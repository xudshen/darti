# 基于 Dart Kernel 的高性能字节码解释器与 Dart VM 互调方案

**Dart 语言的 Common Front End（CFE）将源码编译为 Kernel AST 中间表示（.dill 文件），这为构建一个运行于 Dart VM 内部的自定义字节码解释器提供了坚实的基础设施。** 本报告提出一种完整的技术架构：以 `package:kernel` 解析 .dill 文件，将 Kernel AST 编译为自定义 32 位寄存器式字节码，在纯 Dart 实现的高性能分发循环中执行，并通过基于句柄的对象映射机制实现与宿主 Dart VM 之间的双向互操作。该方案的核心价值在于为 Dart 生态引入安全可控的动态代码执行能力——无需修改 Dart VM 本身，即可实现热更新、插件化和沙箱化脚本执行。与现有方案（dart_eval、hetu_script、d4rt）相比，本设计聚焦于字节码层面的性能优化和系统级的互调架构，而非仅仅提供 AST 解释或脚本引擎。

---

## 一、Dart Kernel 中间表示与 .dill 二进制格式

### 1.1 Common Front End 编译管线

自 Dart 2 起，所有 Dart 工具链共享同一个用 Dart 编写的 **Common Front End（CFE）**，位于 `pkg/front_end/`。CFE 的编译管线分为五个阶段：

```
Dart 源码 → [词法分析] → Token 流 → [语法分析] → 原始 AST 
→ [语义分析/类型推断] → Kernel AST → [序列化] → .dill 二进制
```

Dart VM 加载 .dill 文件时采用**惰性解析**策略——首先仅加载库和类的基础信息，每个实体保留一个指回二进制 blob 的指针；类成员在首次查找时才读取，函数体在首次编译时才反序列化。这种设计意味着自定义解释器同样可以按需加载所需的函数体，无需一次性解析整个组件。

使用 `dart compile kernel bin/app.dart` 可直接生成 .dill 文件，也可通过 SDK 中的 `pkg/vm/bin/gen_kernel.dart` 工具指定平台 .dill 进行交叉编译。

### 1.2 .dill 二进制格式的内部结构

.dill 文件采用自描述的二进制格式，其顶层结构 `ComponentFile` 如下：

| 字段 | 类型 | 说明 |
|------|------|------|
| `magic` | UInt32 | **`0x90ABCDEF`**（大端序），用于格式识别 |
| `formatVersion` | UInt32 | 当前主分支为 **126**，与 SDK 版本强绑定 |
| `shortSdkHash` | Byte[10] | 10 字节 SDK 哈希，加载时校验版本一致性 |
| `libraries` | Library[] | 所有库定义 |
| `constants` | List\<Constant\> | 常量池 |
| `canonicalNames` | List\<CanonicalName\> | 层次化命名树 |
| `strings` | StringTable | 共享字符串表 |
| `componentIndex` | ComponentIndex | 随机访问索引 |

格式中使用**变长无符号整数编码（UInt）**：单字节表示 0–127（`0xxxxxxx`），双字节表示至 2^14（`10xxxxxx xxxxxxxx`），四字节表示至 2^30（`11xxxxxx ...`）。**字符串表**通过偏移量数组加 UTF-8 字节流实现紧凑存储。**规范化名称**形成一棵树结构，用于唯一标识库、类和成员——每个 `CanonicalName` 包含一个指向父节点的引用和一个字符串引用。

**ComponentIndex** 是实现随机访问的关键，位于文件尾部，包含源表、常量表、字符串表等各区段的字节偏移量以及每个库的偏移量。读取文件最后 4 字节可获得 `componentFileSizeInBytes`，由此反向定位整个索引结构。多个 .dill 文件可以直接拼接，VM 会依次读取。

### 1.3 package:kernel 的 Visitor 模式与 AST 遍历

`package:kernel` 定义了完整的 Kernel AST 节点层次和多种 Visitor 接口。所有节点继承自 `Node`，实现 `accept<R>(Visitor<R> v)` 和 `visitChildren(Visitor v)` 方法。

**核心 AST 节点类型**包括：`Component`（根容器）→ `Library`（库）→ `Class`（类）→ `Procedure`/`Constructor`/`Field`（成员）。`FunctionNode` 是函数表示的核心，携带 `asyncMarker`（Sync/Async/SyncStar/AsyncStar）、类型参数、形参列表、返回类型和函数体。表达式子类涵盖 `InstanceInvocation`、`ConstructorInvocation`、`FunctionExpression`（闭包）、`AwaitExpression` 等数十种节点；语句子类包含 `IfStatement`、`ForStatement`、`TryCatch`、`YieldStatement` 等。Dart 3.x 新增了 `RecordLiteral`、`ExtensionTypeDeclaration` 等节点。

Visitor 体系提供了**级联默认机制**——`TreeVisitor` 中 `visitVariableGet` 默认回落到 `defaultExpression`，再到 `defaultTreeNode`，最终到 `defaultNode`，允许通过单一覆写捕获整类节点。关键 Visitor 包括：

- **`RecursiveVisitor`**：深度优先遍历所有节点，`defaultNode` 调用 `node.visitChildren(this)` 驱动递归
- **`Transformer`**：访问时可替换节点，用于 Kernel-to-Kernel 变换
- **`ExpressionVisitor`/`StatementVisitor`/`DartTypeVisitor`**：分类专用访问器

以下代码展示如何加载 .dill 文件并遍历 AST：

