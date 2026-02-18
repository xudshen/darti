# 自定义 Dart 字节码解释器中 async/await 的设计与实现

**异步操作是自定义 Dart 字节码解释器最具挑战性的子系统**。核心难题不在于单侧的挂起/恢复机制，而在于解释器与宿主 Dart VM 之间异步操作的跨边界互调——当一条 `await` 链跨越 VM → 解释器 → VM → 解释器多层边界时，Future 的传递、Zone 的传播、异常的冒泡和栈追踪的拼接必须无缝衔接。本章基于 Dart VM 源码（`runtime/docs/async.md`、`async_patch.dart`）、Kernel 二进制规范、现有解释器项目（dart_eval、d4rt）以及 V8、Kotlin 协程、Lua 协程等跨语言参考，提出一套以 **「Completer 桥接 + 帧快照式挂起/恢复」** 为核心的完整架构方案。

---

## 一、Dart 异步语义与 Kernel 层表示

### 1.1 Dart VM 的 Suspend/Resume 模型

Dart VM **不再使用** CPS 变换或 Kernel 层脱糖来实现异步函数。自 Dart 2.x 起，VM 采用「**可挂起函数**」（Suspendable Function）模型：挂起时将函数的 **整个栈帧复制到堆上**，恢复时从堆复制回栈。这一设计的核心数据结构是 `_SuspendState` 对象。

**`_SuspendState` 的结构**（来源：`sdk/lib/_internal/vm/lib/async_patch.dart`）：

```dart
@pragma("vm:entry-point")
class _SuspendState {
  // payload 区域：保存完整栈帧（局部变量、溢出槽、表达式栈）
  // pc：挂起点的程序计数器
  // function_data：_Future<T>（async）或 _AsyncStarStreamController<T>（async*）
  // frame_size：帧大小
  
  static Object? _initAsync<T>() => _Future<T>();  // 创建结果 Future

  void _createAsyncCallbacks() {
    final suspendState = this;
    thenCallback(value) { suspendState._resume(value, null, null); }
    errorCallback(Object exception, StackTrace stackTrace) {
      suspendState._resume(null, exception, stackTrace);
    }
    _thenCallback = thenCallback;
    _errorCallback = errorCallback;
  }
}
```

**关键设计决策**：每个可挂起函数拥有一个合成局部变量 `:suspend_state`，位于栈帧的固定偏移位置。首次挂起前该变量为 `null`，首次挂起后持有 `_SuspendState` 实例。回调 **惰性创建**——仅在第一次遇到 `await` 时才分配 then/error 回调闭包，因为大量 async 函数实际无 `await`。

**执行流时序**：

```
调用者          Future<T> foo() async           VM Stubs         _SuspendState
  │                                                │                   │
  ├──────调用────►│                                 │                   │
  │              │(prologue)──────────────────────►InitAsync           │
  │              │                                 │─────────────────►_initAsync()
  │              │                                 │                   │ 创建 _Future<T>
  │              │◄────────────────────────────────│◄──────────────────│
  │              │                                 │                   │
  │              │ [执行同步代码直到 await]          │                   │
  │              │                                 │                   │
  │              │(await expr)────────────────────►Suspend             │
  │              │    ┌ 复制栈帧到 _SuspendState ┐  │─────────────────►_await()
  │              │    │ 保存 PC、locals、表达式栈 │  │                   │ 惰性创建回调
  │◄─返回 Future─│    └──────────────────────────┘  │                   │ 注册 then/error
  │              │                                 │                   │
  │  [事件循环]   │                                 │                   │
  │              │                                 │                   │
  │  Future 完成→│                                 Resume              │
  │              │  ┌ 从 _SuspendState 恢复栈帧 ┐  │◄──────────────────│
  │              │  │ 跳转到挂起点 PC 继续执行   │  │                   │
  │              │  └──────────────────────────┘   │                   │
  │              │                                 │                   │
  │              │(return value)──────────────────►Return              │
  │              │                                 │─────────────────►_returnAsync()
  │              │                                 │                   │ 完成 _Future<T>
  │◄─Future 完成─│                                 │                   │
```

### 1.2 Kernel AST 中异步的表示方式

Kernel 二进制格式通过 **`FunctionNode`** 的两个字段表达异步标记：

