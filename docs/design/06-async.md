# Chapter 6: 异步与生成器

## 模块定位

异步与生成器模块为字节码解释器提供 `async`/`await`、`async*`/`yield`、`sync*`/`yield` 的运行时支持。核心洞察是**帧即续体**——解释器帧（InterpreterFrame）是堆对象，挂起时将全局栈中帧占用的区间快照到帧对象，恢复时在栈顶重新分配空间并拷回，帧本身封装了挂起/恢复的全部状态。通过 `Completer<T>` 和 `StreamController<T>` 桥接，解释器的 async/async* 函数返回 VM 原生 `Future<T>` / `Stream<T>`，对宿主代码完全透明。

## 与其他模块的关系

| 方向 | 模块 | 接口 |
|------|------|------|
| 依赖 | Ch2 运行时 | 使用全局 ValueStack/RefStack 和分发循环；挂起/恢复修改栈指针 |
| 依赖 | Ch1 ISA | 消费 AWAIT、YIELD 等异步指令的编码和操作数 |
| 依赖 | Ch4 编译器 | 编译器为每个 async/generator 函数输出寄存器数量，决定快照大小 |
| 被依赖 | Ch3 互调 | 跨边界异步互调通过本章的 Completer/StreamController 桥接 |
| 契约 | Ch7 沙箱 | 沙箱验证器检查异步指令的合法性（如 AWAIT 仅出现在 async 函数内） |

## 设计决策

| 决策项 | 选择 | 备选方案与拒绝理由 | 理由 |
|--------|------|-------------------|------|
| async 实现策略 | 帧快照续体 | CPS 变换：编译器复杂度高，生成代码膨胀 2-3x；状态机脱糖：Kernel 后端不做 async 脱糖，需自建 | 解释器帧已在堆上，快照 10-50 槽位（80-400 字节 memcpy）代价远低于 Future.then 回调（~5-10μs） |
| 跨边界桥接 | Completer\<T\>（async）/ StreamController\<T\>（async*） | 自定义 Future 子类：需处理 Zone、错误传播等大量边界情况 | 返回 VM 原生 Future/Stream，宿主代码可直接 await |
| 协作调度 | fuel 耗尽 → `Timer.run`；await 恢复 → `scheduleMicrotask` | 无让出：阻塞事件循环；每帧让出：microtask 开销过大 | 不饿死 event queue，同时保持热路径同步执行 |
| 恢复栈分配 | 栈顶重新分配 | 写回原位置：挂起期间原栈区间可能被其他活跃帧占用，导致数据覆盖 | 保证恢复帧区间不与任何活跃帧重叠 |
| sync* 阻塞 | 接受限制 | 加 fuel 切片：sync* 是同步语义，切片会破坏调用者对同步返回的预期 | sync* 语义是同步阻塞，调用者已有预期 |
| Kernel 处理 | 直接处理 AwaitExpression / YieldStatement | 在 Kernel 层做 async 脱糖：Dart VM 后端不做此脱糖，无参考实现 | 与 Dart VM 后端行为一致 |

## 核心概念

### 帧即续体（Frame-as-Continuation）

字节码解释器的核心异步优势：InterpreterFrame 是堆对象，挂起/恢复的全部状态封装在帧中。不同于原生编译器需要 CPS 变换或状态机脱糖，解释器天然具备暂停和恢复的能力——只需保存帧的 PC 和栈快照。

### 浅保存与深保存

InterpreterFrame 的挂起存在两种深度，按场景选择以平衡正确性与性能：

| | 浅保存（fuel 让出） | 深保存（AWAIT / YIELD 挂起） |
|---|---|---|
| 触发 | fuel 耗尽，`Timer.run` 调度下一回合 | AWAIT 遇到 Future / YIELD 遇到 Stream paused |
| 保存内容 | pc、savedVBase、savedRBase（几个 int） | pc + 栈数据完整快照（savedValueSlots / savedRefSlots） |
| 栈空间 | 保留占用——帧仍在 `_runQueue` 中，栈区间不释放 | 释放——帧从 `_runQueue` 移除，原栈位置可被其他帧复用 |
| 恢复位置 | 原位继续（下回合 `_driveInterpreter` 取同一帧） | 栈顶重新分配（恢复不变式） |
| 代价 | ≈0（几次 int 赋值） | <1μs（memcpy 80-400 字节 + 引用栈置 null） |

