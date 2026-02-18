# Batch 2.3: 语句与控制流

## 概览

实现完整的控制流语句编译：if/else、for/while/do-while 循环、switch/case、break/continue/label、try/catch/finally 异常处理、assert 断言。解释器新增 THROW/RETHROW 异常分发和 ASSERT 指令。异常处理是 Phase 2 中最复杂的子系统，需要编译器生成异常处理器表 + 解释器实现处理器匹配与栈展开。

**设计参考：** `docs/design/05-compiler.md`（控制流编译、语句编译补充）、`docs/design/03-execution-engine.md`（异常分发、异常处理器表、附录参考实现）

**依赖：** Batch 2.1（全局变量——部分测试需要跨函数共享状态）, Batch 2.2（比较/逻辑运算——用于条件判断）

---

### Task 2.3.1: if/else 语句

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/compiler/if_else_test.dart`
- Test: `test/e2e/control_flow_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"控制流编译"表中 if/else 模式：编译条件 → JUMP_IF_FALSE 到 else → 编译 then → JUMP 到 end → 回填 else → 编译 else → 回填 end
2. **写测试** — 验证：
   - 单 if（无 else）：条件为 true 执行 body，false 跳过
   - if/else：正确分支选择
   - 嵌套 if/else：多层分支正确
   - if 内的变量赋值在 if body 作用域内可见（Block 作用域验证）
   - **端到端测试**（`test/e2e/control_flow_test.dart`）：编译含 if/else 的 Dart 函数 → 执行 → 结果正确（如 `int abs(int x) { if (x < 0) return -x; return x; }`，或 `int max(int a, int b) { if (a > b) return a; else return b; }`）
3. **实现** — 在 `_compileStatement` 添加 `IfStatement` 分支。引入 BytecodeEmitter 的跳转回填辅助模式：`emitPlaceholder()` 预留跳转指令位置 → `patchJump(pc, instruction)` 回填实际跳转目标（已有此 API，Phase 1 用于 arg patching）。需要计算跳转偏移：`目标PC - 当前PC`（excess-K 编码）
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/if_else_test.dart test/e2e/control_flow_test.dart`

---

### Task 2.3.2: for / while / do-while 循环

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/compiler/loop_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"控制流编译"表中 for/while/do-while 的向后跳转模式。注意 for 循环的作用域：循环变量在 for 的 Block 作用域中，循环结束后不可见
2. **写测试** — 验证：
   - `while(condition) { body }` → 循环正确执行指定次数
   - `for(var i = 0; i < n; i++) { body }` → 初始化 + 条件 + 更新 + 循环体正确协作
   - `do { body } while(condition)` → 至少执行一次
   - 累加器模式：`int sum = 0; for(var i = 1; i <= 10; i++) sum += i;` → 结果 55
   - 嵌套循环
   - 循环变量作用域：循环结束后循环变量不可见
   - 空循环体
   - 端到端：循环计算（阶乘、斐波那契等）结果正确
3. **实现** —
   - **WhileStatement**：记录循环起点 PC → 编译条件 → JUMP_IF_FALSE 到出口（预留回填）→ 编译体 → JUMP 回起点 → 回填出口
   - **ForStatement**：进入作用域 → 编译初始化器（VariableDeclaration 列表）→ 记录循环起点 → 编译条件 → JUMP_IF_FALSE 到出口 → 编译体 → 编译更新表达式（ExpressionStatement 列表）→ JUMP 回起点 → 回填出口 → 退出作用域
   - **DoStatement**：记录起点 → 编译体 → 编译条件 → JUMP_IF_TRUE 回起点
   - 注意：Kernel ForStatement 的 condition 可能为 null（无限循环 `for(;;)`），此时不生成条件跳转
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/loop_test.dart`

---

### Task 2.3.3: switch/case 语句（基础）

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/compiler/switch_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"控制流编译"表中 switch 编译策略。Phase 2 统一编译为 if-else 链（密集整数跳转表和二分查找优化延迟到后续 Phase）。Dart switch 的 fall-through 规则：非空 case 不允许 fall-through（编译器/CFE 已检查），空 case body 可以 fall-through 到下一个
2. **写测试** — 验证：
   - 基础 int switch：匹配正确 case 并执行
   - default case：无匹配时执行 default
   - 多个 case 值共享一个 body（空 case fall-through 到下一个 case）
   - switch 无匹配且无 default：跳过整个 switch
   - switch 中的 block 作用域
   - 端到端执行正确