```dart
import 'dart:io';
import 'package:kernel/kernel.dart';
import 'package:kernel/binary/ast_from_binary.dart';

void main() {
  final bytes = File('app.dill').readAsBytesSync();
  final component = Component();
  BinaryBuilder(bytes).readComponent(component);

  for (final library in component.libraries) {
    print('Library: ${library.importUri}');
    for (final cls in library.classes) {
      for (final proc in cls.procedures) {
        print('  ${cls.name}.${proc.name.text}');
      }
    }
  }
}

/// 统计所有实例方法调用
class InvocationCounter extends RecursiveVisitor {
  int count = 0;
  @override
  void visitInstanceInvocation(InstanceInvocation node) {
    count++;
    super.visitInstanceInvocation(node);
  }
}
```

---

## 二、虚拟机架构设计与指令集

### 2.1 寄存器架构与栈架构的抉择

学术研究（Shi 等人 2008 年的 *Virtual Machine Showdown*、Šimek 等人 2025 年的对比实验）给出了明确的量化结论：**寄存器式 VM 比栈式 VM 减少约 46% 的指令执行次数**，在 switch 分发下快约 **32%**，在线程分发下快约 **27%**，代价仅是字节码体积增大约 26%。

本方案选择**寄存器架构**，理由如下：指令编码可同时携带源和目标操作数，减少隐式 push/pop 操作；寄存器映射为栈帧内的偏移量（类似 Lua 的窗口寄存器），与 Dart VM 自身曾使用的 KBC 设计一致；对于 Dart 宿主的 switch 分发场景，减少指令数带来的收益更为显著。

Dart VM 曾实验性地实现过 KBC（Kernel Bytecode）解释器——一个寄存器式字节码格式，寄存器指向栈帧内的槽位（负偏移量 `FP[n]` 用于局部变量/参数，正偏移量 `rN` 用于虚拟寄存器）。虽然 KBC 已于 2020-2021 年间从 VM 中移除（当前 VM 直接从 Kernel AST 编译到原生代码），但其设计为本方案提供了重要参考。

### 2.2 32 位指令编码方案

采用固定 32 位宽度指令，**8 位操作码**（最多 256 条指令，字节对齐简化解码）加 24 位操作数空间，支持多种编码格式：

| 格式 | 布局 | 用途 |
|------|------|------|
| `ABC` | `[op:8][A:8][B:8][C:8]` | 三操作数运算（如 `ADD R(A), R(B), R(C)`） |
| `ABx` | `[op:8][A:8][Bx:16]` | 寄存器+无符号立即数（如常量加载） |
| `AsBx` | `[op:8][A:8][sBx:16]` | 寄存器+有符号偏移（如条件跳转） |
| `Ax` | `[op:8][Ax:24]` | 大范围立即数/跳转目标 |

编码与解码操作使用位运算实现，在 Dart 中以 `Uint32List` 存储可获得最佳性能：

```dart
/// 指令编码
int encodeABC(int op, int a, int b, int c) =>
    op | (a << 8) | (b << 16) | (c << 24);

int encodeABx(int op, int a, int bx) =>
    op | (a << 8) | (bx << 16);

/// 指令解码
int decodeOp(int instr) => instr & 0xFF;
int decodeA(int instr) => (instr >> 8) & 0xFF;
int decodeB(int instr) => (instr >> 16) & 0xFF;
int decodeC(int instr) => (instr >> 24) & 0xFF;
int decodeBx(int instr) => (instr >> 16) & 0xFFFF;
int decodesBx(int instr) => decodeBx(instr) - 0x7FFF; // excess-K 编码
```

### 2.3 核心操作码设计

参考 Dart VM KBC 和 Lua 5.4 的指令集，定义以下核心操作码：

```dart
abstract class OpCode {
  // 加载/存储
  static const int loadConst   = 0x01;  // ABx: R(A) = K(Bx)
  static const int loadNull    = 0x02;  // A:   R(A) = null
  static const int move        = 0x03;  // AB:  R(A) = R(B)
  static const int loadUpvalue = 0x04;  // ABx: R(A) = Upvalue(Bx)
  static const int storeUpvalue= 0x05;  // ABx: Upvalue(Bx) = R(A)

  // 算术运算
  static const int addInt      = 0x10;  // ABC: R(A) = R(B) + R(C)  [int]
  static const int addDouble   = 0x11;  // ABC: R(A) = R(B) + R(C)  [double]
  static const int addGeneric  = 0x12;  // ABC: R(A) = R(B).+(R(C)) [dynamic]

  // 比较与逻辑
  static const int lt          = 0x20;  // ABC: R(A) = R(B) < R(C)
  static const int eq          = 0x21;  // ABC: R(A) = R(B) == R(C)

  // 控制流
  static const int jump        = 0x30;  // sBx: PC += sBx
  static const int jumpIfFalse = 0x31;  // AsBx: if !R(A) then PC += sBx
  static const int jumpIfTrue  = 0x32;  // AsBx: if R(A) then PC += sBx

  // 调用
  static const int call        = 0x40;  // ABC: R(A) = R(B)(R(B+1)..R(B+C))
  static const int callHost    = 0x41;  // ABx: R(A) = HostFunc(Bx)(args...)
  static const int ret         = 0x42;  // A:   return R(A)

  // 对象操作
  static const int getField    = 0x50;  // ABx: R(A) = R(B).field(Kx)
  static const int setField    = 0x51;  // ABx: R(A).field(Kx) = R(B)
  static const int newInstance = 0x52;  // ABx: R(A) = new Class(Bx)

  // 闭包与异步
  static const int closure     = 0x60;  // ABx: R(A) = Closure(DarticFuncProto(Bx))
  static const int awaitFuture = 0x61;  // A:   suspend, await R(A)

  // 系统
  static const int halt        = 0xFF;  // 停机
}
```