| 字段 | 说明 |
|---|---|
| `asyncMarker` | 编译器变换后的标记（可能被修改为 `Sync`） |
| `dartAsyncMarker` | 源码中的原始标记：`Sync=0, SyncStar=1, Async=2, AsyncStar=3` |

**关键发现**：Dart VM 后端 **保留** Kernel AST 中的 `AwaitExpression` 和 `YieldStatement` 节点，由 `StreamingFlowGraphBuilder` 直接翻译为 IL 指令（`Suspend`、`Call1ArgStub` 等），**不进行 Kernel 层脱糖**。旧的脱糖变换（`pkg/kernel/lib/transformations/continuation.dart`）仅供 dart2js 等其他后端使用。

这对自定义解释器有重要启示：**应直接处理 `AwaitExpression` 和 `YieldStatement` 节点**，而非依赖 Kernel 层脱糖。

### 1.3 异步语义的精确约束

自定义解释器必须遵循的关键语义不变量：

- **async 函数被调用时立即创建 `Future<T>`** 并同步返回给调用者。函数体同步执行直到第一个 `await`。
- **`await` 总是异步的**——即使等待的 Future 已完成或等待的值不是 Future，也会至少产生一个 microtask 延迟。`await null` 等价于让出一次 microtask 时间片。
- **Future 展平**（Flattening）：async 函数返回 `Future<T>` 时，若 return 的值本身是 Future，会被隐式 await，不会产生 `Future<Future<T>>`。
- **Completer() 默认异步通知**——监听器通过 microtask 调度，而非同步调用。只有 `Completer.sync()` 同步触发。
- **Zone.current 始终正确**——回调在其被注册时的 Zone 中执行，错误不跨越 error zone 边界。

---

## 二、解释器 async/await 实现方案深度对比

### 2.1 四种候选方案

| 方案 | 核心思路 | 每次挂起分配 | 非挂起开销 | 实现复杂度 |
|---|---|---|---|---|
| **状态机** | 编译期将 async 函数按 await 点切分为状态，运行时通过 state label 切换 | 1 个状态对象 + 1 个 Completer | **近零**（一个条件判断） | ★★★★ |
| **续体（Continuation）** | 保存完整执行上下文（PC、栈帧快照、异常链），Future 完成时恢复 | 1 个帧快照对象 | 近零 | ★★★ |
| **CPS 变换** | 编译期将函数转为续体传递风格，每步以回调结尾 | N 个闭包（每个续体一个） | 闭包分配开销 | ★★★★★ |
| **协程（Stackful）** | 每个异步操作分配独立栈，yield/resume 切换栈指针 | **4KB-1MB**（一个栈） | 无 | ★★（需平台特定代码） |

### 2.2 推荐方案：帧快照式续体（Frame Snapshot Continuation）

综合分析后，推荐 **帧快照式续体方案**——本质上是 Dart VM 自身 Suspend/Resume 模型在字节码解释器中的类比实现。其核心思想是：**解释器的栈帧本身就是堆对象，挂起/恢复就是保存/恢复帧指针**，天然适配非递归的字节码分发循环。

此方案融合了状态机（编译期标注 await 点、局部变量提升）和续体（运行时保存/恢复帧状态）的优势，同时避免了纯 CPS 的闭包链开销和 Stackful 协程的高内存消耗。

**DarticFrame 的结构设计**：

```dart
class DarticFrame {
  final Uint8List bytecode;        // 函数字节码
  int ip;                          // 指令指针（挂起点 PC）
  final List<dynamic> locals;      // 局部变量表（含提升的跨 await 变量）
  final List<dynamic> valueStack;  // 操作数栈
  int stackTop;                    // 栈顶指针
  
  // 异步相关
  Completer<dynamic>? resultCompleter;  // async 函数的结果 Completer
  Function? thenCallback;               // 惰性创建的 then 回调
  Function? errorCallback;              // 惰性创建的 error 回调
  
  // 异常处理
  List<ExceptionHandler> handlerTable;  // 异常处理器表
  
  // 调用链
  DarticFrame? callerFrame;        // 调用者帧（同步调用链）
  Zone capturedZone;                    // 注册回调时的 Zone
  
  // 挂起/恢复
  dynamic resumeValue;                  // Future 完成时的返回值
  Object? resumeException;              // Future 完成时的异常
  StackTrace? resumeStackTrace;
}
```

### 2.3 字节码指令设计

