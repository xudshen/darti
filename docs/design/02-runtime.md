# Chapter 2: 运行时

## 模块定位

运行时是 dartic 的核心执行引擎：加载字节码模块、管理三栈内存模型（值栈/引用栈/调用栈）、驱动分发循环执行指令，并通过内联缓存加速虚方法调用。它位于架构分层中 ISA（Ch1）之上、Bridge/互调（Ch3）之下，为上层的异步子系统（Ch6）和安全沙箱（Ch7）提供基础执行能力。

## 与其他模块的关系

| 方向 | 模块 | 接口 |
|------|------|------|
| 输入 | Ch4 编译器 | 加载编译器产出的 `.darticb` 字节码模块，含字节码、常量池、符号表 |
| 输入 | Ch1 ISA | 分发循环解码并执行 Ch1 定义的 32 位定宽指令 |
| 输出 | Ch3 互调 | 暴露运行时 API（字段读写、方法调用、对象创建）供 Bridge/Proxy 回调解释器 |
| 扩展 | Ch6 异步 | 异步子系统复用分发循环的帧管理机制，扩展 InterpreterFrame 支持挂起/恢复 |
| 扩展 | Ch7 沙箱 | 沙箱层在模块加载时执行字节码验证，复用运行时的 fuel 计数和调用深度限制 |
| 依赖 | Ch5 泛型 | 栈帧中的 ITA/FTA 槽位为泛型系统提供类型参数传递通道 |

## 设计决策

| 决策项 | 选择 | 备选方案与拒绝理由 | 理由 |
|--------|------|-------------------|------|
| 值栈 | 共享 ByteBuffer 双视图（Int64List + Float64List） | 独立 int/double 栈：两套栈指针管理复杂，帧快照/恢复需处理双倍数据 | int 保留 64 位精度 + double 零装箱，单缓冲区对缓存友好 |
| 引用栈 | 独立 `List<Object?>` | 混入值栈：typed list 无法持有 Object 引用，VM GC 无法追踪 | 参与宿主 GC 追踪，弹出置 null 确保及时回收 |
| 对象模型 | 统一 InterpreterObject | 按类型生成不同宿主类：类数量爆炸，无法支持动态加载 | 单一表示简化实现；extends 宿主类时走 Bridge 路径（详见 Ch3） |
| fuel 让出 | `Timer.run`（fuel 耗尽）+ `scheduleMicrotask`（await 恢复） | Isolate：创建/通信开销过高，不适合轻量级让出 | 协作调度不饿死 event queue，详见 Ch6 |
| GC | 完全依赖宿主 Dart VM GC | 自实现 GC：复杂度极高，且 VM 已有成熟 GC | 解释器对象即 VM 堆对象，零额外 GC 开销 |
| 内联缓存 | 单态 IC（每 CALL_VIRTUAL 一个缓存槽） | 无缓存：每次虚调用都查 HashMap，10-50x 性能劣化 | 典型 OO 代码单态命中率 85-95%，一次 int 比较 O(1) |

## 核心概念

### 三栈内存模型

运行时使用三个独立的栈结构管理执行状态：

**ValueStack**（双视图值栈）

底层为一块 `Uint8List` 缓冲区，上面叠加两个视图共享同一内存：

| 属性 | 类型 | 说明 |
|------|------|------|
| intView | Int64List | 整数视图，每槽 8 字节 |
| doubleView | Float64List | 浮点视图，与 intView 共享同一缓冲区 |
| sp | int | 栈顶指针（槽位单位） |

**不变式**：同一槽位在其活跃区间内只通过一种视图访问。编译器的 StackKind 分类保证此约束——`dynamic` / `num` 类型变量走引用栈（装箱路径）。

**RefStack**（引用栈）

| 属性 | 类型 | 说明 |
|------|------|------|
| slots | List\<Object?\> | 引用类型存储，参与宿主 VM GC 追踪 |
| sp | int | 栈顶指针（槽位单位） |

**不变式**：弹出时必须将槽位置 null（`slots[sp] = null`），防止 GC 过期引用导致内存泄漏。

**CallStack**（调用栈）

| 属性 | 类型 | 说明 |
|------|------|------|
| data | Uint32List | 帧元数据存储，每帧 6 个 uint32 槽位 |
| fp | int | 帧指针（指向当前帧基址） |

**不变式**：`savedVSP`/`savedRSP` 用于同步调用链的帧切换。异步挂起时栈指针额外保存到 InterpreterFrame 对象（详见 Ch6），因为挂起帧脱离了 CallStack 的线性调用链。

### 栈帧布局

每个函数调用占用三部分空间：