**深保存必须快照的原因**：帧从 `_runQueue` 移除后栈空间被释放，后续帧可能分配到同一区间。若不快照，恢复时原位数据已被覆盖。浅保存无此问题——帧留在 `_runQueue` 中，栈空间持续占用，无人会覆盖。

### 异步帧状态机

```
                ┌─────────────────────────────────────────────┐
                │                                             │
                ▼                                             │
┌──────┐   INIT_ASYNC   ┌──────┐   执行字节码    ┌──────┐    │
│ 创建 │───────────────►│ 运行 │──────────────►│ 完成 │    │
└──────┘                └──┬───┘               └──────┘    │
                           │                       ▲        │
                      AWAIT│遇到                   │ASYNC_  │
                      Future                       │RETURN  │
                           │                       │        │
                           ▼                       │        │
                      ┌──────┐   Future 完成   ┌──────┐    │
                      │ 挂起 │────────────────►│ 恢复 │────┘
                      └──────┘  scheduleMicro  └──────┘
                                   task
```

- **创建**：INIT_ASYNC 创建 Completer，帧进入运行态
- **运行**：正常执行字节码，与同步帧无异
- **挂起**：AWAIT 遇到 Future → 快照栈数据到帧对象，注册回调
- **恢复**：Future 完成 → scheduleMicrotask → 在栈顶分配新空间、拷回数据、写入恢复值
- **完成**：ASYNC_RETURN 完成 Completer，帧生命周期结束

### InterpreterFrame 字段

InterpreterFrame 的异步相关字段按功能分组（基础字段详见 Ch2）：

**基础字段**

| 字段名 | 类型 | 用途 |
|--------|------|------|
| bytecode | Uint32List | 当前函数的字节码序列 |
| pc | int | 程序计数器，挂起时保存恢复点 |
| icTable | List\<InlineCacheEntry\> | 内联缓存表（详见 Ch2） |

**栈快照字段**

| 字段名 | 类型 | 用途 |
|--------|------|------|
| savedVSP | int | 挂起时的值栈指针 |
| savedRSP | int | 挂起时的引用栈指针 |
| savedVBase | int | 挂起时值栈帧基址 |
| savedRBase | int | 挂起时引用栈帧基址 |
| savedValueSlots | Int64List? | 值栈快照（帧占用区间），恢复后置 null |
| savedRefSlots | List\<Object?\>? | 引用栈快照（帧占用区间），恢复后置 null |

**异步扩展字段**

| 字段名 | 类型 | 用途 |
|--------|------|------|
| resultCompleter | Completer\<Object?\>? | async 函数的结果 Completer |
| thenCallback | Function? | 惰性创建的 then 回调，避免每次 await 分配 |
| errorCallback | Function? | 惰性创建的 error 回调 |

**生成器扩展字段**

| 字段名 | 类型 | 用途 |
|--------|------|------|
| streamController | StreamController\<Object?\>? | async* 的输出 Stream |
| streamPaused | bool | Stream 是否被暂停 |
| isSuspendedAtYield | bool | 是否因 Stream 暂停而在 yield 点挂起 |
| cancelled | bool | 订阅是否已取消 |

**异常处理字段**

| 字段名 | 类型 | 用途 |
|--------|------|------|
| handlerTable | List\<ExceptionHandler\> | 异常处理器表，按 PC 范围匹配 |

**挂起恢复字段**

| 字段名 | 类型 | 用途 |
|--------|------|------|
| awaitDestReg | int | AWAIT 指令的目标寄存器 A（恢复时写入结果） |
| resumeValue | Object? | Future 正常完成的恢复值 |
| resumeException | Object? | Future 异常完成的异常对象 |
| resumeStackTrace | StackTrace? | 异常对应的栈追踪 |
| capturedZone | Zone | 帧创建时捕获的 Zone.current |
| awaiterFrame | InterpreterFrame? | 等待此帧结果的帧（异步栈追踪用） |