```
操作码              操作数          语义描述
─────────────────────────────────────────────────────────────────────────
INIT_ASYNC          <type_index>   创建 Completer<T>，存入 frame.resultCompleter
                                   将 completer.future 压栈（供同步返回给调用者）

AWAIT               <resume_ip>    弹出栈顶值 v
                                   if v is! Future → 压入 v，IP 前进（快速路径）
                                   if v is Future:
                                     保存当前 IP 为 resume_ip
                                     惰性创建 then/error 回调
                                     v.then(thenCallback, onError: errorCallback)
                                     返回 SUSPENDED 信号给分发循环

ASYNC_RETURN                       弹出栈顶值 v
                                   if v is Future → v.then((r) => completer.complete(r))
                                   else → completer.complete(v)
                                   标记帧为已完成

ASYNC_THROW                        弹出 error 和 stackTrace
                                   completer.completeError(error, stackTrace)

INIT_ASYNC_STAR     <type_index>   创建 StreamController<T>
                                   将 controller.stream 压栈

YIELD               <resume_ip>    弹出值 v，添加到 StreamController
                                   检查 subscription 暂停状态
                                   if 暂停 → 保存帧，返回 SUSPENDED
                                   else → 继续执行

YIELD_STAR          <resume_ip>    弹出 Stream/Iterable，委托转发

INIT_SYNC_STAR      <type_index>   创建惰性 Iterable<T>（不执行函数体）
```

### 2.4 try/catch/finally 与 await 的交互

这是状态机方案的核心难点。当 `await` 出现在 `try` 块内部时，异常处理器必须跨越挂起/恢复边界：

```dart
// 源码
Future<int> complexAsync() async {
  try {
    var a = await fetchA();      // await 点 1
    try {
      var b = await fetchB(a);   // await 点 2
      return a + b;
    } finally {
      await cleanup();           // await 点 3（finally 中的 await！）
    }
  } catch (e) {
    return -1;
  }
}
```

**异常处理器表设计**：

```
字节码范围          处理器类型    跳转目标    栈深度
─────────────────────────────────────────────────────
[ip_try1, ip_end1)  catch         ip_catch    depth_1
[ip_try2, ip_end2)  finally       ip_finally  depth_2
```

关键规则：**帧恢复后，根据当前 IP 查找有效的异常处理器**。如果恢复时携带了异常（`resumeException != null`），解释器在恢复帧后立即跳转到对应的 catch/finally 处理器，而非继续正常执行。这与 Dart VM 的 `AsyncExceptionHandler` 存根行为一致。

```dart
void _resumeFrame(DarticFrame frame) {
  if (frame.resumeException != null) {
    // 查找覆盖当前 IP 的异常处理器
    var handler = _findHandler(frame, frame.ip);
    if (handler != null) {
      frame.valueStack[frame.stackTop++] = frame.resumeException;
      frame.valueStack[frame.stackTop++] = frame.resumeStackTrace;
      frame.ip = handler.targetIp;
    } else {
      // 无处理器 → 完成 Completer 为错误
      frame.resultCompleter?.completeError(
        frame.resumeException!, frame.resumeStackTrace);
      return;
    }
    frame.resumeException = null;
    frame.resumeStackTrace = null;
  } else {
    // 正常恢复：将值压栈
    frame.valueStack[frame.stackTop++] = frame.resumeValue;
    frame.resumeValue = null;
  }
  _runQueue.addFirst(frame);
  _scheduleDrive();
}
```

---

## 三、跨边界异步互调——最关键的设计

当异步操作跨越解释器-VM 边界时，产生四种基本交互模式。以 **Completer<T>** 作为统一桥接机制是关键设计决策。

### 3.1 模式一：VM 调用解释器的 async 函数

```
宿主 VM 代码                    解释器运行时                  解释器字节码
    │                              │                           │
    │  callInterpreterAsync()      │                           │
    ├─────────────────────────────►│                           │
    │                              │ 创建 DarticFrame     │
    │                              │ 创建 Completer<T>         │
    │                              │ frame.resultCompleter = c │
    │                              │──────────────────────────►│
    │                              │    开始执行字节码          │
    │                              │    (同步执行到 await)      │
    │                              │                           │ AWAIT
    │                              │◄──────────────────────────│ 返回 SUSPENDED
    │◄─ return completer.future ───│                           │
    │                              │                           │
    │  [VM 继续执行其他任务]        │                           │
    │                              │                           │
    │  Future 完成 (microtask) ───►│                           │
    │                              │  恢复帧执行               │
    │                              │──────────────────────────►│
    │                              │                           │ ASYNC_RETURN
    │                              │  completer.complete(v) ◄──│
    │◄── future.then 回调触发 ─────│                           │
```

