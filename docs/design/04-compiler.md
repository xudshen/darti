# Chapter 4: 编译器

## 设计决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 编译器形态 | 独立 CLI 工具（独立 package） | 编译器依赖 `package:kernel`（SDK 级别），运行时不需要 |
| Kernel 加载 | `package:kernel` BinaryBuilder | 正确性有保障，跟随 SDK 升级 |
| 寄存器分配 | LSRA（线性扫描） | 编译在本机，时间不受限；LSRA 生成质量优于简单递增 |
| Bridge 生成 | 预生成库（独立 package） | 常用框架类通过 build_runner 预生成，作为 package 发布 |
| 优化遍 | 编译期全量开启 | 常量折叠、窥孔优化、死代码消除 |

## 编译器架构

```
darti_compiler CLI
  │
  ├── Kernel 加载层
  │   └── package:kernel BinaryBuilder 解析 .dill → Component AST
  │
  ├── 分析阶段
  │   ├── 作用域分析（变量绑定、上值标记）
  │   ├── 类型流分析（确定值栈/引用栈分配）
  │   └── 依赖分析（确定需要的 Bridge 绑定集合）
  │
  ├── 代码生成阶段
  │   ├── Kernel AST → 线性 IR
  │   ├── LSRA 寄存器分配
  │   ├── 字节码发射
  │   └── 常量池构建
  │
  ├── 优化阶段
  │   ├── 常量折叠
  │   ├── 窥孔优化
  │   └── 死代码消除
  │
  └── 序列化输出 → .dartib 文件
```

## Kernel 加载

使用 `package:kernel` 的标准流程：

```dart
import 'package:kernel/kernel.dart';
import 'package:kernel/binary/ast_from_binary.dart';

Component loadKernel(String dillPath) {
  final bytes = File(dillPath).readAsBytesSync();
  final component = Component();
  BinaryBuilder(bytes).readComponent(component);
  return component;
}
```

编译器输入为 **linked-platform .dill**（`dart compile kernel` 默认输出，不使用 `--no-link-platform`）。平台库的 AST 节点完整链接，所有 `Reference`（如 `interfaceTarget`、`target`）均可直接解析。编译器通过 `interfaceTarget.enclosingClass` 等属性识别平台类型，映射到 Bridge 绑定标识。编译器维护一份 **Bridge 注册表**，记录预生成库中可用的绑定符号名：

```dart
class BridgeRegistry {
  // 已知的 Bridge 绑定符号名集合（从预生成库元数据加载）
  final Set<String> _knownBindings = {};

  // 编译期本地绑定表：符号名 → 本地索引（写入 .dartib）
  final List<String> _bindingNames = [];
  final Map<String, int> _nameToLocalIndex = {};

  bool hasBridge(String libraryUri, String className) =>
      _knownBindings.contains('$libraryUri::$className');

  /// 分配本地绑定索引（编译期递增，仅在当前编译单元内有效）
  int getOrAllocLocalIndex(String libraryUri, String className, String member) {
    final name = '$libraryUri::$className::$member';
    return _nameToLocalIndex.putIfAbsent(name, () {
      _bindingNames.add(name);
      return _bindingNames.length - 1;
    });
  }

  /// 输出绑定名称表（写入 .dartib 的绑定名称表段）
  List<String> get bindingNames => _bindingNames;
}
```

编译器遇到对 `dart:core::List.add` 的引用时，通过 `interfaceTarget.enclosingClass` 识别宿主类，查找 Bridge 注册表确认绑定存在，分配一个**本地绑定索引**，生成 `CALL_HOST A, B, C`（A=baseReg, B=argCount, C=本地绑定索引）。如果引用的类未在 Bridge 注册表中，编译器报错。

**编译期与运行时的解耦**：编译器不需要知道运行时 `HostBindings` 的注册顺序。`.dartib` 文件中存储完整的绑定名称表（符号名列表），运行时加载时通过 `HostBindings.lookupByName()` 解析每个符号名为真实的运行时 ID，构建重定位表。这使得编译产物与 Bridge 库版本解耦——只要符号名存在，ID 如何分配无关紧要。详见下方「加载时符号解析」。

## 作用域分析

编译器维护作用域帧栈，解析变量引用为三种绑定：

