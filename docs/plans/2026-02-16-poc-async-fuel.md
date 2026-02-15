# POC-5: Flat Call Stack + Fuel 调度 + Async 挂起

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 验证 flat call stack（迭代分发）、fuel-based 调度、async 帧挂起/恢复三个核心机制的可行性。

**Architecture:** 将 POC-4 的递归 `executeFunc()` 重构为迭代分发循环 + `CallStack`（Uint32List 帧元数据），加入 fuel 预算控制和 `Timer.run` 让出，最后实现 AWAIT 指令的帧挂起与 Future 回调恢复。

**Tech Stack:** Dart (fvm dart), package:test, dart:async (Timer, Completer, Future)

---

## 背景

### 当前实现（POC-4）

`DartiRuntime.executeFunc()` 通过 **Dart 递归调用** 处理 `CALL_STATIC`：

```dart
case OpCode.callStatic:
  final result = executeFunc(module, bx, args, newBaseV, newBaseR);
  _rs.slots[rBase + a] = result;
```

问题：
1. **不支持 async 挂起** — Dart 递归栈无法暂停/恢复
2. **无法 fuel 让出** — 深层递归中无法 break 到外层
3. **调用深度受限于 Dart 栈** — 无法精确控制

### 目标架构（设计文档 Chapter 2）

```
_driveInterpreter() {
  int fuel = _fuelBudget;
  while (fuel > 0 && _runQueue.isNotEmpty) {
    final frame = _runQueue.first;
    innerLoop:
    while (fuel-- > 0) {
      switch (op) {
        case CALL: _pushFrame(newFrame); break innerLoop;
        case AWAIT: _suspend(frame); break innerLoop;
        case RETURN: _popFrame(); break innerLoop;
      }
    }
  }
  if (_runQueue.isNotEmpty) Timer.run(_driveInterpreter);
}
```

## 任务

### Task 20: CallStack + 迭代分发循环

**依赖:** Task 17 (handwritten_bytecode_test)
**产出文件:**
- `lib/src/runtime/call_stack.dart`（新建）
- `lib/src/runtime/dispatch_loop.dart`（重写为迭代版）
- `test/runtime/call_stack_test.dart`（新建）
- `test/runtime/dispatch_loop_test.dart`（更新）
- `test/e2e/handwritten_bytecode_test.dart`（验证不破坏）

**设计要点:**

CallStack 用 `Uint32List` 存储帧元数据，每帧 5 个槽位：
- `funcId` — 当前函数 ID（用于查找 FuncProto）
- `returnPC` — 调用者的 PC
- `savedFP` — 调用者的帧指针
- `savedVSP` — 调用者的值栈基址
- `savedRSP` — 调用者的引用栈基址

分发循环改为 `while (true)` + `break innerLoop` 模式。`CALL_STATIC` 不再递归，而是 push 新帧后 `break innerLoop`，外层循环从新帧继续。`RETURN_*` pop 帧后 `break innerLoop`，恢复调用者帧继续。

**TDD 步骤:**

- [ ] 写失败测试 `call_stack_test.dart`：测试 push/pop 帧、栈指针保存/恢复、溢出检测
- [ ] 运行验证测试失败
- [ ] 实现 `call_stack.dart`
- [ ] 运行 `call_stack_test.dart` 验证通过
- [ ] 重写 `dispatch_loop.dart` 为迭代版本（同步，暂不加 fuel）
- [ ] 运行全部现有测试验证不破坏（dispatch_loop_test + handwritten_bytecode_test + compiler_e2e_test）
- [ ] **Commit**（flat call stack + 迭代分发）

### Task 21: Fuel-based 调度

**依赖:** Task 20
**产出文件:**
- `lib/src/runtime/dispatch_loop.dart`（修改，添加 fuel + async API）
- `test/runtime/dispatch_loop_test.dart`（合并）

**设计要点:**

在 Task 20 的迭代循环外层加 fuel 计数。`execute()` 返回 `Future<Object?>` 而非 `Object?`。当 fuel 耗尽时 `Timer.run` 调度下一轮，通过 `Completer` 传递最终结果。

POC 简化：不实现 `_runQueue`（多帧并发调度），仅验证 fuel 耗尽 → yield → 恢复的机制。