**核心实现**：

```dart
/// VM 侧调用解释器 async 函数的入口
Future<T> callInterpreterAsync<T>(
  BytecodeFunction function,
  List<dynamic> args,
) {
  final completer = Completer<T>();
  final frame = DarticFrame(
    bytecode: function.bytecode,
    locals: _initLocals(function, args),
    resultCompleter: completer,
    capturedZone: Zone.current,  // 捕获调用者的 Zone
  );
  _runQueue.add(frame);
  _driveInterpreter();  // 同步执行直到挂起或完成
  return completer.future;  // 返回真正的 VM Future<T>
}
```

**返回值是 VM 原生 `Future<T>`**——因为 `Completer<T>.future` 就是 VM 的 `_Future<T>` 实例。VM 代码可以直接 `await` 这个 Future，与普通 Dart Future 完全一致。

### 3.2 模式二：解释器 await VM 的 Future

解释器代码中 `await http.get(url)` 时，被 await 的是 VM 原生 Future。

```dart
/// AWAIT 指令的运行时处理
_SuspendSignal _executeAwait(DarticFrame frame) {
  final value = frame.pop();
  
  // 快速路径：非 Future 值直接返回
  if (value is! Future) {
    frame.push(value);
    return _ContinueSignal();
  }
  
  // 惰性创建回调（仿 Dart VM 的 _createAsyncCallbacks 优化）
  frame.thenCallback ??= (dynamic result) {
    frame.resumeValue = result;
    frame.resumeException = null;
    // 在捕获的 Zone 中调度恢复
    frame.capturedZone.scheduleMicrotask(() => _resumeFrame(frame));
  };
  frame.errorCallback ??= (Object error, StackTrace stackTrace) {
    frame.resumeException = error;
    frame.resumeStackTrace = stackTrace;
    frame.capturedZone.scheduleMicrotask(() => _resumeFrame(frame));
  };
  
  // 注册到 VM Future 上
  value.then(
    frame.thenCallback as dynamic Function(dynamic),
    onError: frame.errorCallback as Function,
  );
  
  return _SuspendSignal();  // 通知分发循环挂起此帧
}
```

**Future.then() 的回调在哪个上下文运行**？回调由 VM 的 Future 机制调度，运行在 `Zone.current`（即 Future.then 被调用时的 Zone）。解释器通过 `frame.capturedZone` 确保恢复执行时 Zone 上下文正确。

### 3.3 模式三：VM await 解释器的 Future

这是模式一的延续。VM 代码：

```dart
// VM 侧
Future<void> processData() async {
  // 调用解释器定义的 async 函数
  var result = await callInterpreterAsync<int>('computeAsync', [42]);
  print('解释器返回: $result');
}
```

由于 `callInterpreterAsync` 返回的是 `Completer<int>.future`，这是 VM 类型系统完全认可的 `Future<int>`，VM 可以直接 await。泛型类型参数 `T` 通过 `Completer<T>` 的类型参数传递。

### 3.4 模式四：双向异步链——完整调用链时序

这是最复杂的场景：VM async → await 解释器 async → 解释器内部 await VM Future → 结果回传。

```
时间轴 →

VM async 函数 A          解释器 async 函数 B        VM async 函数 C (如 http.get)
    │                         │                          │
    │  await callInterp(B)    │                          │
    ├────────────────────────►│                          │
    │                         │ 创建 Completer_B         │
    │                         │ 开始执行字节码            │
    │                         │ ...同步代码...            │
    │                         │                          │
    │                         │ AWAIT http.get(url) ─────┤
    │                         │ 注册 then 回调            │ 发起 HTTP 请求
    │                         │ ← SUSPENDED              │
    │◄── Completer_B.future ──│                          │
    │                         │                          │
    │  [VM 事件循环运行]       │                          │ [网络 I/O]
    │                         │                          │
    │                         │                          │ HTTP 响应到达
    │                         │     then 回调触发 ◄───────│
    │                         │ ← 恢复帧执行              │
    │                         │ resumeValue = response    │
    │                         │ ...继续执行字节码...       │
    │                         │ ASYNC_RETURN(result)      │
    │                         │ Completer_B.complete(42)  │
    │                         │                          │
    │  await 完成，值 = 42 ◄──│                          │
    │  继续执行 A             │                          │
```