### 2.4 内存模型与栈帧布局

采用**双栈架构**，将无装箱数值与对象引用分离存储：

```
栈帧布局（寄存器窗口映射到栈槽）
┌──────────────────────────────────┐  高地址
│ 调用者帧                          │
├──────────────────────────────────┤
│ 参数 arg0, arg1, ...             │  ← R(-N) .. R(-1)
├──────────────────────────────────┤
│ 返回地址 (PC)                     │
│ 保存的帧指针 (FP)                 │
│ 函数原型引用                      │
├──────────────────────────────────┤ ← FP
│ 局部变量 local0, local1, ...     │  ← R(0) .. R(M)
│ 临时寄存器 tmp0, tmp1, ...       │  ← R(M+1) ..
├──────────────────────────────────┤ ← SP
│ （空闲空间）                      │
└──────────────────────────────────┘  低地址
```

双栈设计的核心数据结构：

```dart
class VMState {
  /// 值栈：存储无装箱的 int/double/bool（作为 double 编码）
  final Float64List valueStack;
  int vsp = 0;

  /// 引用栈：存储 Dart 对象引用（String、List、闭包等）
  final List<Object?> refStack;
  int rsp = 0;

  /// 调用栈：存储返回地址和帧元数据
  final Uint32List callStack;
  int fp = 0;

  /// 指令存储
  final Uint32List code;
  int pc = 0;
}
```

`Float64List` 上的算术操作会被 Dart VM JIT 编译为无装箱的浮点运算，完全避免 GC 压力。`List<Object?>` 则正确参与 Dart 的垃圾回收——弹出元素时需置 null 以防止过期引用。

---

## 三、编译器实现：从 Kernel AST 到字节码

### 3.1 作用域分析与变量解析

编译器维护一个**作用域帧栈**，每个帧是变量名到绑定信息（槽位索引、是否可变、是否被捕获）的映射。变量引用的解析算法：

1. 从最内层作用域向外搜索
2. 在当前函数作用域内找到 → **局部变量**，分配寄存器槽位
3. 在外层函数作用域找到 → **上值（upvalue）**，标记被捕获
4. 全局作用域找到 → **全局变量**，通过常量池索引访问

```dart
class ScopeAnalyzer extends RecursiveVisitor {
  final List<Map<String, BindingInfo>> _scopeStack = [{}];
  int _nextSlot = 0;

  void _enterScope() => _scopeStack.add({});
  void _exitScope() => _scopeStack.removeLast();

  BindingInfo _resolve(String name) {
    for (int i = _scopeStack.length - 1; i >= 0; i--) {
      final binding = _scopeStack[i][name];
      if (binding != null) {
        if (i < _currentFunctionDepth) {
          binding.isCaptured = true; // 标记为上值
        }
        return binding;
      }
    }
    return BindingInfo.global(name);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _scopeStack.last[node.name!] = BindingInfo.local(_nextSlot++);
    super.visitVariableDeclaration(node);
  }
}
```

### 3.2 闭包与上下文捕获机制

闭包实现借鉴 Crafting Interpreters 的**开放上值（open upvalue）**模型。编译时，每个上值记录两种来源：

- `isLocal=true, index=N`：直接捕获外层函数的局部变量槽位 N
- `isLocal=false, index=M`：间接捕获外层函数的上值槽位 M（传递捕获）

运行时，上值对象持有指向栈槽的引用。当变量离开作用域时，执行**关闭操作**——将值从栈复制到上值对象内部，重定向引用指针：

```dart
class Upvalue {
  /// 开放状态：指向值栈中的槽位索引
  int? stackSlot;
  /// 关闭状态：持有拷贝的值
  Object? closedValue;

  bool get isOpen => stackSlot != null;

  Object? get value => isOpen
      ? _vm.refStack[stackSlot!]
      : closedValue;

  void close(Object? currentValue) {
    closedValue = currentValue;
    stackSlot = null;
  }
}

class ClosureObject {
  final FunctionPrototype proto;
  final List<Upvalue> upvalues;
  ClosureObject(this.proto, this.upvalues);
}
```

VM 维护一个按栈槽排序的**开放上值链表**，确保多个闭包捕获同一变量时共享同一个 `Upvalue` 对象。`CLOSE_UPVALUE` 指令在作用域退出时关闭所有指向即将失效槽位的上值。

### 3.3 控制流扁平化

**if/else** 编译为条件跳转加回填（backpatching）：

```dart
void _compileIfStatement(IfStatement node) {
  _compileExpression(node.condition);
  final elseJump = _emitJump(OpCode.jumpIfFalse); // 占位，待回填

  _compileStatement(node.then);
  final endJump = _emitJump(OpCode.jump);

  _patchJump(elseJump); // 回填 else 分支目标
  if (node.otherwise != null) {
    _compileStatement(node.otherwise!);
  }
  _patchJump(endJump); // 回填结束目标
}
```

**for 循环** 编译为向后跳转，`break` 和 `continue` 使用跳转目标栈管理：

```dart
void _compileForStatement(ForStatement node) {
  _enterScope();
  for (final v in node.variables) _compileVariableDeclaration(v);

  final loopStart = _currentOffset;
  _compileExpression(node.condition);
  final exitJump = _emitJump(OpCode.jumpIfFalse);

  _compileStatement(node.body);
  for (final update in node.updates) _compileExpression(update);
  _emitLoop(loopStart); // 向后跳转

  _patchJump(exitJump);
  _exitScope();
}
```