```
值栈 (ValueStack)                 引用栈 (RefStack)
┌────────────────────┐           ┌────────────────────┐
│ [调用者帧]         │           │ [调用者帧]         │
├────────────────────┤           ├────────────────────┤
│ int/double 参数    │           │ ITA (类类型参数)   │ ← rsp+0 (泛型类方法，详见 Ch5)
│ int/double 局部变量 │           │ FTA (方法类型参数) │ ← rsp+1 (泛型方法，详见 Ch5)
│ int/double 临时值  │           │ this / receiver    │
├────────────────────┤ ← vsp    │ ref 参数           │
│ (空闲)             │           │ ref 局部变量       │
└────────────────────┘           │ ref 临时值         │
                                 ├────────────────────┤ ← rsp
                                 │ (空闲)             │
                                 └────────────────────┘

调用栈 (CallStack)
┌──────────────────────────────────┐
│ funcId      │ 当前函数 ID        │
│ returnPC    │ 调用者的 PC        │
│ savedFP     │ 调用者的帧指针     │
│ savedVSP    │ 调用者的值栈指针   │
│ savedRSP    │ 调用者的引用栈指针 │
│ resultReg   │ 调用者的返回值寄存器│
├──────────────────────────────────┤ ← fp
│ (下一帧)                         │
└──────────────────────────────────┘
```

函数入口时，编译器已知该函数需要多少值栈槽位和引用栈槽位（寄存器分配的输出），直接推进 sp 预留空间。

### 对象模型

**InterpreterObject**（统一内部表示）

所有解释器定义的类实例统一使用 InterpreterObject：

| 属性 | 类型 | 说明 |
|------|------|------|
| classId | int | 类标识，用于虚方法表查找和 IC 命中检查 |
| runtimeType | RuntimeType | 含具体化的泛型类型参数（详见 Ch5） |
| refFields | List\<Object?\> | 引用类型字段存储 |
| valueFields | Int64List? | int/double/bool 字段存储（字段全为 ref 时为 null） |

字段访问通过编译期确定的偏移索引，`GET_FIELD_REF r, obj, 2` 读取 `obj.refFields[2]`，O(1)。

**Bridge 实例**：解释器类继承或实现宿主 VM 类型时（如 `extends StatelessWidget`），必须使用 Bridge 实例。Bridge 内部持有 InterpreterObject 的引用，委托方法调用给解释器运行时。详见 Ch3。

**跨边界传递**：非 Bridge 的 InterpreterObject 跨越解释器-VM 边界时，通过 Expando 缓存按需包装为代理。详见 Ch3。

### 虚方法表

每个解释器类通过 ClassInfo 维护方法表和字段布局：

**ClassInfo**

| 属性 | 类型 | 说明 |
|------|------|------|
| classId | int | 类唯一标识 |
| name | String | 类名 |
| superClassId | int | 父类 ID |
| refFieldCount | int | 引用类型字段数量 |
| valueFieldCount | int | 值类型字段数量 |
| typeParamCount | int | 类型参数数量（如 `List<T>` → 1, `Map<K,V>` → 2, 非泛型 → 0） |
| methods | Map\<int, FuncProto\> | 方法名索引 → 字节码函数原型 |
| fields | Map\<int, FieldLayout\> | 字段名索引 → 字段布局 |

**FieldLayout**

| 属性 | 类型 | 说明 |
|------|------|------|
| offset | int | 字段在 refFields 或 valueFields 中的偏移 |
| kind | StackKind | value（值栈类型）或 ref（引用栈类型） |

`CALL_VIRTUAL` 通过 `classId` 查找 ClassInfo，再通过方法名索引查找 FuncProto。IC 缓存将这个两步查找优化为 O(1)。

## 工作流程

### 全局变量惰性初始化

GlobalTable 存储静态字段和顶层变量。每个槽位初始为 `_uninitialized` 哨兵，附带一个初始化函数 ID（由编译器从 Kernel `Field.initializer` 生成）。

**惰性初始化流程**（`LOAD_GLOBAL` 首次访问时触发）：

1. 读取 `slots[index]`
2. 若值为 `_initializing` 哨兵 → 抛出循环依赖错误
3. 若值为 `_uninitialized` 哨兵：
   a. 标记为 `_initializing`（防循环）
   b. 执行初始化函数（`initializerFuncIds[index]`）
   c. 存储结果，返回
   d. 若初始化失败，重置为 `_uninitialized`
4. 否则直接返回已缓存的值

**Late 变量**：Late 局部变量使用相同的哨兵值机制。编译器为 `late` 变量的读取插入检查——值为哨兵时抛出 `LateInitializationError`。有初始化器的 `late` 变量（`late int x = compute()`）首次读取时执行初始化器并缓存结果。

### 分发循环

运行时公开 API 包括：`loadModule`（加载字节码，含验证 + 符号解析，详见 Ch4/Ch7）、`execute`（执行模块）、字段读写与方法调用（供 Bridge/Proxy 使用，详见 Ch3）。

分发循环采用外/内双层循环结构，fuel 计数控制单回合执行量：