**Zone 的传播规则**：Zone 沿调用链向下传播。VM 函数 A 在 Zone_A 中调用解释器函数 B 时，B 的 `capturedZone` 为 Zone_A。B 内部 await VM Future C 时，then 回调注册在 Zone_A 中（因为 B 执行时 Zone.current = Zone_A）。这确保整条链的 Zone 一致性。

**异常的跨边界传播**：

```dart
// 场景：VM Future C 抛出异常
// C completes with error → B 的 errorCallback 触发
//   → frame.resumeException = error
//   → B 恢复执行，查找异常处理器
//   → 若 B 有 try/catch → 捕获，继续执行
//   → 若 B 无处理器 → Completer_B.completeError(error, stackTrace)
//   → A 的 await 收到异常 → A 的 try/catch 可捕获
//   → 若 A 也无处理器 → 错误传播到 Zone.handleUncaughtError
```

### 3.5 Stream 的跨边界处理

**解释器 async* 函数 → VM 消费**：

```dart
/// 解释器侧：创建 VM 原生 StreamController 作为桥梁
Stream<T> callInterpreterAsyncStar<T>(
  BytecodeFunction function,
  List<dynamic> args,
) {
  final controller = StreamController<T>();
  final frame = DarticFrame(
    bytecode: function.bytecode,
    locals: _initLocals(function, args),
  );
  
  // 绑定 StreamController 到帧
  frame.streamController = controller;
  
  // 惰性执行：仅在 listen 时启动
  controller.onListen = () {
    _runQueue.add(frame);
    _driveInterpreter();
  };
  controller.onPause = () {
    frame.streamPaused = true;  // yield 检查此标志
  };
  controller.onResume = () {
    frame.streamPaused = false;
    if (frame.isSuspendedAtYield) {
      _runQueue.add(frame);
      _scheduleDrive();
    }
  };
  controller.onCancel = () {
    frame.cancelled = true;
    // 触发 finally 块执行
  };
  
  return controller.stream;  // 返回 VM 原生 Stream<T>
}
```

**YIELD 指令的运行时实现**：

```dart
_Signal _executeYield(DarticFrame frame) {
  final value = frame.pop();
  final controller = frame.streamController!;
  
  controller.add(value);  // 将值发送到 Stream
  
  // 检查背压
  if (frame.streamPaused) {
    frame.isSuspendedAtYield = true;
    return _SuspendSignal();  // 暂停直到 onResume
  }
  
  return _ContinueSignal();  // 继续执行到下一个 yield
}
```

**VM Stream → 解释器 `await for`**：

解释器中的 `await for (var item in stream)` 编译为：

```
// 编译为以下字节码序列
LOAD stream                // 加载 VM 原生 Stream
INVOKE_METHOD 'listen'     // 调用 stream.listen(...)
// listen 的回调是一个桥接闭包：
//   onData: (value) { frame.resumeValue = value; resumeFrame(frame); }
//   onDone: () { frame.resumeValue = STREAM_DONE; resumeFrame(frame); }
//   onError: (e, s) { frame.resumeException = e; resumeFrame(frame); }
AWAIT_STREAM_NEXT          // 挂起，等待 onData/onDone/onError 回调
// 恢复后检查 STREAM_DONE 标志决定循环是否继续
```

### 3.6 Completer 桥接的完整设计

`Completer<T>` 是解释器-VM 之间一切异步桥接的基石。以下是防止泄漏的完整生命周期管理：

```dart
class AsyncBridge {
  final Set<Completer> _activeCompleters = {};
  
  Completer<T> createBridge<T>() {
    final c = Completer<T>();
    _activeCompleters.add(c);
    c.future.whenComplete(() => _activeCompleters.remove(c));
    return c;
  }
  
  /// 健康检查：检测可能泄漏的 Completer
  void checkLeaks(Duration timeout) {
    for (final c in _activeCompleters) {
      if (c.isCompleted) continue;
      // 如果 Completer 超时未完成，可能是泄漏
      // 记录警告日志
    }
  }
}
```

---

## 四、分发循环与事件循环的协作设计

### 4.1 分发循环的非阻塞架构