**try-catch** 编译为**异常表**而非内联跳转——每个保护区域记录 `(startPC, endPC, handlerPC, catchType)` 元组。当解释器执行期间抛出异常时，查找当前 PC 所在的保护区域，跳转到对应处理器并将异常对象存入指定寄存器。

---

## 四、Dart VM 与自定义解释器的双向互调机制

**这是本方案的架构核心。** 互调机制需要解决四个根本问题：对象如何跨越边界传递、解释器如何调用宿主函数、宿主如何回调解释器函数、以及如何保证并发安全。

### 4.1 成熟 VM 互调设计的启示

在设计互调架构之前，有必要回顾业界成熟方案的共性模式：

**Lua C API** 使用**栈作为唯一通信通道**——所有参数传递、返回值获取都通过 `lua_push*` / `lua_to*` 操作虚拟栈完成。C 函数统一签名为 `int f(lua_State *L)`，参数从栈读取，返回值推入栈，返回计数作为 C 返回值。Userdata + metatable 机制将 C 对象包装为 Lua 可操作的值。

**JVM JNI** 使用**句柄引用系统**——`jobject` 是不透明句柄，分为 Local（函数调用期间有效）、Global（手动释放）、Weak Global 三种生命周期。通过 `JNIEnv*` 方法指针表进行所有操作。异常通过侧通道传播（挂起异常标志）。

**V8 嵌入 API** 使用**HandleScope 管理的句柄层次**——`Local<T>` 在作用域退出时自动失效，`Global<T>` 持久存在。`FunctionTemplate` + `ObjectTemplate` 用于将 C++ 函数/对象暴露给 JavaScript。`TryCatch` 对象捕获边界异常。

四种 VM 互调设计的**共性模式**：

- **句柄间接层**：所有 VM 都使用句柄而非原始指针，为 GC 提供间接层
- **错误传播非对称性**：异常无法直接跨边界传播，需要侧通道（保护调用、挂起异常、TryCatch）
- **边界穿越成本**：参数编组/解组、句柄创建、GC 屏障操作均产生开销
- **可重入支持**：支持 Host→VM→Host→VM 的嵌套调用链

### 4.2 基于句柄的对象映射机制

本方案采用**整数句柄表**作为对象映射的核心，设计理念借鉴 JNI 的引用管理和 V8 的 HandleScope：

```dart
class HandleScope {
  final HandleTable _table;
  final List<int> _localHandles = [];

  HandleScope(this._table);

  /// 注册一个宿主对象，返回解释器可使用的整数句柄
  int register(Object obj) {
    final handle = _table.allocate(obj);
    _localHandles.add(handle);
    return handle;
  }

  /// 作用域退出时释放所有局部句柄
  void dispose() {
    for (final h in _localHandles) {
      _table.release(h);
    }
  }
}

class HandleTable {
  final List<Object?> _slots = [];
  final Queue<int> _freeList = Queue<int>();
  int _size = 0;

  int allocate(Object obj) {
    int slot;
    if (_freeList.isNotEmpty) {
      slot = _freeList.removeFirst();
    } else {
      slot = _size++;
      _slots.add(null);
    }
    _slots[slot] = obj;
    return slot;
  }

  Object? get(int handle) {
    assert(handle >= 0 && handle < _size);
    return _slots[handle];
  }

  void release(int handle) {
    _slots[handle] = null; // 允许 GC 回收
    _freeList.add(handle);
  }
}
```

在解释器的引用栈中，宿主对象以句柄形式存在；在值栈中，基本类型（int、double、bool）直接以无装箱形式存储。**类型判别**通过指令中的类型标签实现——编译器在生成字节码时已确定操作数是值类型还是引用类型，分别使用值栈操作或引用栈操作。

### 4.3 外调：解释器调用宿主 VM 函数

外调（outcall）是解释器执行过程中需要调用宿主 Dart VM 的函数或方法。本方案设计三层外调机制：

**第一层：注册函数表（轻量级）**

```dart
class HostBindings {
  final Map<String, Function> _functions = {};

  void register(String name, Function fn) => _functions[name] = fn;

  Object? invoke(String name, List<Object?> args) {
    final fn = _functions[name];
    if (fn == null) throw InterpreterError('Unbound host function: $name');
    return Function.apply(fn, args);
  }
}

// 注册示例
final bindings = HostBindings()
  ..register('print', (Object? value) => print(value))
  ..register('DateTime.now', () => DateTime.now())
  ..register('math.sqrt', (num x) => math.sqrt(x));
```

在字节码中，`CALL_HOST` 指令携带函数名的常量池索引。解释器遇到此指令时，从常量池取出函数名，查找注册表，将参数从解释器栈转换为 Dart `List<Object?>`，调用宿主函数，将返回值推回解释器栈。

**第二层：包装器类（结构化访问）**

借鉴 dart_eval 的 `$Instance` 模式，为每个需要交互的宿主类生成包装器：