```
┌─ _driveInterpreter() ─────────────────────────────────────────┐
│                                                                │
│  fuel = _fuelBudget                                            │
│                                                                │
│  ┌─ 外层循环: while fuel > 0 && _runQueue 非空 ──────────────┐ │
│  │                                                            │ │
│  │  frame = _runQueue.first                                   │ │
│  │                                                            │ │
│  │  ┌─ 内层循环: while fuel-- > 0 ─────────────────────────┐ │ │
│  │  │                                                       │ │ │
│  │  │  取指: instr = code[pc++]                             │ │ │
│  │  │  解码: op = instr & 0xFF                              │ │ │
│  │  │  执行: switch(op)                                     │ │ │
│  │  │    ├─ 算术/逻辑指令 → 值栈操作，继续内循环            │ │ │
│  │  │    ├─ CALL → 保存 PC，push 新帧，break 内循环         │ │ │
│  │  │    ├─ RETURN → pop 帧，恢复调用者，break 内循环       │ │ │
│  │  │    ├─ AWAIT → 保存帧，移出队列，break 内循环(详见Ch6) │ │ │
│  │  │    └─ HALT → pop 帧，break 内循环                     │ │ │
│  │  │                                                       │ │ │
│  │  └───────────────────────────────────────────────────────┘ │ │
│  │                                                            │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                │
│  _runQueue 非空? → Timer.run(_driveInterpreter)  // 下一回合   │
│  _runQueue 空?   → _driving = false              // 停止       │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

**帧切换**：`CALL` 保存当前 PC 后 `break` 内循环，外层循环从 `_runQueue.first` 取新帧继续。`RETURN` 弹出当前帧，恢复调用者的栈指针和返回值寄存器后 `break` 内循环。

### 分发循环优化要点

- **opcode 解码内联**：`instr & 0xFF`、`(instr >> 8) & 0xFF` 等位运算在 switch case 内直接展开，不抽取为函数调用。Dart AOT 编译为单条机器指令
- **switch 密度**：所有 256 个 case 值填满（未使用的指向 default 错误处理），确保 AOT 生成跳转表而非二分查找
- **内循环零分配**：值栈操作全部是 typed list 索引赋值，零 GC 压力。引用栈操作仅在需要时移动引用
- **帧切换最小化**：通过 break innerLoop + 外层重取帧实现，无需额外函数调用

### 内联缓存 (IC) 分发

每个 `CALL_VIRTUAL` 指令关联一个 IC 槽，存储最近一次成功匹配的 classId 和方法偏移。

**IC 分发流程**：

1. 从 `CALL_VIRTUAL` 指令的 C 操作数取 IC 槽索引
2. **单态命中**：`ic.cachedClassId == receiver.classId` → 直接调用缓存的方法偏移（一次 int 比较，O(1)）
3. **未命中**（慢路径）：查虚方法表（classId → ClassInfo → methods HashMap）→ 更新 IC 缓存 → 调用

命中率：典型面向对象代码约 85-95%。命中 vs 未命中性能差约 10-50x。

> **Phase 2**：多态 IC（2-4 条目）和超态回退（全局查找）。触发条件：profiling 显示单态命中率 < 85%。

### GC 集成

解释器不实现自己的 GC。所有对象（InterpreterObject、Bridge 实例、闭包）都是宿主 Dart VM 堆对象，由 VM GC 管理。关键的 GC 协作点：

- **引用栈弹出置 null**：确保弹出的对象可被 GC 回收
- **上值关闭**：`CLOSE_UPVALUE` 将值从栈复制到上值对象内部后，栈槽置 null
- **帧销毁**：帧从 `_runQueue` 移除后，帧对象及其引用可被 GC 回收（除非被挂起的 async 帧持有，详见 Ch6）

## 关键约束与边界条件

| 约束项 | 值 | 来源 |
|--------|-----|------|
| fuel 预算 | 50,000 指令/回合 | ~200us `Timer.run` 调度开销 + ~10ms 目标回合时间（保持 UI 60fps 流畅） |
| 最大调用深度 | 512 帧 | 满足正常递归深度（Dart 常规代码极少超过 100 层），同时防止栈溢出消耗过多内存 |
| CallStack 帧大小 | 6 个 uint32 | funcId + returnPC + savedFP + savedVSP + savedRSP + resultReg |
| ValueStack 槽位 | 8 字节/槽 | Int64List 和 Float64List 共享同一缓冲区 |

## 已知局限与演进路径

> **Phase 2**：运行时 Quickening。触发条件：profiling 显示编译器静态类型特化覆盖不足（当前编译器已根据 CFE 静态类型信息生成特化指令如 `ADD_INT`、`ADD_DBL`）。

> **Phase 2**：多态 IC（2-4 条目）和超态回退。触发条件：profiling 显示单态命中率 < 85%。

> **Phase 2**：ValueStack/RefStack 容量动态扩展。触发条件：实际应用中出现深调用链导致预分配栈空间不足。

## 附录：参考实现

<details>
<summary>GlobalTable 惰性初始化实现</summary>

```dart
Object? load(int index, DarticRuntime runtime) {
  final value = slots[index];
  if (identical(value, _initializing)) {
    throw DarticError('Circular dependency: global variable $index');
  }
  if (identical(value, _uninitialized)) {
    final initId = initializerFuncIds[index];
    if (initId == -1) throw LateInitializationError('Global $index');
    slots[index] = _initializing;
    try {
      final result = runtime._executeInitializer(initId);
      slots[index] = result;
      return result;
    } catch (e) {
      slots[index] = _uninitialized;
      rethrow;
    }
  }
  return value;
}
```

</details>
