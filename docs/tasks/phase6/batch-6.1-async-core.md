# Batch 6.1: 异步核心 (Ch7)

## 概览

基于帧即续体（Frame-as-Continuation）模型实现 async/await、sync* 和 async* 运行时支持。DarticFrame 挂起时将全局栈区间快照到帧对象（深保存），恢复时在栈顶重新分配空间并拷回，通过 Completer/StreamController 桥接返回 VM 原生 Future/Stream。编译器将 `_emitAsyncStub` 替换为真正的异步函数编译：INIT_ASYNC/AWAIT/ASYNC_RETURN 用于 async 函数，INIT_SYNC_STAR/YIELD 用于 sync* 生成器，INIT_ASYNC_STAR/YIELD/AWAIT_STREAM_NEXT 用于 async* 生成器。

**设计参考：** `docs/design/07-async.md`（帧即续体、DarticFrame 字段、挂起/恢复流程、异步帧状态机、sync*/async* 生成器、AWAIT 语义、栈恢复不变式、参考实现 _suspendFrame/_restoreFrameStack/_resumeFrame）、`docs/design/03-execution-engine.md`（分发循环集成、_runQueue、fuel 让出）、`docs/design/01-bytecode-isa.md`（操作码 0x80-0x88）、`docs/design/05-compiler.md`（Generator 编译 line 456-474、emittedValueType）

**依赖：** Phase 5 全部完成

---

### Task 6.1.1: DarticFrame 异步字段 + 挂起/恢复机制

**产出文件：**
- Modify: `lib/src/runtime/frame.dart`（增加 14 个异步/生成器控制字段）
- Modify: `lib/src/runtime/interpreter.dart`（增加 _suspendFrame + _restoreFrameStack 方法）
- Test: `test/runtime/frame_suspend_resume_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch7"DarticFrame 字段"节：三组字段分类——基础与栈快照字段（已有）、异步与生成器控制字段（resultCompleter, thenCallback, errorCallback, streamController, streamPaused, isSuspendedAtYield, cancelled）、挂起恢复字段（awaitDestReg, resumeValue, resumeException, resumeStackTrace, capturedZone, awaiterFrame）。Ch7"浅保存与深保存"表格对比两种挂起深度。Ch7 附录参考实现：_suspendFrame（快照值栈+引用栈区间到帧对象，引用栈原位置置 null 助 GC）、_restoreFrameStack（在栈顶分配新空间、拷回数据、更新帧基址）
2. **写测试** — 验证：
   - DarticFrame 增加字段后的基本属性读写
   - _suspendFrame 正确快照值栈区间到 savedValueSlots（Int64List）
   - _suspendFrame 正确快照引用栈区间到 savedRefSlots（List<Object?>），且原栈位置全部置 null
   - _restoreFrameStack 在栈顶（非原位）分配新空间
   - _restoreFrameStack 恢复后 savedVBase/savedRBase 更新为新位置
   - 多帧挂起/恢复交错——帧 A 挂起、帧 B 占用相同栈区间、帧 A 恢复到栈顶——数据完整
   - 空帧（0 个值栈槽位 + 0 个引用栈槽位）挂起/恢复正常
3. **实现** —
   - DarticFrame 增加 Ch7 定义的全部异步/生成器控制字段（nullable，初始为 null/false/0）
   - 解释器增加 `_suspendFrame(DarticFrame)` 方法：按 Ch7 附录参考实现，快照 [savedVBase, savedVSP) 到 savedValueSlots，快照 [savedRBase, savedRSP) 到 savedRefSlots，引用栈原位置置 null
   - 解释器增加 `_restoreFrameStack(DarticFrame)` 方法：在当前 _vs.sp/_rs.sp 位置分配空间，从快照拷回数据，更新帧基址和全局 sp，释放快照引用
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/frame_suspend_resume_test.dart`

---

