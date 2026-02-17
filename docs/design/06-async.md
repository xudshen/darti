# Chapter 6: 异步与生成器

## 设计决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| async 实现 | 帧快照续体（挂起时拷贝栈数据到帧对象） | 解释器帧在堆上；挂起时快照值栈/引用栈区间到帧对象，恢复时拷回 |
| 跨边界桥接 | Completer\<T\>（async）/ StreamController\<T\>（async*） | 返回 VM 原生 Future/Stream |
| 协作调度 | fuel 耗尽 → Timer.run；await 恢复 → scheduleMicrotask | 不饿死 event queue |
| sync* 阻塞 | 接受限制 | sync* 是同步语义，调用者对阻塞有预期 |
| Kernel 处理 | 直接处理 AwaitExpression / YieldStatement | Dart VM 后端不做 Kernel 层 async 脱糖 |

## 核心原理

解释器的帧（InterpreterFrame）是 Dart 堆对象——PC、异常处理器、Completer 等元数据在堆上。局部变量和操作数存储在全局 ValueStack/RefStack 中（详见 Chapter 2），挂起时需要将帧占用的栈区间快照到帧对象，恢复时拷回。快照大小等于帧的寄存器数量（编译期确定），通常仅 10-50 个槽位（80-400 字节），拷贝代价相比 Future.then 回调 + microtask 调度可忽略。

这是字节码解释器的核心优势：**帧本身就是续体**，挂起/恢复的全部状态封装在帧对象中。

## InterpreterFrame 异步扩展

```dart
class InterpreterFrame {
  // 基础字段（同 Chapter 2）
  final Uint32List bytecode;
  int pc;
  final List<InlineCacheEntry> icTable;  // 内联缓存表
  // 值栈/引用栈通过全局 sp 偏移定位
  int savedVSP;   // 挂起时保存的值栈指针
  int savedRSP;   // 挂起时保存的引用栈指针
  int savedVBase = 0;  // 挂起时值栈帧基址
  int savedRBase = 0;  // 挂起时引用栈帧基址
  Int64List? savedValueSlots;    // 挂起时值栈快照（帧占用区间）
  List<Object?>? savedRefSlots;  // 挂起时引用栈快照（帧占用区间）

  // 异步扩展
  Completer<Object?>? resultCompleter;  // async 函数的结果 Completer
  Function? thenCallback;               // 惰性创建的 then 回调
  Function? errorCallback;              // 惰性创建的 error 回调

  // 生成器扩展
  StreamController<Object?>? streamController;  // async* 的输出 Stream
  bool streamPaused = false;
  bool isSuspendedAtYield = false;
  bool cancelled = false;

  // 异常处理
  List<ExceptionHandler> handlerTable;

  // 挂起恢复
  int awaitDestReg = -1;          // AWAIT 指令的目标寄存器 A
  Object? resumeValue;
  Object? resumeException;
  StackTrace? resumeStackTrace;

  // Zone
  Zone capturedZone;

  // 异步栈追踪
  InterpreterFrame? awaiterFrame;  // 等待此帧结果的帧
}
```

## 异步帧与全局栈的交互

Chapter 2 的运行时使用全局 ValueStack/RefStack。多个 async 帧可能并发挂起，它们的栈区间在全局栈上可能重叠——后启动的帧分配到与先挂起帧相同的栈位置。因此挂起时必须快照栈数据，恢复时在栈顶重新分配空间（不写回原位置，避免覆盖其他活跃帧）。

### 栈恢复不变式

恢复帧时必须满足以下不变式：

1. **新空间分配**：恢复帧总是在当前 `_vs.sp` / `_rs.sp` 位置（栈顶）分配新空间，**绝不**写回原 `savedVBase` / `savedRBase` 位置
2. **无重叠保证**：恢复后的帧区间 `[newBase, newBase+size)` 不与任何活跃帧的栈区间重叠——因为总是在栈顶分配，而活跃帧的数据在栈顶以下
3. **基址更新**：恢复后 `frame.savedVBase` / `frame.savedRBase` 更新为新位置，后续字节码中的寄存器访问使用新基址

**挂起时**（AWAIT 遇到真 Future）：