分发循环 **不能** 是阻塞式 `while(true)`。它必须协作式地与宿主 Dart 事件循环交替执行：

```dart
class InterpreterRuntime {
  final Queue<DarticFrame> _runQueue = Queue();
  bool _driving = false;
  
  void _scheduleDrive() {
    if (!_driving) {
      _driving = true;
      // 使用 scheduleMicrotask 而非 Timer，确保高优先级
      scheduleMicrotask(_driveInterpreter);
    }
  }
  
  void _driveInterpreter() {
    int fuel = 10000;  // 每次驱动周期的指令预算
    
    while (fuel > 0 && _runQueue.isNotEmpty) {
      final frame = _runQueue.first;
      
      while (fuel-- > 0) {
        final opcode = frame.bytecode[frame.ip++];
        
        switch (opcode) {
          case OpCode.LOAD_CONST:
            frame.push(_constants[frame.readUint16()]);
            break;
            
          case OpCode.AWAIT:
            final signal = _executeAwait(frame);
            if (signal is _SuspendSignal) {
              _runQueue.removeFirst();  // 从运行队列移除
              goto driveLoop;          // 检查下一个帧
            }
            break;  // 快速路径：继续执行
            
          case OpCode.ASYNC_RETURN:
            _executeAsyncReturn(frame);
            _runQueue.removeFirst();
            goto driveLoop;
            
          case OpCode.CALL:
            final newFrame = _executeCall(frame);
            _runQueue.addFirst(newFrame);  // 新帧优先执行
            goto driveLoop;
            
          // ... 其他指令
        }
      }
      
      driveLoop:
      continue;
    }
    
    // 燃料耗尽但仍有待执行帧 → 让出控制权给事件循环
    if (_runQueue.isNotEmpty) {
      scheduleMicrotask(_driveInterpreter);  // 下一个 microtask 继续
    } else {
      _driving = false;
    }
  }
}
```

**关键设计**：`fuel` 计数器防止解释器独占事件循环。每执行 **10,000 条指令**（可调）后让出控制权，确保 UI 不卡顿、I/O 事件得到处理。使用 `scheduleMicrotask` 而非 `Timer` 确保恢复执行的优先级高于事件队列。

### 4.2 同步快速路径优化

参考 V8 的优化和 C# 的 `awaiter.IsCompleted` 模式，当 await 的 Future **已经完成** 时应避免挂起：

```dart
_Signal _executeAwait(DarticFrame frame) {
  final value = frame.pop();
  
  // 快速路径 1：非 Future 值
  if (value is! Future) {
    frame.push(value);
    return _ContinueSignal();
  }
  
  // 快速路径 2：已完成的 Future（使用 Completer.sync 探测）
  // 注意：Dart 标准库不直接暴露 Future.isCompleted
  // 使用 sync Completer 技巧探测
  bool completed = false;
  dynamic syncResult;
  Object? syncError;
  StackTrace? syncStack;
  
  value.then(
    (v) { completed = true; syncResult = v; },
    onError: (e, s) { completed = true; syncError = e; syncStack = s; },
  );
  // 注意：上面的 then 回调在 microtask 中执行
  // 如果 Future 已完成，回调不会同步触发（除非 Completer.sync）
  // 因此这里 completed 仍然是 false
  
  // 严格遵循 Dart 语义：await 总是异步的
  // 即使 Future 已完成，也必须等到下一个 microtask
  _setupAsyncResume(frame, value);
  return _SuspendSignal();
}
```

**语义权衡**：Dart 规范要求 `await` 总是异步的。但 Dart VM 内部通过 `_awaitHelper` 进行了 **await elision 优化**——对于已完成的 Future，VM 可以在同一 microtask 内连续恢复多个 await（通过 Resume 存根的尾调用优化），实质上减少了 microtask 切换次数。自定义解释器可以选择两种策略：

1. **严格模式**：每个 await 都让出到 microtask 队列，保证完全的语义正确性
2. **优化模式**：检测已完成的 Future，在分发循环内直接恢复（不让出），性能更好但可能影响微妙的调度时序

推荐 **先实现严格模式，再在性能分析指导下添加优化**。

---

## 五、async*/sync* 生成器实现

### 5.1 async* 函数的帧生命周期

```dart
// 源码
Stream<int> count() async* {
  for (var i = 0; i < 3; i++) {
    await Future.delayed(Duration(seconds: 1));
    yield i;
  }
}
```