### Task 6.1.2: async/await — INIT_ASYNC + AWAIT + ASYNC_RETURN + ASYNC_THROW

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`（4 个新 opcode case + _resumeFrame 方法）
- Modify: `lib/src/compiler/compiler.dart`（替换 _emitAsyncStub → 真正的 async 编译）
- Modify: `lib/src/compiler/compiler_expressions.dart`（AwaitExpression visitor）
- Modify: `lib/src/compiler/compiler_statements.dart`（async ReturnStatement 分支）
- Modify: `lib/src/compiler/compiler_closures.dart`（async 闭包编译）
- Test: `test/runtime/async_interpreter_test.dart`
- Test: `test/e2e/async_e2e_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch7"异步帧状态机"：创建 → 运行 → 挂起 → 恢复 → 完成。Ch7"AWAIT 指令语义"：总是导致帧挂起，值为 Future 时注册 then/error 回调，值非 Future 时直接 scheduleMicrotask 恢复。Ch7"分发循环集成"：AWAIT → _suspendFrame → 注册回调 → _runQueue.removeFirst → break innerLoop。ASYNC_RETURN → completer.complete → _runQueue.removeFirst → break innerLoop。Ch7"回调惰性创建"：thenCallback/errorCallback 在帧上缓存避免重复分配。Ch7"emittedValueType"：编译器从 FunctionNode.emittedValueType 获取 T，编译为 TypeTemplate 存常量池 refs[Bx]，INIT_ASYNC 创建 Completer\<T\>。Ch5"Generator 编译"（line 456-474）
2. **写测试** —
   - **解释器测试**（手工字节码）：
     - INIT_ASYNC 创建 Completer，refStack[A] = completer.future
     - AWAIT 值为已完成 Future 时，帧挂起后通过 microtask 恢复
     - AWAIT 值为非 Future 时，帧挂起后通过 microtask 恢复
     - AWAIT 值为未完成 Future 时，Future 完成后帧恢复
     - ASYNC_RETURN 正确 complete Completer
     - ASYNC_THROW 正确 completeError
     - 多个 AWAIT 点的 async 函数——每次恢复后 PC 正确更新
     - 异常在 async 函数内被 catch → 正常继续
     - 异常未被 catch → ASYNC_THROW 传播到 Completer
   - **E2E 测试**（Dart 源码 → 编译 → 执行）：
     - `Future<int> f() async { return 42; } void main() async { print(await f()); }`
     - `Future<int> f() async { await Future.value(1); return 2; }`
     - `Future<int> f() async { try { throw 'err'; } catch (e) { return 0; } }`
     - 多级 await 链：`a() async => await b(); b() async => await c(); c() async => 42;`
     - async 闭包：`var f = () async { return 42; }; await f();`
3. **实现** —
   - **解释器**：
     - `case Op.initAsync`：从常量池 refs[Bx] 取 emittedValueType TypeTemplate → 实化 → 创建 `Completer<T>()` → 存入 frame.resultCompleter → refStack[rBase + A] = completer.future
     - `case Op.await_`：保存 awaitDestReg = A → 设置 frame.pc = Bx（恢复点）→ _suspendFrame(frame) → 检查 refStack[rBase + A] 是否为 Future → 若是则注册 then/error 回调（惰性创建）→ 若否则 scheduleMicrotask 直接恢复 → _runQueue.removeFirst → break innerLoop
     - _resumeFrame：_restoreFrameStack → 写入恢复值（正常：refStack[awaitDestReg] = resumeValue；异常：查找 exceptionTable handler）→ 加入 _runQueue
     - `case Op.asyncReturn`：frame.resultCompleter!.complete(refStack[rBase + A]) → _runQueue.removeFirst → break innerLoop
     - `case Op.asyncThrow`：frame.resultCompleter!.completeError(refStack[rBase + A], refStack[rBase + B]) → _runQueue.removeFirst → break innerLoop
   - **编译器**：
     - `_compileFunction2c`：当 fn.asyncMarker == AsyncMarker.Async 时，不再调用 _emitAsyncStub，而是：(a) 从 fn.emittedValueType 编译 TypeTemplate 存入常量池 → 获取 Bx (b) 分配 ref 寄存器 A (c) emit INIT_ASYNC A, Bx (d) 正常编译函数体 (e) 函数末尾 safety net 改为 ASYNC_RETURN null
     - 新增 `_compileAwaitExpression`（ExpressionVisitor）：编译操作数到 ref 寄存器 A → 分配恢复点 Bx（通过占位 + 回填方式，或使用当前 code.length + 1 作为恢复 PC）→ emit AWAIT A, Bx → 恢复后结果在 refStack[A]
     - 修改 `_compileReturnStatement`：检测当前函数 asyncMarker，若为 Async → 编译返回值到 ref 栈 → emit ASYNC_RETURN（非 RETURN_REF/RETURN_VAL）
     - 修改 `_compileFunctionExpression`（闭包）：同样替换 _emitAsyncStub 为真正 async 闭包编译
   - **Zone 传播**：帧创建时捕获 Zone.current 到 capturedZone，恢复时在 capturedZone 内调度 scheduleMicrotask
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/async_interpreter_test.dart && fvm dart test test/e2e/async_e2e_test.dart`

---

### Task 6.1.3: sync* 生成器 — INIT_SYNC_STAR + YIELD

**产出文件：**
- Create: `lib/src/runtime/sync_star.dart`（SyncStarIterable + SyncStarIterator）
- Modify: `lib/src/runtime/interpreter.dart`（INIT_SYNC_STAR + YIELD sync* 分支 + drive 方法）
- Modify: `lib/src/compiler/compiler.dart`（sync* 函数编译）
- Modify: `lib/src/compiler/compiler_statements.dart`（YieldStatement visitor）
- Test: `test/runtime/sync_star_test.dart`
- Test: `test/e2e/sync_star_e2e_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch7"sync* 生成器"：INIT_SYNC_STAR 创建惰性 SyncStarIterable\<T\>，不立即执行函数体。SyncStarIterator.moveNext() 流程：首次调用创建 DarticFrame → 同步执行帧（drive()）→ YIELD 时 current = value + 深保存 + 返回 true → RETURN 时 isDone = true + 返回 false。帧与栈的交互：moveNext 期间帧占用全局栈，YIELD 时深保存释放栈空间。Ch7"YIELD_STAR"在 sync* 中的行为（delegateIterator）
2. **写测试** —
   - **runtime 测试**：
     - SyncStarIterable 创建后不执行函数体（惰性）
     - moveNext() 首次调用创建帧并执行到第一个 YIELD，返回 true
     - current 返回 YIELD 产出的值
     - 连续 moveNext() 恢复帧执行到下一个 YIELD
     - 函数体结束时 moveNext() 返回 false，isDone = true
     - 生成器抛出异常时 moveNext() 向调用者传播异常
     - for-in 循环正确消费 sync* 生成器
   - **E2E 测试**：
     - `Iterable<int> count(int n) sync* { for (var i = 0; i < n; i++) yield i; }`
     - `Iterable<int> fibonacci() sync* { int a = 0, b = 1; while (true) { yield a; var t = a; a = b; b = t + b; } }`（无限生成器，取前 N 个）
     - sync* 中包含 try/finally：`sync* { try { yield 1; yield 2; } finally { /* cleanup */ } }`
     - 嵌套 sync*：外层 sync* 调用内层 sync*
