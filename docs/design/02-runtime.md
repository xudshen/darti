# Chapter 2: 运行时

## 设计决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 值栈 | 共享 ByteBuffer 双视图（Int64List + Float64List） | int 64 位精度 + double 无装箱 |
| 引用栈 | 独立 `List<Object?>` | 参与宿主 GC 追踪 |
| 对象模型 | 统一 InterpreterObject + Expando 缓存跨边界代理。extends 宿主类必须用 Bridge | 容错性高，实现简单 |
| fuel 让出 | `Timer.run`（fuel 耗尽）+ `scheduleMicrotask`（await 恢复） | 不饿死 event queue |
| GC | 完全依赖宿主 Dart VM GC | 解释器不实现自己的 GC |

## 内存模型

### 双视图值栈

```dart
class ValueStack {
  final Uint8List _buffer;
  late final Int64List intView;
  late final Float64List doubleView;
  int sp = 0;  // 栈顶指针（以槽位为单位，每槽 8 字节）

  ValueStack(int maxSlots)
      : _buffer = Uint8List(maxSlots * 8) {
    intView = Int64List.view(_buffer.buffer);
    doubleView = Float64List.view(_buffer.buffer);
  }
}
```

同一槽位通过 `intView[i]` 读写 int、通过 `doubleView[i]` 读写 double。编译器已确定每个操作数的类型，指令决定用哪个视图。`dynamic` / `num` 类型变量走引用栈（装箱路径）。

### 引用栈

```dart
class RefStack {
  final List<Object?> slots;
  int sp = 0;

  RefStack(int maxSlots) : slots = List<Object?>.filled(maxSlots, null);

  void push(Object? value) {
    slots[sp++] = value;
  }

  // 弹出时置 null，防止 GC 过期引用
  Object? pop() {
    final val = slots[--sp];
    slots[sp] = null;
    return val;
  }
}
```

### 调用栈

```dart
class CallStack {
  final Uint32List data;
  int fp = 0;  // 帧指针

  CallStack(int maxDepth) : data = Uint32List(maxDepth * _frameMetaSize);

  static const _frameMetaSize = 6;  // funcId, returnPC, savedFP, savedVSP, savedRSP, resultReg
}
```

**同步调用链 vs 异步挂起的栈指针保存**：`CallStack` 中的 `savedVSP`/`savedRSP` 用于同步调用链中的帧切换——调用和返回时通过 `Uint32List` 高效保存/恢复栈指针。当 async 帧需要挂起时，栈指针额外保存到 `InterpreterFrame` 对象上（`savedVSP`/`savedRSP` 字段，详见 Chapter 6），因为挂起帧脱离了 `CallStack` 的线性调用链，需要独立于 `CallStack` 持有自己的恢复信息。

## 栈帧布局

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

## 全局变量表

静态字段和顶层变量存储在全局变量表中：

```dart
class GlobalTable {
  final List<Object?> slots;
  final List<int> initializerFuncIds;  // 惰性初始化函数 ID，-1 = 无/已初始化

  static final Object _uninitialized = Object();   // 哨兵：未初始化
  static final Object _initializing = Object();    // 哨兵：正在初始化（检测循环依赖）

  GlobalTable(int count)
      : slots = List<Object?>.filled(count, _uninitialized),
        initializerFuncIds = List<int>.filled(count, -1);

  /// LOAD_GLOBAL 运行时：惰性初始化 + 循环依赖检测
  Object? load(int index, DarticRuntime runtime) {
    final value = slots[index];
    if (identical(value, _initializing)) {
      throw DarticError('Circular dependency: global variable $index is being initialized');
    }
    if (identical(value, _uninitialized)) {
      final initId = initializerFuncIds[index];
      if (initId == -1) {
        throw LateInitializationError('Global variable $index not initialized');
      }
      // 标记为"正在初始化"，防止循环依赖
      slots[index] = _initializing;
      try {
        final result = runtime._executeInitializer(initId);
        slots[index] = result;
        return result;
      } catch (e) {
        slots[index] = _uninitialized;  // 初始化失败，重置为未初始化
        rethrow;
      }
    }
    return value;
  }
}
```

`LOAD_GLOBAL` 首次访问时触发惰性初始化。初始化函数由编译器从 Kernel 的 `Field.initializer` 或顶层变量的初始化表达式生成。

### Late 变量

Late 局部变量使用相同的哨兵值机制。编译器为 `late` 变量的读取插入检查：