```dart
/// 包装器接口
abstract class HostClassWrapper {
  Object get hostObject;
  Object? getProperty(String name);
  void setProperty(String name, Object? value);
  Object? invokeMethod(String name, List<Object?> args);
}

/// 自动生成的 List 包装器示例
class ListWrapper implements HostClassWrapper {
  @override
  final List hostObject;
  ListWrapper(this.hostObject);

  @override
  Object? getProperty(String name) => switch (name) {
    'length' => hostObject.length,
    'isEmpty' => hostObject.isEmpty,
    'first' => hostObject.first,
    _ => throw InterpreterError('Unknown property: List.$name'),
  };

  @override
  Object? invokeMethod(String name, List<Object?> args) => switch (name) {
    'add' => hostObject.add(args[0]),
    'removeAt' => hostObject.removeAt(args[0] as int),
    'map' => hostObject.map((e) => _invokeCallback(args[0], [e])),
    'where' => hostObject.where((e) => _invokeCallback(args[0], [e]) as bool),
    _ => throw InterpreterError('Unknown method: List.$name'),
  };
}
```

**第三层：基于 Kernel 元数据的自动绑定生成器**

手动编写每个标准库类的包装器不可扩展。自动绑定生成器利用 `package:kernel` 分析目标库的 .dill 文件，自动生成包装代码：

```dart
class BindingGenerator extends RecursiveVisitor {
  final StringBuffer _output = StringBuffer();

  @override
  void visitClass(Class node) {
    final className = node.name;
    _output.writeln('class ${className}Wrapper implements HostClassWrapper {');
    _output.writeln('  @override final $className hostObject;');
    _output.writeln('  ${className}Wrapper(this.hostObject);');

    // 生成属性访问
    _output.writeln('  @override Object? getProperty(String name) {');
    _output.writeln('    switch (name) {');
    for (final field in node.fields) {
      if (!field.name.text.startsWith('_')) {
        _output.writeln(
          "      case '${field.name.text}': return hostObject.${field.name.text};");
      }
    }
    _output.writeln('      default: throw InterpreterError(name);');
    _output.writeln('    }');
    _output.writeln('  }');

    // 生成方法调用
    _output.writeln('  @override Object? invokeMethod(String name, List<Object?> args) {');
    _output.writeln('    switch (name) {');
    for (final proc in node.procedures) {
      if (proc.isPublic && proc.kind == ProcedureKind.Method) {
        _generateMethodBinding(proc);
      }
    }
    _output.writeln('      default: throw InterpreterError(name);');
    _output.writeln('    }');
    _output.writeln('  }');
    _output.writeln('}');
  }
}
```

生成器从平台 .dill 文件读取 `dart:core`、`dart:math`、`dart:collection` 等库的类定义，自动产生完整的包装器代码。对于**泛型类**，生成器产生参数化的包装器模板；对于**扩展方法**，通过 Kernel 的 `Extension` 节点识别并生成对应的静态方法绑定。

### 4.4 内调：宿主 VM 回调解释器函数

内调（incall）发生在宿主 Dart 代码需要调用解释器中定义的函数时——例如将解释器函数作为回调传递给宿主 API（如 `List.map`、`Future.then`、事件处理器等）。

**回调代理模式**是核心解决方案：

```dart
/// 将解释器中的函数包装为宿主 Dart 可调用的闭包
class DarticCallbackProxy {
  final Interpreter _interpreter;
  final ClosureObject _closure;

  DarticCallbackProxy(this._interpreter, this._closure);

  /// 生成不同签名的代理闭包
  Object? Function() proxy0() {
    return () => _interpreter.invokeClosure(_closure, []);
  }

  Object? Function(Object?) proxy1() {
    return (a) => _interpreter.invokeClosure(_closure, [a]);
  }

  Object? Function(Object?, Object?) proxy2() {
    return (a, b) => _interpreter.invokeClosure(_closure, [a, b]);
  }

  /// 生成满足特定类型签名的代理
  T typedProxy<T extends Function>() {
    // 根据 T 的运行时类型信息选择正确的代理
    if (T == int Function(int)) {
      return ((int a) =>
          _interpreter.invokeClosure(_closure, [a]) as int) as T;
    }
    if (T == bool Function(dynamic)) {
      return ((dynamic a) =>
          _interpreter.invokeClosure(_closure, [a]) as bool) as T;
    }
    throw InterpreterError('Unsupported callback type: $T');
  }
}
```

当解释器编译后的代码将闭包传递给宿主 API 时（如 `list.where(callback)`），`CALL_HOST` 指令的绑定实现需要识别参数中的闭包对象，自动创建 `DarticCallbackProxy` 并传递给宿主方法：

```dart
// ListWrapper.invokeMethod 中的 'where' 处理
case 'where':
  final closure = args[0] as ClosureObject;
  final proxy = DarticCallbackProxy(interpreter, closure);
  return hostObject.where(proxy.typedProxy<bool Function(dynamic)>());
```

**noSuchMethod 代理**提供了另一条路径，但受限于必须在编译时静态声明 `implements` 的接口：

```dart
class InterpreterProxy implements Comparable<dynamic> {
  final Interpreter _interpreter;
  final ClosureObject _dispatch;

  InterpreterProxy(this._interpreter, this._dispatch);

  @override
  noSuchMethod(Invocation inv) {
    final args = [...inv.positionalArguments];
    return _interpreter.invokeClosure(_dispatch, args);
  }
}
```

### 4.5 dart:ffi 在互调中的角色

当解释器的性能关键路径需要进一步优化时，可以将分发循环核心用 C 实现，通过 `dart:ffi` 桥接。此时 `NativeCallable` 成为关键组件：

**`NativeCallable.isolateLocal`** 可将 Dart 闭包转换为原生函数指针，但**必须在同一线程调用**，适合 C 分发循环同步回调 Dart 宿主函数。**`NativeCallable.listener`** 可跨线程调用但仅支持 void 返回且异步执行，适合从后台解释线程通知主 isolate。