```dart
enum BindingKind { local, upvalue, global }

class BindingInfo {
  final BindingKind kind;
  final int index;          // 寄存器槽位 / 上值索引 / 全局索引
  final bool isMutable;
  bool isCaptured = false;  // 被闭包捕获
  final StackKind stackKind; // value / ref — 决定存入哪个栈
}

enum StackKind { value, ref }
```

**类型流分析决定 StackKind**：CFE 已在 Kernel AST 中填入完整类型信息。编译器根据变量的静态类型决定分配到值栈还是引用栈：

- `int`, `double`, `bool` → `StackKind.value`（值栈，无装箱）
- 其他所有类型 → `StackKind.ref`（引用栈）
- `dynamic`, `Object?`, `num` → `StackKind.ref`（无法确定，走引用栈装箱路径）

```dart
StackKind classifyType(DartType type) {
  if (type is InterfaceType) {
    final cls = type.classNode;
    if (cls == coreTypes.intClass) return StackKind.value;
    if (cls == coreTypes.doubleClass) return StackKind.value;
    if (cls == coreTypes.boolClass) return StackKind.value;
  }
  return StackKind.ref;
}
```

## 寄存器分配：LSRA

### 从 Kernel AST 构建控制流图

Kernel AST 不是 SSA 形式。编译器先将 AST 转换为线性 IR（基本块序列），然后构建 CFG：

```
Kernel AST → 线性 IR（基本块） → CFG → 活跃区间分析 → LSRA → 字节码发射
```

基本块从以下节点边界划分：
- `IfStatement` → 条件分支产生两个后继块
- `ForStatement` / `WhileStatement` → 循环头和循环体
- `TryCatch` → try 块、catch 处理器块
- `SwitchStatement` → 每个 case 一个块

### 活跃区间计算

每个变量的活跃区间 [start, end) 表示从首次定义到最后一次使用的指令范围：

```dart
class LiveInterval {
  final BindingInfo binding;
  int start;    // 首次定义的 IR 位置
  int end;      // 最后一次使用的 IR 位置
  int? register; // 分配的寄存器编号（null 表示溢出到栈）
}
```

### 分配算法

```dart
void linearScan(List<LiveInterval> intervals) {
  intervals.sort((a, b) => a.start.compareTo(b.start));
  final active = <LiveInterval>[];  // 按 end 排序
  final freeRegs = List.generate(maxRegs, (i) => i);

  for (final interval in intervals) {
    // 1. 过期清理
    active.removeWhere((a) {
      if (a.end <= interval.start) {
        freeRegs.add(a.register!);
        return true;
      }
      return false;
    });

    // 2. 分配或溢出
    if (freeRegs.isNotEmpty) {
      interval.register = freeRegs.removeLast();
      active.add(interval);
      active.sort((a, b) => a.end.compareTo(b.end));
    } else {
      _spill(interval, active, freeRegs);
    }
  }
}
```

**值栈和引用栈独立分配**：两个栈各自维护独立的寄存器池和 LSRA 实例。值栈变量不与引用栈变量竞争寄存器。

### Extension Type 处理

Dart 3 的 extension type 是编译期零成本抽象，在 Kernel AST 中已被 CFE 脱糖为底层表示类型的操作。编译器无需特殊处理——extension type 的方法调用在 Kernel 中表现为普通的静态调用或实例调用，编译器正常生成 `CALL_STATIC` 或 `CALL_VIRTUAL` 即可。

### 溢出处理

当寄存器不足时，选择活跃区间最长的变量溢出到栈帧的溢出区。溢出生成额外的 `MOVE_VAL` / `MOVE_REF` 指令在使用点恢复。由于 Dart 函数通常局部变量不多，溢出在实际中极少发生。

## 控制流编译

### if/else → 条件跳转 + 回填

```dart
void compileIfStatement(IfStatement node) {
  compileExpression(node.condition);
  final elseJump = emitJump(OpCode.JUMP_IF_FALSE);

  compileStatement(node.then);
  final endJump = emitJump(OpCode.JUMP);

  patchJump(elseJump);
  if (node.otherwise != null) {
    compileStatement(node.otherwise!);
  }
  patchJump(endJump);
}
```

### for 循环 → 向后跳转