3. **实现** — SwitchStatement 编译为顺序比较链：编译 switch 表达式到临时寄存器 → 对每个 SwitchCase 的每个 expression 生成比较（EQ_INT 或 EQ_REF）+ JUMP_IF_FALSE 到下一个 case → 编译 case body → JUMP 到 switch 末尾。Kernel 中 SwitchStatement 的结构：`expression` + `List<SwitchCase>`，每个 SwitchCase 有 `expressions`（匹配值列表，default 为空）和 `body`
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/switch_test.dart`

---

### Task 2.3.4: break / continue / label

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/compiler/break_continue_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"控制流编译"表中 labeled break/continue 策略：编译器维护标签→跳转目标映射表，BreakStatement 发射 JUMP 并记录待回填，标签语句结束时批量回填。Ch5"语句编译补充"中 ContinueSwitchStatement 说明
2. **写测试** — 验证：
   - 循环中 break：提前退出循环
   - 循环中 continue：跳过当前迭代
   - 嵌套循环中 break/continue：只影响最内层循环
   - labeled break：跳出外层循环（`outer: for(...) { for(...) { break outer; } }`）
   - switch 中 break：退出 switch 语句（需要在 2.3.3 的 switch 实现中预留 break 支持）
   - continue 到 switch 的下一个 case（ContinueSwitchStatement）
3. **实现** — 在编译器中维护两个跳转目标上下文栈：
   - **breakTargets**：每个循环/switch/labeled 语句 push 一个待回填列表，break 时 emit JUMP 并记录 PC
   - **continueTargets**：每个循环 push 更新步骤的 PC 位置，continue 时 emit JUMP 到该位置
   - **LabeledStatement**：注册标签 → 编译 body → 回填所有 BreakStatement 的 JUMP
   - **BreakStatement**：查找目标标签或当前循环/switch 的 break 列表，emit JUMP 占位
   - **ContinueSwitchStatement**：emit JUMP 到目标 SwitchCase 的起始 PC
   - 注意：Kernel 中 break 使用 `LabeledStatement` + `BreakStatement`，循环内部的 break/continue 会被 CFE 包装在 LabeledStatement 中
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/break_continue_test.dart`

---

### Task 2.3.5: try / catch / finally + THROW / RETHROW

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`（异常分发逻辑 + THROW/RETHROW opcodes）
- Modify: `lib/src/compiler/compiler.dart`（异常处理表生成）
- Modify: `lib/src/compiler/bytecode_emitter.dart`（异常处理表构建辅助）
- Test: `test/runtime/exception_dispatch_test.dart`
- Test: `test/compiler/try_catch_test.dart`
- Test: `test/e2e/exception_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch3"异常分发"全节（处理器匹配算法、栈展开、finally 处理、边界情况）。Ch5"控制流编译"中 try/catch 和 try/finally 的编译策略。Ch3 附录"异常分发实现"参考代码。Ch2 ExceptionHandler 8 字段结构（Phase 1.5 已定义数据结构但未使用）
2. **写解释器异常分发测试** — 手工构造包含异常处理表的字节码模块验证：
   - THROW 触发异常 → 匹配 catch-all handler（catchType=-1）→ 跳转到 handlerPC
   - 嵌套 try：内层无匹配 → 外层匹配
   - catch 变量绑定：exception 和 stackTrace 正确写入指定寄存器（exceptionReg/stackTraceReg）
   - 栈展开：值栈/引用栈正确回退到 handler 记录的深度（valStackDP/refStackDP）
   - 引用栈清理：被跳过的引用槽位置 null（GC 安全）
   - 无匹配 handler：异常传播到顶层
   - RETHROW：重新抛出异常并保留原始 stackTrace
3. **写编译器测试** — 验证：
   - `try { throw 'error'; } catch (e) { return e; }` → 正确生成异常处理表 + THROW 指令 + catch body
   - `try { ... } finally { ... }` → finally 在正常和异常路径均执行
   - 类型化 catch：`on TypeError catch (e)` → catchType 指向类型常量池索引
   - 嵌套 try-catch 的异常处理表排序（内层范围更小排在前面）
   - **端到端测试**：编译含 try/catch/throw 的 Dart 函数 → 执行 → 验证异常捕获和结果正确