```dart
/// 通过 FFI 暴露宿主函数给原生解释器核心
final callHostFn = NativeCallable<Int64 Function(Int32, Pointer<Void>)>
    .isolateLocal(
  (int funcId, Pointer<Void> argsPtr) {
    final args = _unmarshalArgs(argsPtr);
    final result = hostBindings.invokeById(funcId, args);
    return _marshalResult(result);
  },
);
// 将 callHostFn.nativeFunction 传递给 C 分发循环
```

**并发安全约束**：`NativeCallable.isolateLocal` 若从错误线程调用会导致进程终止。如果解释器运行在独立 Isolate 中，跨 Isolate 通信只能通过 `SendPort`/`ReceivePort` 的消息传递，不能共享可变状态。`TransferableTypedData` 可实现字节码数据的零拷贝跨 Isolate 传输。

### 4.6 互调数据流的完整生命周期

以一个完整的互调场景说明数据流：

```dart
// 宿主代码
final interpreter = BytecodeInterpreter();
interpreter.hostBindings
  ..register('fetchData', (String url) async => await http.get(Uri.parse(url)));

// 解释器执行的脚本（编译前的源码）
// var result = fetchData("https://api.example.com/data");
// var items = result.body.split(",");
// items.where((item) => item.length > 3);

// 执行流程：
// 1. LOAD_CONST "https://..."     → 字符串常量加载到引用栈
// 2. CALL_HOST 'fetchData'         → 从引用栈取出参数 → 调用宿主函数
//    → 宿主函数返回 Response 对象 → 注册到句柄表 → 句柄推入引用栈
// 3. GET_FIELD 'body'              → 通过句柄查找 Response 对象
//    → ResponseWrapper.getProperty('body') → 返回 String → 新句柄推入
// 4. CALL_METHOD 'split'           → StringWrapper.invokeMethod('split', [","])
//    → 返回 List<String> → 新句柄推入
// 5. CALL_METHOD 'where'           → 参数是解释器闭包
//    → ListWrapper 创建 DarticCallbackProxy
//    → 宿主 List.where 每次迭代回调 proxy → proxy 调用 interpreter.invokeClosure
//    → 解释器执行闭包体 → 返回 bool 给宿主
```

---

## 五、高性能运行时优化

### 5.1 分发循环优化策略

Dart 语言不支持 computed goto（GCC 的 `&&label` 扩展），因此 Dart 宿主解释器的分发循环以 `switch` 为主要机制。Dart VM 的 JIT 编译器会将密集 switch 优化为**跳转表**，在操作码连续且密集时性能接近间接跳转。

关键优化手段：

**操作码特化（Superinstructions）**：将高频操作码序列合并为单一操作码，减少分发次数。例如 `LOAD_LOCAL` + `ADD_INT` 可合并为 `ADD_LOCAL_INT`：

```dart
case OpCode.addLocalInt:
  // 一条指令完成：R(A) = locals[B] + R(C)
  final a = decodeA(instr);
  final b = decodeB(instr);
  final c = decodeC(instr);
  valueStack[a] = valueStack[b] + valueStack[c];
  break;
```

**指令缓存局部性**：将分发循环主体控制在约 16KB 以内（参考 Luau 的实践），确保完整循环体驻留在 CPU L1 指令缓存中。

**`Uint32List` 指令存储**带来的性能优势：每条指令仅 4 字节，顺序访问时 CPU 缓存行（64 字节）可容纳 16 条指令；无装箱开销，`Uint32List` 在 Dart VM 内部作为定长类型数组直接映射到连续内存；索引访问被 JIT 编译为单条内存加载指令加边界检查（在循环中检查通常被消除）。

### 5.2 内联缓存实现

内联缓存（IC）是优化动态方法分发的核心技术。基于 Deutsch & Schiffman（1984）的原始设计和 V8 Ignition 的反馈向量实现，本方案在每个 `CALL_METHOD` 字节码位置关联一个 IC 条目：

```dart
class InlineCache {
  // 单态缓存（命中率约 90%）
  int cachedClassId = -1;
  HostClassWrapper? cachedWrapper;

  // 多态缓存（2-4 条目）
  static const int maxPoly = 4;
  final Int32List polyClassIds = Int32List(maxPoly);
  final List<HostClassWrapper?> polyWrappers = List.filled(maxPoly, null);
  int polySize = 0;

  /// 快速查找
  HostClassWrapper? lookup(int classId) {
    if (cachedClassId == classId) return cachedWrapper; // 单态命中
    for (int i = 0; i < polySize; i++) {
      if (polyClassIds[i] == classId) {
        // 提升为单态位置（MRU 策略）
        cachedClassId = classId;
        cachedWrapper = polyWrappers[i];
        return cachedWrapper;
      }
    }
    return null; // 未命中，走慢路径
  }
}
```

**Quickening 优化**：当 IC 观察到某调用点始终处理 `int` 类型时，将通用 `ADD_GENERIC` 指令**就地改写**为特化的 `ADD_INT`。若后续类型守卫失败，回退为通用版本。这种优化参考了 CPython 的 Adaptive Interpreter 和 V8 的 bytecode quickening。

### 5.3 常量折叠与窥孔优化

编译器在生成字节码后执行一趟**窥孔优化遍**：