```dart
void _suspendFrame(InterpreterFrame frame) {
  final vBase = frame.savedVBase;
  final vSize = frame.savedVSP - vBase;
  final rBase = frame.savedRBase;
  final rSize = frame.savedRSP - rBase;

  // 快照值栈区间
  if (vSize > 0) {
    frame.savedValueSlots = Int64List(vSize);
    frame.savedValueSlots!.setRange(0, vSize, _vs.intView, vBase);
  }

  // 快照引用栈区间
  if (rSize > 0) {
    frame.savedRefSlots = List<Object?>.filled(rSize, null);
    for (int i = 0; i < rSize; i++) {
      frame.savedRefSlots![i] = _rs.slots[rBase + i];
      _rs.slots[rBase + i] = null;  // 释放引用，允许 GC
    }
  }
}
```

**恢复时**（Future 完成，`_resumeFrame` 调用前）：

恢复时**不写回原位置**——原栈区间可能已被其他活跃帧占用。改为在栈顶分配新空间：

```dart
void _restoreFrameStack(InterpreterFrame frame) {
  final vSize = frame.savedValueSlots?.length ?? 0;
  final rSize = frame.savedRefSlots?.length ?? 0;

  // 在栈顶分配新空间（不使用原 vBase/rBase）
  final newVBase = _vs.sp;
  final newRBase = _rs.sp;

  // 恢复值栈到新位置
  if (frame.savedValueSlots != null) {
    _vs.intView.setRange(newVBase, newVBase + vSize, frame.savedValueSlots!);
    frame.savedValueSlots = null;
  }

  // 恢复引用栈到新位置
  if (frame.savedRefSlots != null) {
    for (int i = 0; i < rSize; i++) {
      _rs.slots[newRBase + i] = frame.savedRefSlots![i];
    }
    frame.savedRefSlots = null;
  }

  // 更新帧基址和栈指针
  frame.savedVBase = newVBase;
  frame.savedRBase = newRBase;
  frame.savedVSP = newVBase + vSize;
  frame.savedRSP = newRBase + rSize;
  _vs.sp = newVBase + vSize;
  _rs.sp = newRBase + rSize;
}
```

**性能**：快照大小由编译器的寄存器分配输出决定（`FuncProto.refRegCount` + `FuncProto.valueRegCount`），典型帧 10-50 个槽位。`Int64List.setRange` 底层为 `memcpy`，80-400 字节的拷贝在现代 CPU 上 <1μs。相比 Future.then 回调注册（~5-10μs）和 microtask 调度开销，栈快照代价可忽略。

## 字节码指令

```
INIT_ASYNC      A, Bx    创建 Completer<T>，refStack[A] = completer.future
                          T 从 type 常量池 [Bx] 获取
                          frame.resultCompleter = completer

AWAIT           A, Bx    弹出 refStack[A] 作为待 await 的值
                          Bx 为恢复点 PC
                          总是挂起帧，通过 scheduleMicrotask 恢复：
                          if value is Future → 注册 then/error 回调
                          if value is! Future → 直接 scheduleMicrotask 恢复

ASYNC_RETURN    A        completer.complete(refStack[A])
                          if refStack[A] is Future → 隐式 await（Future 展平）

ASYNC_THROW     A, B     completer.completeError(refStack[A], refStack[B])

INIT_ASYNC_STAR A, Bx    创建 StreamController<T>
                          refStack[A] = controller.stream

YIELD           A, Bx    controller.add(refStack[A])
                          Bx 为恢复点 PC
                          if stream paused → SUSPENDED
                          else → 继续

YIELD_STAR      A, Bx    委托 yield* refStack[A]

INIT_SYNC_STAR  A, Bx    创建惰性 Iterable<T>
```

## async/await 执行流

### VM 调用解释器 async 函数

```dart
Future<T> callInterpreterAsync<T>(
  BytecodeFunction function,
  List<Object?> args,
) {
  final completer = Completer<T>();
  final frame = InterpreterFrame(
    bytecode: function.bytecode,
    resultCompleter: completer,
    capturedZone: Zone.current,
  );
  _initFrameArgs(frame, args);
  _runQueue.add(frame);
  _driveInterpreter();  // 同步执行直到挂起或完成
  return completer.future;  // VM 原生 Future<T>
}
```

### AWAIT 指令运行时