```
// late int x;
// 编译为：
// 声明时: refStack[r] = _UNINITIALIZED（哨兵）
// 读取时:
LOAD_GLOBAL  rTemp, globalIndex   // 或局部变量读取
// 运行时检查：若值为哨兵 → throw LateInitializationError
```

对于有初始化器的 `late` 变量（`late int x = compute()`），首次读取时执行初始化器并缓存结果。

## 对象模型

### InterpreterObject（统一内部表示）

所有解释器定义的类实例统一使用 InterpreterObject：

```dart
class InterpreterObject {
  final int classId;
  final RuntimeType runtimeType;    // 含泛型类型参数
  final List<Object?> refFields;    // 引用类型字段
  final Int64List? valueFields;     // int/double/bool 字段（可选，字段全为 ref 时为 null）

  InterpreterObject({
    required this.classId,
    required this.runtimeType,
    required int refFieldCount,
    int valueFieldCount = 0,
  })  : refFields = List<Object?>.filled(refFieldCount, null),
        valueFields = valueFieldCount > 0 ? Int64List(valueFieldCount) : null;
}
```

字段访问通过编译期确定的偏移索引，`GET_FIELD_REF r, obj, 2` 读取 `obj.refFields[2]`，O(1)。

### Bridge 实例（extends/implements 宿主类）

**唯一例外**：解释器类继承或实现宿主 VM 类型时（如 `extends StatelessWidget`），必须使用 Bridge 实例。Bridge 内部持有 InterpreterObject 的引用，委托方法调用给解释器运行时。详见 Chapter 3 (Interop)。

### 跨边界传递

非 Bridge 的 InterpreterObject 跨越解释器-VM 边界时，通过 Expando 缓存按需包装为代理。详见 Chapter 3 (Interop)。

## 分发循环

### 核心结构

```dart
class DarticRuntime {
  final ValueStack _vs;
  final RefStack _rs;
  final CallStack _cs;
  final Queue<InterpreterFrame> _runQueue = Queue();
  final HostBindings hostBindings;   // 宿主函数绑定（详见 Chapter 3）
  final GlobalTable globals;         // 静态字段/顶层变量
  bool _driving = false;

  static const int _fuelBudget = 50000;  // 根据 profiling 调优；基于 ~200μs Timer.run 开销和 ~10ms 目标回合时间
  static const int maxCallDepth = 512;
  int _currentCallDepth = 0;

  // === 公开 API ===

  /// 加载字节码模块（含验证 + 绑定符号解析，详见 Chapter 4/7）
  /// 解析 .darticb 绑定名称表，构建重定位表（localIndex → runtimeId）
  DarticModule loadModule(Uint8List bytes);

  /// 执行已加载的模块
  Future<void> execute(DarticModule module);

  /// 字段读写与方法调用（供 Bridge/Proxy 使用，详见 Chapter 3）
  Object? getField(InterpreterObject target, String name);
  void setField(InterpreterObject target, String name, Object? value);
  Object? invokeMethod(InterpreterObject target, String name, List<Object?> args);
  Object? invokeClosure(InterpreterObject closure, List<Object?> args);

  /// 对象创建（详见 Chapter 3）
  Object createInstance(int classId, RuntimeType type);

  // === 帧管理 ===

  void _pushFrame(InterpreterFrame frame) {
    _currentCallDepth++;
    if (_currentCallDepth > maxCallDepth) {
      _currentCallDepth--;
      throw DarticError('Stack overflow: call depth exceeded $maxCallDepth');
    }
    _runQueue.addFirst(frame);
  }

  void _popFrame() {
    _currentCallDepth--;
    _runQueue.removeFirst();
  }

  void _scheduleDrive() {
    if (!_driving) {
      _driving = true;
      Timer.run(_driveInterpreter);  // event queue，不饿死 UI/IO
    }
  }

  void _driveInterpreter() {
    int fuel = _fuelBudget;

    while (fuel > 0 && _runQueue.isNotEmpty) {
      final frame = _runQueue.first;
      final code = frame.bytecode;
      var pc = frame.pc;

      innerLoop:
      while (fuel-- > 0) {
        final instr = code[pc++];
        final op = instr & 0xFF;

        switch (op) {
          case OpCode.ADD_INT:
            final a = (instr >> 8) & 0xFF;
            final b = (instr >> 16) & 0xFF;
            final c = (instr >> 24) & 0xFF;
            _vs.intView[a] = _vs.intView[b] + _vs.intView[c];

          case OpCode.CALL:
            frame.pc = pc;  // 保存调用者 PC
            final newFrame = _setupCall(frame, instr);
            _pushFrame(newFrame);  // 含调用深度检查
            break innerLoop;  // 切换到新帧

          case OpCode.AWAIT:
            frame.pc = pc;
            _executeAwait(frame, instr);
            _runQueue.removeFirst();
            break innerLoop;  // 总是挂起，等待 microtask 恢复（详见 Ch6）

          case OpCode.RETURN_REF:
            final retVal = _rs.slots[(instr >> 8) & 0xFF];
            _popFrame();  // 含调用深度递减
            if (_runQueue.isNotEmpty) {
              _restoreCallerFrame(_runQueue.first, retVal);
            }
            break innerLoop;

          case OpCode.HALT:
            _popFrame();
            break innerLoop;

          // ... 其他操作码
        }
      }
    }

    if (_runQueue.isNotEmpty) {
      Timer.run(_driveInterpreter);  // 还有工作，下一轮继续
    } else {
      _driving = false;
    }
  }
}
```