- `LOAD_CONST k1; LOAD_CONST k2; ADD` → `LOAD_CONST (k1+k2)`（常量折叠）
- `JUMP +0` → 删除（空跳转消除）
- `LOAD_LOCAL n; STORE_LOCAL n` → 删除（冗余移动消除）
- `NOT; JUMP_IF_FALSE` → `JUMP_IF_TRUE`（条件反转）

---

## 六、异步模型与并发处理

### 6.1 async/await 的 Kernel 层脱糖

Dart 编译器通过 `pkg/kernel/lib/transformations/async.dart` 将 async 函数变换为状态机。变换结果在 Kernel AST 中表现为：引入控制变量 `:await_jump_var`（状态编号）和 `:await_ctx_var`（等待上下文），函数体改写为 switch 分发结构，每个 `await` 点成为一个状态转移边界。

自定义编译器可选择**两种策略**处理 async：

**策略一：在 Kernel 层完成脱糖后再编译。** 直接使用 Kernel 的 async 变换，将状态机代码作为普通同步代码编译为字节码。优点是编译器无需特殊处理，缺点是生成的字节码较冗长。

**策略二：保留 async 语义，在字节码层实现挂起/恢复。** 编译器保留 `AwaitExpression` 的语义，生成 `AWAIT_FUTURE` 指令。解释器遇到此指令时保存执行状态并返回一个 `Future`：

```dart
class AsyncExecutionContext {
  final Uint32List code;
  int savedPC;
  final Float64List savedValueStack;
  int savedVSP;
  final List<Object?> savedRefStack;
  int savedRSP;
  final Completer<Object?> completer;

  AsyncExecutionContext({
    required this.code,
    required this.savedPC,
    required Float64List valueStack,
    required this.savedVSP,
    required List<Object?> refStack,
    required this.savedRSP,
  })  : savedValueStack = Float64List.fromList(
            valueStack.sublist(0, savedVSP)),
        savedRefStack = List<Object?>.from(
            refStack.sublist(0, savedRSP)),
        completer = Completer<Object?>();
}

/// 解释器的异步执行入口
Future<Object?> executeAsync(Uint32List code) async {
  while (true) {
    final result = _executeUntilSuspend(code);
    if (result is _SuspendSignal) {
      // 解释器在 AWAIT_FUTURE 处挂起
      final future = result.awaitedFuture as Future;
      try {
        final value = await future; // 让出给 Dart 事件循环
        _pushResult(value);         // 将结果推回解释器栈
      } catch (e, s) {
        _pushException(e, s);       // 异常处理
      }
      continue; // 恢复执行
    }
    return result; // 脚本执行完毕
  }
}
```

**关键设计**：由于解释器的"栈"是 Dart 数据结构（`Float64List` / `List<Object?>`），而非 C 调用栈，挂起仅需保存 PC 和栈指针——这正是 Lua 协程的核心洞察（"解释器不应使用其内部 C 栈来实现被解释代码的调用"）。

### 6.2 与宿主事件循环的集成

解释器通过 `Completer` 和 `Future` 与 Dart 的事件循环自然集成。为避免长时间阻塞事件循环，引入**指令预算机制**：

```dart
Object? _executeWithBudget(int maxInstructions) {
  int budget = maxInstructions;
  while (budget-- > 0) {
    final instr = code[pc++];
    switch (decodeOp(instr)) {
      case OpCode.awaitFuture:
        return _SuspendSignal(refStack[--rsp] as Future);
      case OpCode.halt:
        return refStack[--rsp];
      // ... 其他操作码
    }
  }
  return _YieldSignal(); // 预算耗尽，让出控制权
}

/// 协作式调度
Future<Object?> runCooperatively() async {
  while (true) {
    final result = _executeWithBudget(10000);
    if (result is _YieldSignal) {
      await Future<void>.delayed(Duration.zero); // 让出给事件循环
      continue;
    }
    if (result is _SuspendSignal) {
      final value = await result.awaitedFuture;
      _pushResult(value);
      continue;
    }
    return result;
  }
}
```

### 6.3 Isolate 隔离与安全

解释器默认运行在主 Isolate，可以直接访问所有宿主对象。当需要**计算密集型执行**时，可将解释器移至独立 Isolate：

- 字节码通过 `TransferableTypedData` 零拷贝传输
- 宿主对象不能跨 Isolate 共享，需序列化为消息
- 回调必须通过 `SendPort`/`ReceivePort` 异步通信
- 适合纯计算场景，不适合需要密集互调的场景

对于新版 Dart（3.7+）的共享内存实验特性，`NativeCallable.isolateGroupShared` 允许跨 Isolate 调用无状态函数，可能为未来的并行解释器执行开辟新路径。

---

## 七、安全性与沙箱化设计

### 7.1 基于能力的安全模型

借鉴 WebAssembly/WASI 的能力安全模型——沙箱内代码**没有默认权限**，只能使用显式授予的能力：

```dart
class SandboxCapabilities {
  final bool networkAccess;
  final bool fileSystemAccess;
  final bool processSpawn;
  final bool isolateCreation;
  final Set<String> allowedHostAPIs;
  final int maxMemoryBytes;
  final int maxInstructionCount;
  final int maxCallDepth;
  final Duration maxWallTime;

  const SandboxCapabilities.minimal()
      : networkAccess = false,
        fileSystemAccess = false,
        processSpawn = false,
        isolateCreation = false,
        allowedHostAPIs = const {'dart:core.*', 'dart:math.*', 'dart:collection.*'},
        maxMemoryBytes = 10 * 1024 * 1024,
        maxInstructionCount = 10000000,
        maxCallDepth = 256,
        maxWallTime = const Duration(seconds: 10);
}
```