```dart
_Signal executeAwait(InterpreterFrame frame, int destReg, int resumePC) {
  final value = _rs.slots[destReg];

  // 非 Future 值：仍需通过 scheduleMicrotask 让出一次 microtask
  // （符合 Dart 语言规范：await e 总是让出，即使 e 不是 Future）
  if (value is! Future) {
    frame.pc = resumePC;
    frame.awaitDestReg = destReg;
    frame.resumeValue = value;
    _suspendFrame(frame);
    frame.capturedZone.scheduleMicrotask(() => _resumeFrame(frame));
    return _Signal.suspended;
  }

  // 保存恢复点和目标寄存器
  frame.pc = resumePC;
  frame.awaitDestReg = destReg;

  // 惰性创建回调
  frame.thenCallback ??= (Object? result) {
    frame.resumeValue = result;
    frame.resumeException = null;
    frame.capturedZone.scheduleMicrotask(() => _resumeFrame(frame));
  };
  frame.errorCallback ??= (Object error, StackTrace stackTrace) {
    frame.resumeException = error;
    frame.resumeStackTrace = stackTrace;
    frame.capturedZone.scheduleMicrotask(() => _resumeFrame(frame));
  };

  // 注册到 VM Future
  value.then(
    frame.thenCallback! as dynamic Function(dynamic),
    onError: frame.errorCallback! as Function,
  );

  return _Signal.suspended;
}
```

### 帧恢复

```dart
// 连续恢复计数器（防止频繁 await-resume 绕过 fuel）
int _resumeCounter = 0;
static const int _maxResumesPerRound = 64;  // 连续恢复上限

void _resumeFrame(InterpreterFrame frame) {
  // 先恢复栈快照（在栈顶分配新空间）
  _restoreFrameStack(frame);

  if (frame.resumeException != null) {
    // 异常恢复：查找异常处理器
    final handler = _findHandler(frame, frame.pc);
    if (handler != null) {
      // 异常和栈追踪写入处理器约定的寄存器位置
      _rs.slots[handler.refStackDepth] = frame.resumeException;
      _rs.slots[handler.refStackDepth + 1] = frame.resumeStackTrace;
      frame.pc = handler.handlerPC;
    } else {
      // 无处理器 → 完成 Completer 为错误
      frame.resultCompleter?.completeError(
        frame.resumeException!, frame.resumeStackTrace);
      return;
    }
    frame.resumeException = null;
    frame.resumeStackTrace = null;
  } else {
    // 正常恢复：将值写入 AWAIT 指令指定的目标寄存器
    _rs.slots[frame.awaitDestReg] = frame.resumeValue;
    frame.resumeValue = null;
  }

  _runQueue.addFirst(frame);

  // 防止频繁 await-resume 绕过 fuel：连续恢复超限后降级为 Timer.run
  _resumeCounter++;
  if (_resumeCounter >= _maxResumesPerRound) {
    _resumeCounter = 0;
    Timer.run(_driveInterpreter);  // 让出事件循环
  } else {
    _scheduleDrive();
  }
}
```

## try/catch 与 await 的交互

异常处理器表跨越 await 点。恢复帧后根据当前 PC 查找有效处理器：

```dart
ExceptionHandler? _findHandler(InterpreterFrame frame, int pc) {
  for (final handler in frame.handlerTable) {
    if (pc >= handler.startPC && pc < handler.endPC) {
      return handler;
    }
  }
  return null;
}
```

finally 中的 await 正常工作——finally 块的字节码序列包含 AWAIT 指令，挂起/恢复机制与普通 await 一致。

## 跨边界异步互调

### 四种模式

```
模式 1: VM → 解释器 async
  VM 调用 callInterpreterAsync<T>()
  → 返回 Completer<T>.future（VM 原生 Future）
  → VM 可直接 await

模式 2: 解释器 await VM Future
  解释器 AWAIT 指令遇到 VM 原生 Future
  → 注册 then/error 回调
  → Future 完成时恢复帧

模式 3: VM await 解释器 Future
  = 模式 1 的延续，VM await Completer.future

模式 4: 双向链
  VM async A → await 解释器 async B → B 内部 await VM async C
  → C 完成 → B 恢复 → B 完成 → A 恢复
  → 通过 Completer 链自然串联
```

### Zone 传播

Zone 沿调用链向下传播。解释器帧的 `capturedZone` 在帧创建时捕获 `Zone.current`，恢复执行时在正确的 Zone 中调度：

```dart
frame.capturedZone.scheduleMicrotask(() => _resumeFrame(frame));
```

### 异常跨边界传播

```
VM Future 异常 → errorCallback 触发
  → frame.resumeException = error
  → 帧恢复，查找 handler
  → 有 catch → 解释器内处理
  → 无 catch → completer.completeError()
  → VM 的 await 收到异常
```

异常栈追踪拼接：