3. **实现** —
   - **SyncStarIterable\<T\>**：持有 DarticFuncProto 引用 + 创建参数（upvalues, type args 等）。实现 Iterable\<T\> 接口，iterator getter 返回 SyncStarIterator
   - **SyncStarIterator\<T\>**：字段——frame(DarticFrame?), current(T?), delegateIterator(Iterator\<T\>?), isDone(bool)。moveNext() 按 Ch7 设计的 4 步流程实现。需要调用解释器的 drive() 方法同步执行帧
   - **解释器**：
     - `case Op.initSyncStar`：从常量池 refs[Bx] 取 emittedValueType → 创建 SyncStarIterable → refStack[rBase + A] = iterable → 函数同步返回（不压入 _runQueue）
     - YIELD 在 sync* 上下文：iterator.current = refStack[A] → 设置 frame.pc = Bx（恢复点）→ _suspendFrame(frame) → 从 drive() 返回 true
     - 增加 `drive(DarticFrame)` 公开方法供 SyncStarIterator 调用——分配栈空间、执行帧直到 YIELD/RETURN/异常
   - **编译器**：
     - sync* 函数：emit INIT_SYNC_STAR A, Bx → 编译函数体 → YIELD 编译为 YieldStatement visitor → 函数末尾 emit RETURN_NULL（触发 isDone）
     - `_compileYieldStatement`：编译 yield 表达式到 ref 寄存器 A → emit YIELD A, Bx（Bx = 恢复点 PC）
     - 标记当前函数 asyncMarker 以区分 YIELD 在 sync*/async* 中的分发
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/sync_star_test.dart && fvm dart test test/e2e/sync_star_e2e_test.dart`

---

### Task 6.1.4: async* 生成器 — INIT_ASYNC_STAR + YIELD

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`（INIT_ASYNC_STAR + YIELD async* 分支 + StreamController 生命周期）
- Modify: `lib/src/compiler/compiler.dart`（async* 函数编译）
- Test: `test/runtime/async_star_test.dart`
- Test: `test/e2e/async_star_e2e_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch7"async* 生成器"：INIT_ASYNC_STAR 创建 StreamController\<T\>，注册 onListen/onPause/onResume/onCancel 四个控制回调。YIELD 语义：controller.add(value) → 检查 streamPaused → 若暂停则挂起（isSuspendedAtYield=true）→ 否则继续。正常完成：controller.close()。未捕获异常：controller.addError() → controller.close()。取消流程：onCancel 设置 cancelled=true → 恢复帧 → 执行 finally → controller.close()。async* 中的 await：行为与普通 async 一致
2. **写测试** —
   - **runtime 测试**：
     - INIT_ASYNC_STAR 创建 StreamController，refStack[A] = controller.stream
     - YIELD 通过 controller.add 发送值
     - Stream.listen 正确接收值
     - Stream pause/resume 控制生成器暂停/恢复
     - Stream cancel 触发生成器 finally 执行
     - 生成器正常结束时 stream closed
     - 生成器异常时 stream 收到 error 事件
   - **E2E 测试**：
     - `Stream<int> count(int n) async* { for (var i = 0; i < n; i++) yield i; }`
     - async* 中使用 await：`async* { yield await Future.value(42); }`
     - async* 中使用 try/finally：`async* { try { yield 1; yield 2; } finally { /* cleanup */ } }`
     - Stream.toList() 收集全部值
3. **实现** —
   - **解释器**：
     - `case Op.initAsyncStar`：从常量池 refs[Bx] 取 emittedValueType → 创建 StreamController\<T\>() → 注册 4 个回调（onListen: 帧加入 _runQueue；onPause: streamPaused=true；onResume: streamPaused=false + 若 isSuspendedAtYield 则重新入队；onCancel: cancelled=true + 若挂起则恢复）→ refStack[rBase + A] = controller.stream → break innerLoop（不立即执行，等 onListen）
     - YIELD 在 async* 上下文：controller.add(refStack[rBase + A]) → 检查 cancelled → 检查 streamPaused → 若暂停则 isSuspendedAtYield=true + _suspendFrame + break innerLoop → 否则继续
     - async* 函数正常完成（RETURN_NULL 或 fall through）：检测帧类型 → controller.close() → _runQueue.removeFirst
     - async* 函数未捕获异常：controller.addError(error, stackTrace) → controller.close() → _runQueue.removeFirst
   - **编译器**：
     - async* 函数：emit INIT_ASYNC_STAR A, Bx → 编译函数体 → YIELD 同 sync* 但标记为 async* 上下文 → 函数末尾 safety net 为 RETURN_NULL（触发 stream close）
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/async_star_test.dart && fvm dart test test/e2e/async_star_e2e_test.dart`