```dart
void compileForStatement(ForStatement node) {
  enterScope();
  for (final v in node.variables) compileVarDecl(v);

  final loopStart = currentOffset;
  compileExpression(node.condition);
  final exitJump = emitJump(OpCode.JUMP_IF_FALSE);

  compileStatement(node.body);
  for (final update in node.updates) compileExpression(update);
  emitLoop(loopStart);

  patchJump(exitJump);
  exitScope();
}
```

### try/catch → 异常处理器表

不使用内联跳转，而是生成异常处理器表。每个保护区域记录 `(startPC, endPC, handlerPC, catchType, stackDepth)` 元组。运行时查表跳转。

```dart
class ExceptionHandler {
  final int startPC;
  final int endPC;
  final int handlerPC;
  final int catchTypeIndex;  // 常量池中的类型索引，-1 表示 catch-all
  final int stackDepth;      // 进入 try 时的栈深度（用于恢复）
}
```

### switch → 跳转表或二分查找

编译器分析 switch 的 case 值。密集整数 case 生成跳转表指令，稀疏 case 生成二分查找跳转链。Pattern matching（Dart 3）在 Kernel 层已被 CFE 脱糖为 if-else 链。

### for-in 循环 → 迭代器协议

```dart
void compileForInStatement(ForInStatement node) {
  enterScope();
  // r_iter = iterable.iterator
  compileExpression(node.iterable);
  final rIter = allocReg();
  emit(OpCode.CALL_VIRTUAL, rIter, rIterable, icIndex('iterator'));

  final loopStart = currentOffset;
  // r_bool = iter.moveNext()
  final rBool = allocReg();
  emit(OpCode.CALL_VIRTUAL, rBool, rIter, icIndex('moveNext'));
  final exitJump = emitJump(OpCode.JUMP_IF_FALSE);

  // var item = iter.current (getter 调用)
  final rItem = allocReg();
  emit(OpCode.CALL_VIRTUAL, rItem, rIter, icIndex('current'));
  bindVariable(node.variable, rItem);

  compileStatement(node.body);
  emitLoop(loopStart);

  patchJump(exitJump);
  exitScope();
}
```

### Getter / Setter 编译

Kernel 中属性访问统一为 `InstanceGet` / `InstanceSet` 节点。编译器根据 `interfaceTarget` 分发：

- **目标是解释器类的真实字段** → `GET_FIELD_REF` / `GET_FIELD_VAL` / `SET_FIELD_REF` / `SET_FIELD_VAL`
- **目标是 getter/setter `Procedure`** → `CALL_VIRTUAL`（调用 getter/setter 方法）
- **目标是宿主类属性** → `GET_FIELD_DYN` / `SET_FIELD_DYN`（走 HostClassWrapper 路由）

### Assert 语句编译

```dart
void compileAssertStatement(AssertStatement node) {
  if (!enableAsserts) return;  // --no-enable-asserts 时完全省略

  compileExpression(node.condition);
  final skipJump = emitJump(OpCode.JUMP_IF_TRUE);

  // 条件为 false → 执行 ASSERT
  final msgIndex = node.message != null
      ? addConstant(compileConstExpr(node.message!))
      : addConstant(null);
  emit(OpCode.ASSERT, rCondition, msgIndex);

  patchJump(skipJump);
}
```

### Late 变量编译

Kernel 的 `VariableDeclaration` 携带 `isLate` 标志：

- **无初始化器的 late 变量**：声明时存入 `_UNINITIALIZED` 哨兵，读取时检查哨兵并在未初始化时抛出 `LateInitializationError`
- **有初始化器的 late 变量**（`late int x = compute()`）：声明时存哨兵，首次读取时执行初始化器、缓存结果、返回值
- **late final**：首次写入后标记为已初始化，再次写入抛出错误

### 静态字段与顶层变量编译

Kernel 中静态字段为 `Field`（`isStatic = true`），顶层变量为库级 `Field`。编译器为每个分配全局索引：

```dart
void compileStaticFieldAccess(StaticGet node) {
  final globalIndex = _globalRegistry.indexOf(node.target);
  emit(OpCode.LOAD_GLOBAL, destReg, globalIndex);
}
```

初始化器编译为独立的 `FuncProto`，在 `LOAD_GLOBAL` 首次访问时由运行时调用。

### Labeled break / continue

Kernel 保留 `LabeledStatement` 和 `BreakStatement(label)`。编译器维护标签→跳转目标映射：

