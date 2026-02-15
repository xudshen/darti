# POC-5: Flat Call Stack + Fuel 调度 + Async 挂起

> 方案来源: `docs/plans/2026-02-16-poc-async-fuel.md`

## 目标

验证 flat call stack（迭代分发）、fuel-based 调度、async 帧挂起/恢复三个核心机制的可行性。

## 任务

### Task 20: CallStack + 迭代分发循环

**依赖:** Task 17
**产出文件:**
- `lib/src/runtime/call_stack.dart`
- `lib/src/runtime/dispatch_loop.dart`（重写）
- `test/runtime/call_stack_test.dart`
- `test/runtime/dispatch_loop_test.dart`（更新）

**TDD 步骤:**
- [x] 写失败测试 `call_stack_test.dart`
- [x] 运行验证测试失败
- [x] 实现 `call_stack.dart`
- [x] 运行 `call_stack_test.dart` 验证通过
- [x] 重写 `dispatch_loop.dart` 为迭代版本
- [x] 运行全部现有测试验证不破坏
- [x] **Commit** `dc8c6ae`（flat call stack + 迭代分发）

### Task 21: Fuel-based 调度

**依赖:** Task 20
**产出文件:**
- `lib/src/runtime/dispatch_loop.dart`（修改）
- `test/runtime/dispatch_loop_test.dart`（合并）

**TDD 步骤:**
- [x] 写失败测试（合入 `dispatch_loop_test.dart`）
- [x] 运行验证测试失败
- [x] 修改 `dispatch_loop.dart` 添加 fuel + async API
- [x] 更新现有测试适配 async API
- [x] 运行全部测试验证通过
- [x] **Commit** `949ab3c`（fuel-based 调度）

### Task 22: AWAIT 指令 + 帧挂起/恢复

**依赖:** Task 21
**产出文件:**
- `lib/src/runtime/opcodes.dart`（修改）
- `lib/src/runtime/types.dart`（修改）
- `lib/src/runtime/dispatch_loop.dart`（修改）
- `test/runtime/dispatch_loop_test.dart`（合并）

**TDD 步骤:**
- [x] 写失败测试（合入 `dispatch_loop_test.dart`）
- [x] 运行验证测试失败
- [x] 在 `opcodes.dart` 添加 INIT_ASYNC / AWAIT / ASYNC_RETURN
- [x] 在 `types.dart` 添加 `InterpreterFrame`
- [x] 在 `dispatch_loop.dart` 实现 AWAIT 分支
- [x] 运行 `dispatch_loop_test.dart` 验证通过
- [x] 运行全部测试确认不破坏
- [x] **Commit** `fce24bf`（AWAIT 挂起/恢复）

### Task 23: 更新导出 + 文档 + 全部测试

**依赖:** Task 20, 21, 22
**产出文件:**
- `lib/darti.dart`（修改）
- `docs/tasks/poc/poc-5-async.md`（更新）
- `docs/tasks/overview.md`（更新）

**TDD 步骤:**
- [x] 更新 `lib/darti.dart` 导出
- [x] 运行 `fvm dart analyze` 确认 0 issues
- [x] 运行全部测试确认通过
- [x] 更新进度和关键发现
- [ ] **Commit**（POC-5 完成）

## 关键发现

### 1. 闭包捕获替代 InterpreterFrame（POC 简化有效）

设计文档要求创建 `InterpreterFrame` 对象保存挂起帧状态。POC 发现 Dart 闭包自动捕获局部变量，`drive()` 函数内的 `curFuncId`、`pc`、`vBase`、`rBase` 等变量在 fuel 耗尽或 AWAIT 挂起时自动保留。`.then()` 回调恢复时直接修改这些变量并调 `drive()` 即可。

**正式版决策：** 单帧挂起可用闭包方案。多帧并发调度（`_runQueue` 多个帧同时 pending）时需要 InterpreterFrame 对象，因为每个帧需要独立的状态副本。

### 2. Completer.complete(Future) 自动链式解析

`Completer.complete(asyncCompleter.future)` 不会产生 `Future<Future<T>>`。Dart 的 `Completer.complete()` 会自动等待传入的 Future resolve 后再 resolve 自身。这使得 `INIT_ASYNC` 的实现非常简洁 — 只需在 `executeFunc` 的 completer 上 complete 异步函数的 future，调用者透明拿到最终结果。

### 3. CallStack 需要 resultReg（第 6 槽位）

设计文档规定 5 个槽位（funcId, returnPC, savedFP, savedVSP, savedRSP），但迭代分发中 RETURN 指令需要知道调用者期望返回值存放的寄存器。增加 `resultReg` 为第 6 个槽位，设计文档已同步更新（savedFP 可与 resultReg 合并为 5 个槽位的方案待定）。

### 4. Fuel 闭包状态恢复模式

`drive()` 作为闭包捕获帧状态变量，fuel 耗尽时 `Timer.run(drive)` 重入。闭包恢复时所有局部变量保持上次中断的值。这等效于协程（coroutine），但完全使用 Dart 标准语法实现，无需 async*/yield。

### 5. AWAIT 快速路径

`await` 非 Future 值（如 `await 42`）直接 fall-through 到下一条指令，不做任何挂起。已完成的 Future（如 `Future.value(99)`）仍需走挂起路径，因为 Dart 的 Future.then() 回调始终异步调度（microtask），即使 Future 已完成。