4. **实现** —
   - **解释器**：添加 THROW（0xA4）和 RETHROW（0xA5）case。实现 `_dispatchException` 方法——遍历当前帧的 exceptionTable 查找匹配 handler（按 PC 范围 + catchType 匹配），匹配成功执行栈展开（回退 sp、引用栈置 null、写入 catch 变量、跳转 handlerPC），无匹配则弹帧继续搜索调用者帧。编译 Throw 表达式（Throw 在 Dart/Kernel 中是表达式，类型为 Never）
   - **编译器**：TryCatch 编译——记录 startPC → 编译 try body → 记录 endPC → 对每个 catch 子句：分配 exception/stackTrace 寄存器 → 记录 handlerPC → 编译 catch body → JUMP 到 try 末尾 → 组装 ExceptionHandler 条目。TryFinally 编译——finally 块在正常路径和异常路径各编译一份（正常路径尾部直接 fall-through，异常路径以 RETHROW 结束）
   - **BytecodeEmitter**：添加 exceptionHandlers 列表和构建 API
5. **运行** — `fvm dart analyze && fvm dart test test/runtime/exception_dispatch_test.dart test/compiler/try_catch_test.dart test/e2e/exception_test.dart`

> **关键风险**：异常分发是 Phase 2 最复杂的子系统。引用栈清理逻辑（`rs.clearRange(refStackDP, currentRSP)`）遗漏会导致内存泄漏但不会立即报错。建议实现后专门编写 GC 安全性验证测试。

---

### Task 2.3.6: assert 语句

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`（ASSERT opcode）
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/compiler/assert_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"控制流编译"表中 assert 策略：`--no-enable-asserts` 时完全不生成代码，否则编译为条件检查 + ASSERT 指令。Ch1 ASSERT（0xA6）操作码语义
2. **写测试** — 验证：
   - assert 条件为 true → 正常 fall-through
   - assert 条件为 false → 抛 AssertionError（通过异常分发机制）
   - assert 带消息 `assert(condition, 'message')` → AssertionError 携带消息
   - assert 在 release 模式（asserts disabled）下不生成任何指令
3. **实现** — 解释器 ASSERT case：条件为 false 时创建 AssertionError 并进入 `_dispatchException`（复用 2.3.5 的异常分发）。编译器 AssertStatement 编译：编译条件 → JUMP_IF_TRUE 跳过 → 编译消息（如有，加载到引用栈）→ 发射 ASSERT 指令 → 回填跳转。增加 asserts 开关配置（DarticCompiler 构造函数参数或全局配置）
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/assert_test.dart`

---

## Commit

```
feat: support control flow statements and exception handling
```

**提交文件：** 修改的 interpreter.dart + compiler.dart + bytecode_emitter.dart + 全部新测试

## 核心发现

- **Kernel LabeledStatement 统一表示 break/continue**：CFE 将所有 break 和 continue 编译为 `LabeledStatement` + `BreakStatement` 对。while-loop 的 continue 不需要单独的 continue 目标追踪——CFE 会将 continue 转换为 break 到一个包裹循环体的 LabeledStatement。这大大简化了编译器实现。
- **异常处理表结构**：每个 `ExceptionHandler` 记录 `(startPC, endPC, handlerPC, catchType, valStackDP, refStackDP, exceptionReg, stackTraceReg)`。try body 的 PC 范围为 `[startPC, endPC)`，异常发生时搜索匹配处理器。Phase 2 仅支持 catch-all（`catchType=-1`）。
- **finally 双路径编译**：try-finally 编译为两份 finalizer 代码——正常路径和异常路径。异常路径以 RETHROW 结尾继续传播异常。
- **switch 编译为 if-else 链**：Phase 2 使用顺序比较链（EQ_INT/EQ_REF + JUMP_IF_TRUE），每个 case 表达式逐一比较。CFE 将 switch 包裹在 LabeledStatement 中以支持 break。
- **ASSERT 使用 ABx 格式**：条件寄存器在 A，消息常量池索引在 Bx（0xFFFF 表示无消息）。ASSERT 失败时复用 THROW 的异常分发逻辑，因此 `try { assert(false); } catch (e) { ... }` 能正确工作。
- **Entry function 寄存器偏移**：在 entry function 中直接使用临时表达式会占用低位寄存器，导致 return 值不在 v0。测试应使用 `int f() { ... } int main() => f();` 模式通过 RETURN_VAL/CALL_STATIC 传递返回值。

## Batch 完成检查

- [x] 2.3.1 if/else 语句
- [x] 2.3.2 for / while / do-while 循环
- [x] 2.3.3 switch/case 语句
- [x] 2.3.4 break / continue / label
- [x] 2.3.5 try / catch / finally + THROW / RETHROW
- [x] 2.3.6 assert 语句
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test` 全部通过（750 tests）
- [ ] commit 已提交
- [ ] overview.md 已更新
- [ ] code review 已完成