---

### Task 6.1.5: YIELD_STAR + await for + 异步 skip list 清理

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`（YIELD_STAR + AWAIT_STREAM_NEXT）
- Modify: `lib/src/runtime/sync_star.dart`（delegateIterator 支持）
- Modify: `lib/src/compiler/compiler_statements.dart`（yield* + ForInStatement 异步分支）
- Modify: `tool/co19_runner.dart`（移除 _knownAsyncRegressions skip list）
- Test: `test/e2e/yield_star_e2e_test.dart`
- Test: `test/e2e/await_for_e2e_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch7"YIELD_STAR 详细语义"：sync* 中 yield* → 获取 .iterator → 存入 delegateIterator → moveNext 优先从委托 iterator 取值。async* 中 yield* → 订阅 Stream → 转发 onData/onError 到当前 controller → onDone 时恢复帧。Ch7"await for 编译"：编译为 stream.listen + AWAIT_STREAM_NEXT 序列，使用 SENTINEL_DONE 哨兵标记 stream 结束。Ch7"AWAIT_STREAM_NEXT"：挂起等待下一个 stream 事件，onData 恢复值写入寄存器，onDone 恢复 SENTINEL_DONE
2. **写测试** —
   - **yield* E2E 测试**：
     - sync* 中 yield*：`Iterable<int> f() sync* { yield* [1, 2, 3]; yield 4; }`
     - async* 中 yield*：`Stream<int> f() async* { yield* Stream.fromIterable([1, 2, 3]); yield 4; }`
     - 嵌套 yield*：外层 sync* yield* 内层 sync*
   - **await for E2E 测试**：
     - `Future<int> sum(Stream<int> s) async { int total = 0; await for (var x in s) { total += x; } return total; }`
     - await for + break 提前退出
     - await for + try/catch 异常处理
     - await for 空 stream
   - **Skip list 清理测试**：
     - 之前 skip 的 10 个 async/generator 测试现在能通过