帧生命周期远比 async 函数复杂——**帧在多次 yield 之间反复挂起和恢复**，而非单次完成：

```
listen() → 创建帧，加入 runQueue
         → 执行到 await → 挂起（等待 Timer）
         → Timer 完成 → 恢复
         → 执行到 yield 0 → 发送值到 Stream，检查暂停
         → 继续执行 → await → 挂起
         → 恢复 → yield 1 → ...
         → 循环结束 → controller.close()
         → 帧销毁
```

### 5.2 sync* 的惰性求值

sync* 更为特殊——它是 **同步但可挂起** 的，每次 `moveNext()` 同步执行到下一个 yield：

```dart
class SyncStarIterator<T> implements Iterator<T> {
  DarticFrame _frame;
  T? _current;
  
  @override
  T get current => _current as T;
  
  @override
  bool moveNext() {
    // 同步执行帧直到 yield 或函数结束
    while (true) {
      final opcode = _frame.bytecode[_frame.ip++];
      switch (opcode) {
        case OpCode.YIELD:
          _current = _frame.pop() as T;
          return true;  // 挂起，返回 true
        case OpCode.YIELD_STAR:
          // 委托到嵌套 Iterable
          final inner = (_frame.pop() as Iterable<T>).iterator;
          _frame.delegateIterator = inner;
          if (inner.moveNext()) {
            _current = inner.current;
            return true;
          }
          break;  // 嵌套为空，继续
        case OpCode.RETURN:
          return false;  // 生成器结束
        default:
          _executeInstruction(_frame, opcode);
      }
    }
  }
}
```

sync* 不涉及事件循环，但仍需帧快照：每次 `moveNext()` 从上次 yield 点恢复，执行到下一个 yield 点再暂停。**关键差异**是 sync* 是同步挂起——调用者的控制流在 `moveNext()` 返回前不会继续。

---

## 六、跨语言参考与设计启示

### 6.1 V8 的关键优化：消除多余 Promise 包装

V8 v7.2 的优化将 `await` 的 microtick 开销从 **3 次降至 1 次**。核心策略：如果被 await 的值已经是原生 Promise，跳过额外的 Promise 包装层。类比到 Dart 解释器：**如果 await 的值已经是 VM 原生 `_Future`，直接注册回调而不额外创建 Completer**。

### 6.2 Kotlin 的 COROUTINE_SUSPENDED 哨兵值

Kotlin 的关键设计：suspend 函数返回 `Any?` 类型，可能是实际结果（同步完成）或 `COROUTINE_SUSPENDED` 哨兵（实际挂起）。调用者检查返回值以决定是否挂起。

**在 Dart 解释器中的对应设计**：

```dart
/// 哨兵值，标识帧已挂起
const _suspended = Object();

/// CALL 指令执行同步或异步函数
dynamic _executeCall(DarticFrame callerFrame, BytecodeFunction target) {
  if (target.isAsync) {
    // 创建子帧并执行
    final childFrame = DarticFrame(...);
    var result = _executeFrame(childFrame);
    if (identical(result, _suspended)) {
      // 子帧挂起 → 返回其 completer.future 给调用者
      callerFrame.push(childFrame.resultCompleter!.future);
    } else {
      // 子帧同步完成（无 await 的 async 函数）→ 直接用值
      callerFrame.push(result);
    }
  }
}
```

### 6.3 Lua 的续体函数模式

Lua 5.2+ 通过 `lua_yieldk(L, nresults, ctx, k)` 解决 C 函数中的协程挂起问题：挂起时指定一个续体函数 `k`，恢复时调用 `k` 而非返回到原函数。这启示我们处理 **解释器调用 VM 原生方法时的挂起**：

```dart
// 当解释器调用的 VM 方法返回 Future 时，
// 不能直接在 VM 方法的调用帧中挂起。
// 解决方案：VM 方法返回后检查结果类型
case OpCode.INVOKE_NATIVE:
  final nativeFunc = _nativeMethods[frame.readUint16()];
  final result = nativeFunc(args);  // 同步调用 VM 方法
  
  if (result is Future) {
    // VM 方法返回了 Future → 类似 Lua 的 yieldk 模式
    // 将 Future 压栈，后续 AWAIT 指令处理挂起
    frame.push(result);
  } else {
    frame.push(result);
  }
  break;
```