**危险 API 隔离**：`dart:io`（文件/网络/进程）、`dart:ffi`（原生内存访问）、`dart:mirrors`（反射）、`dart:developer`（调试）和 `dart:isolate`（并发创建）默认禁止。自动绑定生成器在生成桥接代码时需过滤这些库。

### 7.2 字节码验证

执行前进行静态验证，参考 JVM 字节码验证器的设计：

```dart
class DarticVerifier {
  bool verify(Uint32List code, FunctionMetadata meta) {
    int stackDepth = 0;
    final stackAtPC = <int, int>{}; // PC → 预期栈深度

    for (int pc = 0; pc < code.length; pc++) {
      // 汇合点栈深度一致性检查
      if (stackAtPC.containsKey(pc) && stackAtPC[pc] != stackDepth) {
        return false;
      }
      stackAtPC[pc] = stackDepth;

      final op = decodeOp(code[pc]);
      stackDepth += _stackDelta(op);

      // 栈溢出/下溢检查
      if (stackDepth < 0 || stackDepth > meta.maxStackDepth) return false;

      // 跳转目标有效性检查
      if (_isJump(op)) {
        final target = pc + decodesBx(code[pc]);
        if (target < 0 || target >= code.length) return false;
      }

      // 常量池索引越界检查
      if (_accessesConstPool(op)) {
        final idx = decodeBx(code[pc]);
        if (idx >= meta.constPoolSize) return false;
      }
    }
    return true;
  }
}
```

**运行时防护**包括：指令计数器防无限循环、调用深度检查防栈溢出、内存分配配额防耗尽。字节码存储使用 `UnmodifiableUint32ListView` 防止自修改。

---

## 八、现有方案分析与本设计的定位

### 8.1 社区项目的经验与局限

**dart_eval** 是当前最成熟的 Dart 解释器（GitHub 383★），采用 `package:analyzer` 解析 → 自定义字节码编译 → 栈式 VM 执行的架构。其三层互操作体系（Value/Wrapper/Bridge）提供了从简单值传递到子类继承的完整互操作能力，并附带 CLI 绑定生成器。但其栈式 VM 和逐操作码类实例化的设计限制了性能上限，约为 AOT Dart 的 **1/10 到 1/50**。

**hetu_script** 定义了独立的脚本语言（非 Dart 语法），提供字节码 VM 和 AST 解释两种模式，通过 `HTExternalClass` 机制绑定 Dart 类。其独立语法设计适合游戏脚本场景但不兼容 Dart 代码。

**d4rt** 是较新的 AST 遍历解释器，支持 Dart 3 语法（含模式匹配），拥有基于权限的安全系统，但 AST 遍历模式天然慢于字节码执行。

### 8.2 本设计的核心差异化

| 维度 | dart_eval | hetu_script | d4rt | **本方案** |
|------|-----------|-------------|------|-----------|
| 输入格式 | Dart 源码（analyzer 解析） | 自定义语言 | Dart 源码（自定义解析） | **Kernel .dill（CFE 编译）** |
| 执行模型 | 栈式字节码 | 栈式字节码 | AST 遍历 | **寄存器式字节码** |
| 指令存储 | List\<EvcOp\> 对象列表 | 字节码 | AST 树 | **Uint32List 紧凑编码** |
| 分发机制 | 虚方法调用 | switch | 递归访问 | **switch 跳转表 + IC** |
| 互调设计 | 三层包装器 | 外部函数注册 | 桥接类 | **句柄表 + 回调代理 + 自动绑定** |
| 异步支持 | 有限 | Future/async | async/await | **挂起/恢复 + 事件循环集成** |

本方案通过直接使用 Kernel AST 作为输入，避免了重新实现 Dart 解析器的巨大工程量，且能获得 CFE 完整的语义分析和类型推断结果。寄存器式字节码配合 `Uint32List` 存储，在理论上可将指令执行次数减少约 **46%**，同时消除对象分配开销。

---

## 结论

本报告提出的技术架构系统性地解决了在 Dart VM 内部构建高性能字节码解释器并实现双向互调的核心挑战。从技术价值角度，该方案为 Dart 生态带来了三个关键能力：**安全的动态代码执行**（沙箱化字节码运行，无需修改 VM）、**热更新基础设施**（字节码可序列化、可远程分发、可增量加载）、以及**可控的第三方扩展点**（插件代码在能力受限的沙箱中运行）。

句柄表加回调代理的互调架构是全方案的关键支柱。这一设计在保持类型安全和 GC 正确性的前提下，以最小的边界穿越开销实现了宿主与解释器之间的双向函数调用和对象共享。基于 Kernel 元数据的自动绑定生成器则将互调能力从少数手动绑定的类扩展到整个 Dart 标准库。

未来演进方向可沿以下路径展开。**性能层面**，可探索将热点函数从字节码 JIT 编译为 Dart 源码字符串再由宿主 VM 编译执行的"元JIT"策略；也可利用 `dart:ffi` 将分发循环核心下沉到 C 实现以获取 computed goto 的分发性能。**功能层面**，增量编译支持将允许修改单个函数而无需重新编译整个模块；共享内存 Isolate（Dart 实验特性）可能为并行字节码执行带来突破。**生态层面**，一旦互调层成熟，可构建声明式 DSL 的解释执行框架、跨平台规则引擎、或安全的用户自定义逻辑沙箱，拓展 Dart 语言在服务端和边缘计算场景的应用边界。