### 分发循环优化要点

**opcode 解码内联**：`instr & 0xFF`、`(instr >> 8) & 0xFF` 等位运算在 switch case 内直接展开，不抽取为函数调用。Dart AOT 会将这些编译为单条机器指令。

**switch 密度**：所有 256 个 case 值填满（未使用的指向 `default` 错误处理），确保 AOT 生成跳转表而非二分查找。

**内循环不分配对象**：值栈操作全部是 typed list 索引赋值，零 GC 压力。引用栈操作仅在需要时移动引用。

**帧切换最小化**：`CALL` 保存 PC 后直接 `break innerLoop`，外层循环从 `_runQueue.first` 取新帧继续。无需额外的帧切换函数调用。

## 内联缓存 (IC)

每个 `CALL_VIRTUAL` 指令关联一个 IC 槽。运行时流程：

```dart
Object? _executeCallVirtual(InterpreterFrame frame, int instr) {
  final receiver = _rs.slots[(instr >> 16) & 0xFF];
  final icIndex = (instr >> 24) & 0xFF;
  final ic = frame.icTable[icIndex];

  final classId = _getClassId(receiver);

  // 单态命中
  if (ic.cachedClassId == classId) {
    return _directCall(ic.cachedMethodOffset, receiver, args);
  }

  // 慢路径：查虚方法表
  final method = _vtableLookup(classId, ic.methodNameIndex);
  ic.cachedClassId = classId;
  ic.cachedMethodOffset = method.offset;

  return _directCall(method.offset, receiver, args);
}
```

> **Phase 2**：多态 IC（2-4 条目）和超态回退（全局查找）留待 profiling 显示单态命中率不足时引入。

## Quickening

> **Phase 2**：编译器已根据 CFE 静态类型信息生成特化指令（如 `ADD_INT`、`ADD_DBL`），运行时 Quickening 留待 profiling 显示需要时再引入。

## GC 集成

解释器不实现自己的 GC。所有对象（InterpreterObject、Bridge 实例、闭包）都是宿主 Dart VM 的堆对象，由 VM GC 管理。

**引用栈弹出置 null**：`_rs.slots[sp] = null` 确保弹出的对象可被 GC 回收。

**上值关闭**：`CLOSE_UPVALUE` 将值从栈复制到上值对象内部后，栈槽置 null。

**帧销毁**：帧从 `_runQueue` 移除后，帧对象及其引用的局部变量、常量池等可被 GC 回收（除非被挂起的 async 帧持有）。

## 虚方法表

每个解释器类维护一个方法表，通过方法名索引查找字节码函数：

```dart
class ClassInfo {
  final int classId;
  final String name;
  final int superClassId;
  final int refFieldCount;
  final int valueFieldCount;
  final int typeParamCount;       // 类型参数数量（如 List<T> → 1, Map<K,V> → 2, 非泛型 → 0）

  // 方法表：方法名索引 → FuncProto
  final Map<int, FuncProto> methods;

  // 字段布局：字段名索引 → (偏移, StackKind)
  final Map<int, FieldLayout> fields;
}

class FieldLayout {
  final int offset;
  final StackKind kind;  // value or ref
}
```

`CALL_VIRTUAL` 通过 `classId` 查找 `ClassInfo`，再通过方法名索引查找 `FuncProto`。IC 缓存将这个两步查找优化为 O(1)。