### 异步帧与全局栈的交互

全局 ValueStack/RefStack 是所有帧共享的线性空间（详见 Ch2）。多个 async 帧可能并发挂起，它们的栈区间在全局栈上可能重叠——后启动的帧分配到与先挂起帧相同的栈位置。因此挂起时必须快照栈数据，恢复时在栈顶重新分配空间。

**栈恢复不变式**：

1. **新空间分配**：恢复帧总是在当前栈顶（`_vs.sp` / `_rs.sp`）分配新空间，绝不写回原 `savedVBase` / `savedRBase` 位置
2. **无重叠保证**：恢复后的帧区间 `[newBase, newBase+size)` 不与任何活跃帧的栈区间重叠
3. **基址更新**：恢复后帧的 `savedVBase` / `savedRBase` 更新为新位置，后续字节码使用新基址

**栈安全性：async 完成不走栈回退**

恢复不变式保证恢复帧在栈顶，但还需说明帧完成后不会向下覆盖其他活跃帧。以下时序说明两个并发 async 帧的栈安全性：

```
时刻1: bar 运行中
  栈: [...bar...]

时刻2: foo 恢复，在栈顶分配空间
  栈: [...bar...][foo]

时刻3: foo 执行 ASYNC_RETURN → completer.complete(result)
  foo 的栈空间释放，sp 回退到 bar 之上
  栈: [...bar...]
  （注意：不是 sync RETURN——不弹 CallStack，不跳回 bar 或其他帧的代码）

时刻4: foo 的等待者（如帧 C）通过 scheduleMicrotask 恢复
  C 在栈顶分配新空间
  栈: [...bar...][C]
  C 继续执行，其子调用同样在 C 之上，不会触及 bar 的栈区间
```

关键区别在于：sync RETURN 是控制流转移（弹栈、跳回调用者代码），async RETURN 是消息传递（complete Completer、等待者自行恢复）。因此恢复帧完成后只释放自身空间，不会修改其下方任何活跃帧的栈区间。

## 工作流程

### 挂起流程（Suspend）

AWAIT 遇到真 Future 时触发：

1. **保存 PC**：`frame.pc = resumePC`（AWAIT 指令的 Bx 操作数）
2. **保存目标寄存器**：`frame.awaitDestReg = destReg`（AWAIT 指令的 A 操作数）
3. **快照值栈区间**：将 `[savedVBase, savedVSP)` 拷贝到 `frame.savedValueSlots`（Int64List.setRange，底层 memcpy）
4. **快照引用栈区间 + 置 null 助 GC**：将 `[savedRBase, savedRSP)` 拷贝到 `frame.savedRefSlots`，原栈位置全部置 null 释放引用

### 恢复流程（Resume）

Future 完成后，通过 `scheduleMicrotask` 触发：

1. **分配新空间**：在当前栈顶 `_vs.sp` / `_rs.sp` 位置预留帧所需的槽位数
2. **恢复值栈**：从 `savedValueSlots` 拷贝到新位置（Int64List.setRange），然后置 null 释放快照
3. **恢复引用栈**：从 `savedRefSlots` 逐项拷贝到新位置，然后置 null 释放快照
4. **更新帧基址**：`savedVBase` / `savedRBase` / `savedVSP` / `savedRSP` 全部更新为新位置，推进全局 sp
5. **写入恢复值**：正常完成 → `refStack[awaitDestReg] = resumeValue`；异常完成 → 查找异常处理器，写入异常寄存器位置

### AWAIT 指令语义

AWAIT 总是导致帧挂起——无论 await 的值是否为 Future，符合 Dart 语言规范（`await e` 总是让出至少一次 microtask）：

- **值为 Future**：注册惰性创建的 then/error 回调，Future 完成时 `scheduleMicrotask` 恢复帧
- **值非 Future**：直接将值存入 `resumeValue`，`scheduleMicrotask` 恢复帧

回调惰性创建（`thenCallback` / `errorCallback`）避免每次 AWAIT 分配新闭包——多数 async 函数包含多个 await 点。

### 分发循环集成

分发循环主路径不因 async 支持变慢（详见 Ch2）：