```dart
void _onFutureError(InterpreterFrame frame, Object error, StackTrace vmTrace) {
  final interpTrace = _buildAsyncTrace(frame);
  frame.resumeStackTrace = CombinedStackTrace(interpTrace, vmTrace);
}
```

## async* 生成器

### 创建

```dart
Stream<T> callInterpreterAsyncStar<T>(BytecodeFunction function, List<Object?> args) {
  final controller = StreamController<T>();
  final frame = InterpreterFrame(
    bytecode: function.bytecode,
    streamController: controller,
  );
  _initFrameArgs(frame, args);

  controller.onListen = () {
    _runQueue.add(frame);
    _driveInterpreter();
  };
  controller.onPause = () { frame.streamPaused = true; };
  controller.onResume = () {
    frame.streamPaused = false;
    if (frame.isSuspendedAtYield) {
      frame.isSuspendedAtYield = false;
      _runQueue.add(frame);
      _scheduleDrive();
    }
  };
  controller.onCancel = () { frame.cancelled = true; };

  return controller.stream;  // VM 原生 Stream<T>
}
```

### YIELD 运行时

```dart
_Signal executeYield(InterpreterFrame frame, int resumePC) {
  final value = _rs.pop();
  frame.streamController!.add(value);

  if (frame.streamPaused || frame.cancelled) {
    frame.pc = resumePC;
    frame.isSuspendedAtYield = true;
    return _Signal.suspended;
  }
  return _Signal.continue_;
}
```

### await for 编译

`await for (var item in stream)` 编译为 stream.listen + AWAIT 序列：

```
// 编译为
CALL_VIRTUAL  rSubscription, rStream, 'listen'
  // listen 参数为桥接回调：
  //   onData: (value) → frame.resumeValue = value; resume
  //   onDone: () → frame.resumeValue = SENTINEL_DONE; resume
  //   onError: (e, s) → frame.resumeException = e; resume

LOOP_HEAD:
  AWAIT_STREAM_NEXT                  // 挂起等待 onData/onDone/onError
  LOAD_CONST  rDone, SENTINEL_DONE
  EQ_REF      rCmp, rResult, rDone
  JUMP_IF_TRUE rCmp, LOOP_EXIT      // stream 结束
  // ... 循环体 ...
  JUMP LOOP_HEAD

LOOP_EXIT:
  // break 时需要 cancel subscription
  CALL_VIRTUAL  rFuture, rSubscription, 'cancel'
  AWAIT          rFuture              // await subscription.cancel()
```

## sync* 生成器

sync* 使用同步阻塞式执行，每次 moveNext() 从上次 yield 点恢复，执行到下一个 yield 点暂停：

```dart
class SyncStarIterator<T> implements Iterator<T> {
  final InterpreterFrame _frame;
  final DarticRuntime _runtime;
  T? _current;

  @override
  T get current => _current as T;

  @override
  bool moveNext() {
    // 同步执行直到 yield 或 return
    return _runtime.executeSyncStarStep(_frame, (value) {
      _current = value as T;
    });
  }
}
```

**已知限制**：sync* 两个 yield 之间的计算如果耗时很长，会阻塞事件循环。这是 sync* 的同步语义决定的，不做 fuel 限制处理。

## 分发循环中的异步集成

AWAIT 指令总是导致帧挂起——无论 await 的值是否为 Future。非 Future 值通过 `scheduleMicrotask` 调度恢复，符合 Dart 语言规范（`await e` 总是让出至少一次 microtask）：

```dart
case OpCode.AWAIT:
  executeAwait(frame, decodeA(instr), decodeBx(instr));
  _runQueue.removeFirst();
  break innerLoop;  // 总是挂起，等待 microtask 恢复
```

分发循环主路径不因 async 支持变慢——大多数 async 函数在无 await 时同步完成（Dart VM 统计中很常见），此时 INIT_ASYNC 仅创建一个 Completer，ASYNC_RETURN 同步完成它，全程不挂起。性能敏感代码应避免无意义的 `await null`。

## Completer 生命周期

```dart
class AsyncBridge {
  final Set<WeakReference<Completer>> _active = {};

  Completer<T> createCompleter<T>() {
    final c = Completer<T>();
    _active.add(WeakReference(c));
    return c;
  }

  /// 诊断：检测可能泄漏的未完成 Completer
  int get pendingCount =>
      _active.where((ref) => ref.target != null && !ref.target!.isCompleted).length;
}
```

使用 WeakReference 追踪，不阻止 GC。未完成的 Completer 如果无人持有其 Future 引用，会被自然回收。