3. **实现** —
   - **解释器 YIELD_STAR**：
     - sync* 上下文：获取 refStack[A].iterator → 存入 SyncStarIterator.delegateIterator → moveNext 优先从委托 iterator 取值 → 委托耗尽时恢复帧从 Bx 继续
     - async* 上下文：获取 refStack[A] 作为 Stream → stream.listen(onData: controller.add, onError: controller.addError, onDone: 恢复帧)→ 帧挂起等待 onDone
   - **解释器 AWAIT_STREAM_NEXT**：挂起帧 → 等待 stream 事件 → onData: resumeValue=value + scheduleMicrotask 恢复 → onDone: resumeValue=SENTINEL_DONE + scheduleMicrotask 恢复 → onError: resumeException=error + scheduleMicrotask 恢复 → 恢复后 refStack[A] = resumeValue
   - **常量池 SENTINEL_DONE**：在常量池 refs 分区预分配唯一哨兵对象
   - **编译器**：
     - yield*：检查 Kernel YieldStatement.isYieldStar → emit YIELD_STAR A, Bx
     - await for：编译 ForInStatement（isAsync=true）→ 编译 stream 表达式 → emit stream.listen 的 CALL_HOST → 循环体内 emit AWAIT_STREAM_NEXT → EQ_REF 与 SENTINEL_DONE 比较 → 条件退出循环
   - **Skip list 清理**：从 co19_runner.dart 移除 `_knownAsyncRegressions` 列表中的 10 个测试
4. **运行** — `fvm dart analyze && fvm dart test`（全量测试确保无回归）

---

## Commit

```
feat(async): add async/await, sync*/async* generators with frame-as-continuation
```

**提交文件：** `lib/src/runtime/frame.dart` + `lib/src/runtime/interpreter.dart` + `lib/src/runtime/sync_star.dart`（新文件）+ `lib/src/compiler/compiler.dart` + `lib/src/compiler/compiler_expressions.dart` + `lib/src/compiler/compiler_statements.dart` + `lib/src/compiler/compiler_closures.dart` + `tool/co19_runner.dart` + 全部新测试

## 核心发现

- **深保存 vs 浅保存**：所有异步挂起均使用深保存（快照值栈+引用栈区间到帧对象），浅保存仅保存 PC/基址不复制数据。深保存保证恢复后帧在栈顶，避免与活跃帧重叠
- **callerAsyncFrame 模式**：async 函数需要保存调用者的异步帧引用，以便在首次 AWAIT 或 ASYNC_RETURN 时恢复调用者上下文。通过 `frame.callerAsyncFrame` 字段和 `futureReturned` 标志实现三路返回
- **CFE 解语法糖**：`await for` 被 CFE 解糖为 `_StreamIterator` 模式（moveNext/cancel/current），无需 AWAIT_STREAM_NEXT 操作码。创建了 StreamIteratorBindings 宿主绑定替代
- **Completer\<T\> 简化**：INIT_ASYNC 当前创建 `Completer<Object?>()` 而非 `Completer<T>()`，TypeTemplate Bx 已编码但运行时暂未使用。待泛型实化完善后可启用
- **sync\* 驱动模型**：SyncStarIterator 通过 `driveSyncStar()` 公开方法同步驱动解释器，使用解释器字段（`_activeSyncStarIterator`、`_syncStarStatus`）在 YIELD 与 moveNext 间传递状态
- **async\* StreamController 四回调**：onListen 启动函数体、onPause 设标志、onResume 恢复已暂停帧、onCancel 标记取消并恢复帧执行 finally
- **跨帧异步异常传播受限**：callee async 函数 throw → `completeError` → awaiter 的 `catch` 无法命中 handler，因为编译器生成的异常表 `endPC` 未覆盖 AWAIT 恢复 PC。运行时 `_resumeFrame` 已添加 try-catch 兜底，但 awaiter 端 catch 匹配需编译器修复。详见 `docs/design/07-async.md` "已知局限"

## Batch 完成检查

- [x] 6.1.1 DarticFrame 异步字段 + 挂起/恢复机制
- [x] 6.1.2 async/await — INIT_ASYNC + AWAIT + ASYNC_RETURN + ASYNC_THROW
- [x] 6.1.3 sync* 生成器 — INIT_SYNC_STAR + YIELD
- [x] 6.1.4 async* 生成器 — INIT_ASYNC_STAR + YIELD
- [x] 6.1.5 YIELD_STAR + await for + 异步 skip list 清理
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test` 全部通过（2425/2425）
- [x] 之前 skip 的 10 个 async 测试恢复通过（skip list 已从 co19_runner.dart 移除）
- [x] commit 已提交（ec670d1）
- [x] overview.md 已更新
- [x] code review 已完成（f7fae15 — 修复 I-1~I-4 + S-1/S-2/S-8 + 2 新测试）