```
case OpCode.AWAIT:
  executeAwait(frame, decodeA(instr), decodeBx(instr));
  _runQueue.removeFirst();
  break innerLoop;  // 总是挂起，等待 microtask 恢复
```

大多数 async 函数在无 await 时同步完成——INIT_ASYNC 仅创建一个 Completer，ASYNC_RETURN 同步完成它，全程不挂起。

ASYNC_RETURN 的分发循环处理与 AWAIT 对称，但语义完全不同于同步 RETURN：

```
case OpCode.ASYNC_RETURN:
  frame.resultCompleter!.complete(refStack[decodeA(instr)]);
  _runQueue.removeFirst();
  break innerLoop;  // 帧生命周期结束，不走 CallStack 回退
```

同步 RETURN 弹出 CallStack、恢复调用者的 pc/vBase/rBase、在调用者帧内继续执行。ASYNC_RETURN 不触碰 CallStack——它通过 `completer.complete()` 将结果投递给等待者，等待者自行在栈顶恢复。

### try/catch 与 await 的交互

异常处理器表跨越 await 点。恢复帧后根据当前 PC 线性扫描 `handlerTable`，找到 `startPC <= pc < endPC` 的处理器。finally 中的 await 正常工作——finally 块的字节码序列包含 AWAIT 指令，挂起/恢复机制与普通 await 一致。

### async* 生成器

**创建**：INIT_ASYNC_STAR 创建 StreamController\<T\>，注册 onListen/onPause/onResume/onCancel 回调控制帧执行。

**YIELD 语义**：
1. `controller.add(value)` 发送值
2. 若 Stream 已暂停或已取消 → 保存恢复点，帧进入 SUSPENDED 状态
3. 否则继续执行

**await for 编译**：`await for (var item in stream)` 编译为 `stream.listen` + AWAIT 序列：

```
CALL_VIRTUAL  rSubscription, rStream, 'listen'
  // onData:  frame.resumeValue = value; resume
  // onDone:  frame.resumeValue = SENTINEL_DONE; resume
  // onError: frame.resumeException = e; resume
LOOP_HEAD:
  AWAIT_STREAM_NEXT                  // 挂起等待
  EQ_REF      rCmp, rResult, rDone
  JUMP_IF_TRUE rCmp, LOOP_EXIT
  // ... 循环体 ...
  JUMP LOOP_HEAD
LOOP_EXIT:
  CALL_VIRTUAL  rFuture, rSubscription, 'cancel'
  AWAIT         rFuture              // await subscription.cancel()
```

### sync* 生成器

sync* 使用同步阻塞式执行。SyncStarIterator 包装一个 InterpreterFrame，每次 `moveNext()` 从上次 yield 点恢复执行到下一个 yield 点暂停，通过回调将 yield 的值设为 `current`。

**已知限制**：sync* 两个 yield 之间的计算如果耗时很长，会阻塞事件循环。这是 sync* 的同步语义决定的，不做 fuel 限制处理。

### 跨边界异步互调

四种模式覆盖了 VM 与解释器之间所有异步交互场景：

| 模式 | 发起方 | 机制 | 结果 |
|------|--------|------|------|
| VM → 解释器 async | VM | 调用 `callInterpreterAsync<T>()`，创建帧 + Completer | 返回 VM 原生 `Future<T>`，VM 可直接 await |
| 解释器 await VM Future | 解释器 | AWAIT 指令遇到 VM 原生 Future → 注册 then/error 回调 | Future 完成时 scheduleMicrotask 恢复帧 |
| VM await 解释器 Future | VM | 模式 1 的延续，VM await `Completer.future` | Completer 完成时 VM 自然恢复 |
| 双向链 | 双方 | VM async A → await 解释器 B → B await VM C | 通过 Completer 链自然串联，C→B→A 依次恢复 |

### Zone 传播

Zone 沿调用链向下传播。帧创建时捕获 `Zone.current` 到 `capturedZone` 字段，恢复执行时在正确的 Zone 中调度（`frame.capturedZone.scheduleMicrotask(...)`）。这保证了 Zone 内的错误处理、日志、调度等行为正确传播到解释器代码。