```dart
void compileLabeledStatement(LabeledStatement node) {
  _labelTargets[node] = _LabelTarget();
  compileStatement(node.body);
  _labelTargets[node]!.exitPC = currentOffset;
  // 回填所有指向此标签的 break 跳转
  for (final jump in _labelTargets[node]!.breakJumps) {
    patchJump(jump);
  }
}

void compileBreakStatement(BreakStatement node) {
  final target = _labelTargets[node.target]!;
  target.breakJumps.add(emitJump(OpCode.JUMP));
}
```

### Const 对象规范化

Kernel 的 `ConstantExpression` 引用 `Constant` 节点（`InstanceConstant`、`ListConstant` 等）。编译器在常量池构建阶段对 const 对象去重：

- 相同结构的 `InstanceConstant`（同 classReference + 同字段值）共享常量池条目
- `LOAD_CONST` 从常量池加载时，`identical()` 保证成立
- 编译器遍历 `Constant` 树递归去重（子常量先去重，父常量再基于子常量的 identity 去重）

### CFE 脱糖确认

以下 Dart 语言特性在 Kernel AST 中已被 CFE 脱糖，编译器正常处理对应的 Kernel 节点即可，无需特殊逻辑：

| 源码特性 | Kernel 表示 |
|----------|------------|
| Cascade (`..`) | 临时变量 + 顺序 `InstanceGet`/`InstanceInvocation` |
| Pattern matching | `IfStatement` 链 |
| Extension methods | `StaticInvocation` |
| Extension types | 擦除为底层表示类型 |
| Constructor tear-offs (`MyClass.new`) | `ConstructorTearOff` → 闭包 |
| Super parameters (`super.x`) | 构造函数参数转发 |
| Named arguments anywhere | 参数已重排至正确位置 |
| Spread collections (`...list`) | 命令式 `add`/`addAll` 调用 |
| List literal (`<int>[1,2,3]`) | `StaticInvocation(_GrowableList._literal3(1, 2, 3))` |
| Control flow collections (`if`/`for` in `[]`) | 命令式展开 |
| Enhanced enums | 普通 `Class` + `Procedure` |
| Wildcards (`_`) | 解析层处理，Kernel 中无痕迹 |
| ++/-- | `VariableSet(x, MethodInvocation(x, '+', 1))` |
| 复合赋值 (+=, ??= 等) | 展开为读取 + 运算 + 写入 |
| 条件表达式 (`a ? b : c`) | `ConditionalExpression` → `JUMP_IF_FALSE` + `JUMP` |
| Type aliases (typedef) | 展开为底层类型引用 |

## 闭包编译

### 上值分析

编译器遍历变量引用，标记被内层函数捕获的变量为 `isCaptured = true`。上值记录来源：

```dart
class UpvalueDesc {
  final bool isLocal;  // true: 直接捕获外层局部变量
  final int index;     // isLocal ? 外层寄存器索引 : 外层上值索引
}
```

### CLOSURE 指令

`CLOSURE A, Bx` 在运行时根据 `funcProto[Bx]` 的上值描述符列表，从当前帧的寄存器或上值表中收集上值，创建 `ClosureObject`。

### CLOSE_UPVALUE 指令

当变量离开作用域且被捕获时，编译器在作用域退出前插入 `CLOSE_UPVALUE A`。运行时将所有指向 >= A 槽位的开放上值关闭（值从栈复制到上值对象内部）。

## 优化遍

编译器在字节码发射后执行优化遍（均在编译期，设备端不执行）：

### 常量折叠

```
LOAD_CONST_INT r1, K1    →  LOAD_CONST_INT r1, (K1+K2)
LOAD_CONST_INT r2, K2
ADD_INT r3, r1, r2
```

### 窥孔优化

```
JUMP +0                  →  (删除)
MOVE_VAL r1, r1          →  (删除)
JUMP_IF_FALSE r, +1      →  (删除，条件跳转跳过的是下一条)
BIT_NOT r1, r2
JUMP_IF_FALSE r1, off    →  JUMP_IF_TRUE r2, off
```

### 死代码消除

移除 `RETURN_*`（`RETURN_REF` / `RETURN_VAL` / `RETURN_NULL`）或 `THROW` 之后到下一个跳转目标之间的不可达指令。

### Superinstruction 候选

分析高频指令序列，在预留 opcode 空间生成合并指令：