**TDD 步骤:**

- [ ] 写失败测试（合入 `dispatch_loop_test.dart`）：验证 fuel 耗尽后通过 Timer.run 恢复执行并得到正确结果
- [ ] 运行验证测试失败
- [ ] 修改 `dispatch_loop.dart`：`execute()` → `Future<Object?>`，加 fuel 计数 + `Timer.run`
- [ ] 更新现有测试适配 async API（dispatch_loop_test、handwritten_bytecode_test、compiler_e2e_test 加 `await`）
- [ ] 运行全部测试验证通过
- [ ] **Commit**（fuel-based 调度）

### Task 22: AWAIT 指令 + 帧挂起/恢复

**依赖:** Task 21
**产出文件:**
- `lib/src/runtime/opcodes.dart`（修改，添加 INIT_ASYNC / AWAIT / ASYNC_RETURN）
- `lib/src/runtime/types.dart`（修改，添加 InterpreterFrame）
- `lib/src/runtime/dispatch_loop.dart`（修改，实现 AWAIT 处理）
- `test/runtime/dispatch_loop_test.dart`（合并）

**设计要点:**

POC 简化版 async 流程：
1. `INIT_ASYNC` — 创建 Completer，将 future 存入 ref 寄存器
2. `AWAIT A, Bx` — 检查 ref[A]：
   - 若已完成/非 Future → 快速路径，将结果存入 ref[A]，PC = Bx 继续
   - 若 pending Future → 保存帧状态到 `InterpreterFrame` 对象，注册 `.then()` 回调，`break innerLoop`
3. `ASYNC_RETURN A` — `completer.complete(ref[A])`，帧结束

`InterpreterFrame` 持有挂起帧的所有状态：funcId、pc、vsp、rsp 以及值栈/引用栈的快照（POC 简化：直接保存基址 + 范围，恢复时重新设为活跃帧）。

**TDD 步骤:**

- [ ] 写失败测试（合入 `dispatch_loop_test.dart`）：手写字节码测试 async 函数 await 一个 delayed Future 后返回结果
- [ ] 运行验证测试失败
- [ ] 在 `opcodes.dart` 添加 INIT_ASYNC / AWAIT / ASYNC_RETURN 常量
- [ ] 在 `types.dart` 添加 `InterpreterFrame` 类
- [ ] 在 `dispatch_loop.dart` 实现 AWAIT 分支
- [ ] 运行 `dispatch_loop_test.dart` 验证通过
- [ ] 运行全部测试确认不破坏
- [ ] **Commit**（AWAIT 挂起/恢复）

### Task 23: 更新导出 + 文档 + 全部测试

**依赖:** Task 20, 21, 22
**产出文件:**
- `lib/darti.dart`（修改，添加 call_stack 导出）
- `docs/tasks/poc/poc-5-async.md`（更新进度）
- `docs/tasks/overview.md`（添加 POC-5 条目）

**TDD 步骤:**

- [ ] 更新 `lib/darti.dart` 导出
- [ ] 运行 `fvm dart analyze` 确认 0 issues
- [ ] 运行全部测试确认通过
- [ ] 更新 `docs/tasks/poc/poc-5-async.md` 记录关键发现
- [ ] 更新 `docs/tasks/overview.md` 添加 POC-5
- [ ] **Commit**（POC-5 完成）

## 风险与简化

| 设计文档特性 | POC 范围 | 说明 |
|-------------|---------|------|
| `_runQueue`（多帧并发） | ❌ 不实现 | POC 仅验证单帧挂起/恢复，多帧调度是工程化问题 |
| `scheduleMicrotask`（await 恢复用 microtask） | ❌ 简化为 `Timer.run` | 优先级区分是优化项，不影响正确性 |
| `InterpreterFrame` 完整字段 | ⚠️ 最小子集 | 仅含 funcId/pc/vBase/rBase，不含 IC 表等 |
| 栈快照/隔离 | ⚠️ 简化 | 挂起帧的栈数据留在原位，不做拷贝（POC 假设无并发帧） |
| `maxCallDepth` 检查 | ✅ 实现 | CallStack.push 中检查 |