### 异常跨边界传播

```
VM Future 异常 → errorCallback 触发
  → frame.resumeException = error
  → 帧恢复，查找 handler
  → 有 catch → 解释器内处理
  → 无 catch → completer.completeError() → VM 的 await 收到异常
```

异常栈追踪拼接：errorCallback 中将 VM 栈追踪与解释器帧的异步栈追踪合并为 CombinedStackTrace。

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

## 关键约束与边界条件

| 约束 | 值 | 来源 / 依据 |
|------|-----|------------|
| 连续恢复上限 | maxResumesPerRound = 64 | 防止频繁 await-resume 绕过 fuel 配额；超限后降级为 `Timer.run` 让出事件循环 |
| 帧快照大小 | 10-50 槽位（80-400 字节） | 由编译器寄存器分配输出决定（`FuncProto.refRegCount` + `valueRegCount`） |
| 快照拷贝延迟 | <1μs | Int64List.setRange 底层 memcpy，现代 CPU 上 80-400 字节拷贝 |
| await 语义 | 总是让出 ≥1 次 microtask | Dart 语言规范要求，即使 await 非 Future 值也必须让出 |
| sync* 阻塞 | 无 fuel 限制 | 同步语义，调用者对阻塞有预期 |

## 已知局限与演进路径

| 局限 | 影响 | 演进 |
|------|------|------|
| sync* 两 yield 间长计算阻塞事件循环 | 用户可感知卡顿 | 接受限制，sync* 语义决定 |
| Completer 泄漏检测仅依赖 WeakReference | 无主动告警 | > **Phase 2**：添加诊断计数器 `pendingCount`，可通过调试接口查询。触发条件：用户报告 async 函数"不返回"的 bug |
| 异步栈追踪为简化拼接 | 跨边界追踪可读性差 | > **Phase 2**：实现 causal async stack trace（类似 Dart VM 的 --causal-async-stacks）。触发条件：用户反馈异步调试体验不佳 |
| 无 async* yield* 的背压传播 | 高速生产者可能 OOM | > **Phase 2**：yield* 检测目标 Stream 的 pause 状态。触发条件：async* 相关 OOM 报告 |

## 附录：参考实现

<details>
<summary>挂起流程（_suspendFrame）</summary>

```dart
void _suspendFrame(InterpreterFrame frame) {
  final vBase = frame.savedVBase;
  final vSize = frame.savedVSP - vBase;
  final rBase = frame.savedRBase;
  final rSize = frame.savedRSP - rBase;
  if (vSize > 0) {
    frame.savedValueSlots = Int64List(vSize);
    frame.savedValueSlots!.setRange(0, vSize, _vs.intView, vBase);
  }
  if (rSize > 0) {
    frame.savedRefSlots = List<Object?>.filled(rSize, null);
    for (int i = 0; i < rSize; i++) {
      frame.savedRefSlots![i] = _rs.slots[rBase + i];
      _rs.slots[rBase + i] = null; // 释放引用，允许 GC
    }
  }
}
```

</details>

<details>
<summary>恢复流程（_restoreFrameStack + _resumeFrame）</summary>

```dart
void _restoreFrameStack(InterpreterFrame frame) {
  final vSize = frame.savedValueSlots?.length ?? 0;
  final rSize = frame.savedRefSlots?.length ?? 0;
  final newVBase = _vs.sp;
  final newRBase = _rs.sp;
  if (frame.savedValueSlots != null) {
    _vs.intView.setRange(newVBase, newVBase + vSize, frame.savedValueSlots!);
    frame.savedValueSlots = null;
  }
  if (frame.savedRefSlots != null) {
    for (int i = 0; i < rSize; i++) {
      _rs.slots[newRBase + i] = frame.savedRefSlots![i];
    }
    frame.savedRefSlots = null;
  }
  frame.savedVBase = newVBase;
  frame.savedRBase = newRBase;
  frame.savedVSP = newVBase + vSize;
  frame.savedRSP = newRBase + rSize;
  _vs.sp = newVBase + vSize;
  _rs.sp = newRBase + rSize;
}
```

</details>