```
LOAD_CONST_INT + ADD_INT  →  ADD_INT_IMM (已在 ISA 中预定义)
GET_FIELD_VAL + UNBOX_INT →  GET_FIELD_UNBOX_INT
```

实际的 Superinstruction 集合根据 profiling 数据决定。

## 编译产物格式 (.dartib)

```
DartiB 文件格式
┌─────────────────────────────────┐
│ Magic: 0xDART1B00 (4 bytes)     │
│ Version: UInt32                  │
│ Checksum: UInt32 (CRC32)        │
├─────────────────────────────────┤
│ 绑定名称表                       │
│   [bindingCount]                 │
│   每个条目: 符号名字符串           │
│   (如 "dart:core::List::add")    │
│   字节码中 CALL_HOST 的 C 操作数   │
│   是此表的本地索引                │
├─────────────────────────────────┤
│ 常量池                           │
│   refs: [length, data...]        │
│   ints: [length, data...]        │
│   doubles: [length, data...]     │
│   names: [length, data...]       │
├─────────────────────────────────┤
│ 函数表                           │
│   [funcCount, FuncProto...]      │
│   每个 FuncProto:                │
│     name, paramCount, regCount   │
│     bytecode: Uint32[]           │
│     exceptionTable               │
│     icSlotCount                  │
│     upvalueDescs                 │
│     sourceMap (optional)         │
├─────────────────────────────────┤
│ 类表                             │
│   [classCount, ClassInfo...]     │
│   每个 ClassInfo:                │
│     name, superClassId           │
│     refFieldCount, valueFieldCount│
│     methodTable, typeParamCount  │
├─────────────────────────────────┤
│ 全局变量表                        │
│   [globalCount]                  │
│   每个 GlobalVar:                 │
│     name, initializerFuncId      │
│     (惰性初始化函数引用，-1=无)     │
├─────────────────────────────────┤
│ 入口点: funcId                   │
└─────────────────────────────────┘
```

### 加载时符号解析

运行时加载 .dartib 时执行以下步骤：

1. 校验 magic 和 checksum
2. 读取绑定名称表，对每个符号名调用 `HostBindings.lookupByName()` 解析为运行时 ID，构建**重定位表**
3. 如果任何符号名找不到对应的运行时绑定，加载失败并报告缺失的绑定（在执行前即发现版本不匹配）
4. 将字节码加载到 `Uint32List`，常量池加载到对应的 typed list

```dart
class DartiModule {
  final Uint32List bytecode;
  final List<int> bindingRelocationTable; // localIndex → runtimeId
  // ... 常量池、函数表等

  static DartiModule load(Uint8List bytes, HostBindings hostBindings) {
    // ... 解析文件头、绑定名称表
    final bindingNames = _readBindingNames(bytes);
    final relocationTable = List<int>.filled(bindingNames.length, -1);

    for (var i = 0; i < bindingNames.length; i++) {
      final runtimeId = hostBindings.lookupByName(bindingNames[i]);
      if (runtimeId == null) {
        throw DartiLoadError(
          'Missing host binding: ${bindingNames[i]}. '
          'Ensure the Bridge library version matches the compiler.',
        );
      }
      relocationTable[i] = runtimeId;
    }

    return DartiModule(
      bytecode: _readBytecode(bytes),
      bindingRelocationTable: relocationTable,
      // ...
    );
  }
}
```

执行 `CALL_HOST` 时通过重定位表转换索引：

```dart
case OpCode.CALL_HOST:
  final a = decodeA(instr);     // baseReg
  final b = decodeB(instr);     // argCount
  final localIndex = decodeC(instr);  // 本地绑定索引
  final runtimeId = module.bindingRelocationTable[localIndex];
  final args = [for (int i = 0; i < b; i++) _rs.slots[a + i]];
  final result = hostBindings.invoke(runtimeId, args);
  _rs.slots[a] = result;
```

**序列化与运行时命名映射**：.dartib 的序列化字段名与 Chapter 2 运行时类的字段名存在对应关系：`methodTable` → `ClassInfo.methods`，`refFieldCount`/`valueFieldCount` → `ClassInfo.refFieldCount`/`ClassInfo.valueFieldCount`，`typeParamCount` → `ClassInfo.typeParamCount`。序列化存储紧凑形式（计数值、偏移量），运行时反序列化为结构化对象。