### 6.4 Cobalt（JVM 上的 Lua VM）的字节码重写

Cobalt 项目的关键发现：**为非挂起路径优化**比为挂起路径优化更重要。大多数函数 *可以* 挂起但 *很少* 挂起。Cobalt 将挂起/恢复逻辑放在冷路径上，热路径（不挂起时）几乎零开销。

对 Dart 解释器的启示：**分发循环的主路径不应因 async 支持而变慢**。AWAIT 指令的快速路径（非 Future 值）应只是一个类型检查 + 继续执行，与普通指令无异。

---

## 七、调试支持与异步栈追踪

### 7.1 因果异步栈追踪（Causal Async Stack Trace）

Dart VM 通过 `@pragma('vm:awaiter-link')` 维护 await 链的因果关系。自定义解释器需要类似机制：

```dart
class DarticFrame {
  // ...
  DarticFrame? awaiterFrame;  // 指向等待此帧结果的帧
  
  StackTrace buildAsyncStackTrace() {
    final frames = <String>[];
    var current = this;
    while (current != null) {
      frames.add('${current.functionName}:${current.ip}');
      if (current.isSuspended) {
        frames.add('<asynchronous suspension>');
      }
      current = current.awaiterFrame;
    }
    return StackTrace.fromString(frames.join('\n'));
  }
}
```

### 7.2 跨边界栈追踪拼接

当异常从 VM Future 传播到解释器帧时，需要拼接两侧的栈追踪：

```dart
void _onFutureError(DarticFrame frame, Object error, StackTrace vmTrace) {
  // 拼接 VM 栈追踪和解释器栈追踪
  final interpreterTrace = frame.buildAsyncStackTrace();
  final combinedTrace = CombinedStackTrace(interpreterTrace, vmTrace);
  
  frame.resumeException = error;
  frame.resumeStackTrace = combinedTrace;
}
```

---

## 八、性能与复杂度权衡总结

| 维度 | 帧快照续体（推荐） | 编译期状态机 | 纯 CPS |
|---|---|---|---|
| 每次挂起内存 | ~200-500B（帧对象） | ~100-300B（状态对象） | N×闭包（链式） |
| 非挂起路径开销 | 1 次类型检查 | 1 次条件判断 | 闭包分配 |
| 实现复杂度 | 中等 | 高（编译器变换复杂） | 极高（全面 CPS 传染） |
| try/catch 支持 | 自然（异常处理器表） | 复杂（跨状态异常路由） | 非常复杂 |
| 调试友好性 | 好（帧可检查） | 差（状态编号不直观） | 极差 |
| 与 VM 互操作 | **优秀**（Completer 桥接） | 良好 | 一般 |

---

## 九、架构建议与实施路线

**推荐分三阶段实施**：

**阶段一：基础 async/await**。实现 `INIT_ASYNC`、`AWAIT`、`ASYNC_RETURN`、`ASYNC_THROW` 四条指令。使用 `Completer<T>` 桥接所有跨边界 Future。分发循环采用 fuel 预算 + `scheduleMicrotask` 协作调度。严格遵循 microtask 语义（每个 await 都让出）。实现基本的 try/catch 跨 await 点异常处理。

**阶段二：生成器与 Stream**。实现 `INIT_ASYNC_STAR`、`YIELD`、`YIELD_STAR` 指令。使用 `StreamController<T>` 桥接 async* 返回的 Stream。实现背压处理（onPause/onResume）。实现 sync* 的惰性迭代器。实现 `await for` 的 Stream 消费。

**阶段三：优化与高级特性**。添加同步快速路径（await 已完成 Future 时不让出）。实现惰性回调创建优化。实现因果异步栈追踪。添加 Zone 传播支持。评估 `Completer.sync()` 在内部链路中的应用以减少 microtask 开销。

这一架构的核心优势在于：**解释器的帧天然是堆对象**，不需要额外的栈帧复制操作（这正是 Dart VM 需要 Suspend/Resume 存根处理的部分）。当解释器帧需要挂起时，只需将其从运行队列移除；恢复时加回队列。帧的全部状态（IP、locals、操作数栈）已经在堆上，无需任何特殊的序列化/反序列化。这使得帧快照续体方案在字节码解释器中的实现成本远低于在编译到本机代码的 VM 中的实现成本——可以说，字节码解释器是实现异步挂起/恢复的理想架构。