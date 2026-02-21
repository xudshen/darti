# Batch 6.4: 沙箱 (Ch8)

## 概览

实现字节码加载时静态验证器（DarticVerifier）和运行时资源限制增强，构建保护宿主应用不因解释器代码错误而崩溃的安全防线。DarticVerifier 在字节码进入执行引擎前对模块逐项扫描（文件头、常量池、操作码、跳转目标、寄存器索引、异常处理器表等 12 项检查），验证通过后运行时零安全开销执行。运行时层面增强 fuel 计数（跨回合累计上限 maxTotalFuel）、执行超时（executionTimeout）和错误分类（DarticLoadError / DarticError / DarticInternalError）。

**设计参考：** `docs/design/08-sandbox.md`（威胁模型、DarticVerifier 验证项、资源限制、错误分类）、`docs/design/01-bytecode-isa.md`（操作码合法性、WIDE 规则、指令编码格式）、`docs/design/03-execution-engine.md`（fuel 计数、调用深度限制、错误恢复）

**依赖：** Phase 5 全部完成（可与 Batch 6.1/6.2 并行——沙箱验证不依赖异步或高级语言特性）

---

### Task 6.4.1: DarticVerifier 字节码验证器

**产出文件：**
- Create: `lib/src/sandbox/verifier.dart`
- Create: `lib/src/sandbox/load_error.dart`（DarticLoadError 错误类型）
- Test: `test/sandbox/verifier_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch8"DarticVerifier 验证项"表格（12 项）：
   - 文件头：magic=0x44415242、版本号 <= 当前版本、CRC32 校验和匹配
   - 常量池边界：refs/ints/doubles/names 各分区内部引用不越界
   - 操作码合法性：每条指令 opcode 在 ISA 范围内且非预留
   - 跳转目标：JUMP/JUMP_IF_*/JUMP_AX 偏移量计算后在 [0, codeLength) 内
   - 寄存器索引：A/B/C < 函数 regCount，按 ABC/ABx/AsBx/Ax 格式分别校验
   - 常量池索引：LOAD_CONST/LOAD_CONST_INT/LOAD_CONST_DBL 索引 < 对应分区长度
   - WIDE 前缀：不在末尾 2 位内、后跟指令兼容 WIDE、不可嵌套
   - 函数/方法引用：CALL_STATIC 的 Bx 在函数表范围内、CALL_HOST 的 Bx 在绑定表范围内、CALL_VIRTUAL 的 IC 索引在 IC 表范围内
   - 异常处理器表：[startPC, endPC) 合法非空、handlerPC 在代码范围内、valStackDP/refStackDP >= 0 且 <= regCount、exceptionReg 在引用栈寄存器范围内
   - 上值描述符：isLocal 引用索引 < 外层函数 regCount、非 isLocal 索引 < 外层上值数量
   - 类表：超类 ID 合法、方法引用指向合法函数、字段数量一致
   - 入口点：模块入口函数 ID 在函数表范围内

   Ch8 附录参考实现：DarticVerifier.verify() → _verifyHeader → _verifyConstantPool → per-function _verifyFunction → _verifyClassTable → _verifyEntryPoint。所有错误收集到 errors 列表后统一报告

2. **写测试** — 验证每项检查的正负面：
   - **文件头**：正确 magic+版本+CRC → 通过；错误 magic → DarticLoadError；错误 CRC → DarticLoadError；版本号过高 → DarticLoadError
   - **操作码**：合法操作码模块 → 通过；含非法操作码（0xFF reserved）→ 报错
   - **跳转目标**：跳转到合法 PC → 通过；跳转到 codeLength 之外 → 报错；跳转到负数 → 报错
   - **寄存器索引**：A < regCount → 通过；A >= regCount → 报错
   - **常量池索引**：索引在范围内 → 通过；索引越界 → 报错
   - **WIDE**：合法 WIDE 使用 → 通过；WIDE 在末尾 → 报错；WIDE 嵌套 → 报错
   - **函数引用**：CALL_STATIC Bx 在函数表范围内 → 通过；越界 → 报错
   - **异常处理器**：合法 handler → 通过；startPC >= endPC → 报错；handlerPC 越界 → 报错
   - **上值描述符**：合法索引 → 通过；isLocal 索引越界 → 报错
   - **类表**：合法继承链 → 通过；超类 ID 越界 → 报错
   - **入口点**：合法 funcId → 通过；越界 → 报错
   - **多错误收集**：含多个问题的模块 → errors 列表包含所有错误（不在第一个错误时中断）
   - **合法模块端到端**：编译器产出的正常 .darb → 验证通过

3. **实现** —
   - **DarticVerifier 类**：
     - `List<String> errors` 字段收集所有错误
     - `bool verify(DarticModule module)` 入口方法 → 依次调用各子验证器 → 返回 errors.isEmpty
     - `_verifyHeader(DarticModule)`：检查 magic、版本、CRC32
     - `_verifyConstantPool(ConstantPool)`：检查各分区内部引用不越界
     - `_verifyFunction(DarticFuncProto, DarticModule)`：遍历字节码检查操作码、寄存器、常量池索引、跳转目标、WIDE。遍历异常处理器表和上值描述符
     - `_verifyClassTable(DarticModule)`：检查超类 ID、方法引用、字段布局
     - `_verifyEntryPoint(DarticModule)`：检查入口函数 ID
   - **辅助方法**：`_isValidOpcode(int)`, `_isJumpOp(int)`, `_computeJumpTarget(int op, int instr, int pc)`, `_verifyOperandBounds(int op, int instr, int regCount, DarticModule, int pc)`
   - **DarticLoadError**：继承 Error，携带 errors 列表和模块路径
   - **集成点**：在 DarticInterpreter.execute() 或模块加载路径中可选调用 verify()（Task 6.4.3 集成）

4. **运行** — `fvm dart analyze && fvm dart test test/sandbox/verifier_test.dart`

---

### Task 6.4.2: 资源限制增强 — maxTotalFuel + executionTimeout + 错误分类

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`（maxTotalFuel + executionTimeout + 错误恢复）
- Create: `lib/src/sandbox/dartic_errors.dart`（DarticError / DarticInternalError 错误类型，若不已存在）
- Test: `test/sandbox/resource_limits_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch8"运行时资源限制"：
   - Fuel 计数（已有）：每回合 _fuelBudget = 50,000，耗尽后 Timer.run 让出
   - maxTotalFuel（新增）：跨回合累计指令数上限，超出后清空 _runQueue 并抛出 DarticError
   - executionTimeout（新增）：执行总时长上限，通过 Stopwatch 计时，超出后抛出 DarticError
   - maxCallDepth（已有，Ch3）：512 帧，超出抛 DarticError
   - Ch8"错误分类"：DarticLoadError（加载失败）、DarticError（运行时可恢复）、DarticInternalError（运行时实现 bug）
   - Ch8"错误恢复不变式"：DarticError 后运行时可继续使用；DarticInternalError 后运行时实例应被丢弃

2. **写测试** — 验证资源限制：
   - **maxTotalFuel**：设置低 maxTotalFuel（如 100）→ 执行简单循环 → 超出后抛 DarticError
   - **maxTotalFuel 跨回合累计**：设置 fuel = 100, _fuelBudget = 50 → 第一回合消耗 50（Timer.run 让出）→ 第二回合消耗 50 → 超出 → DarticError
   - **executionTimeout**：设置超时 100ms → 执行无限循环 → 超时后抛 DarticError
   - **maxCallDepth**：递归超过 512 层 → DarticError（验证已有行为）
   - **正常执行不触发限制**：合理程序在默认限制内正常完成
   - **错误恢复**：DarticError 后，同一解释器实例可执行另一个模块（验证状态清理）
   - **DarticLoadError 不影响运行时**：加载失败后解释器仍可用

3. **实现** —
   - **maxTotalFuel**：DarticInterpreter 新增 `int? maxTotalFuel` 配置字段 + `int _totalFuelConsumed = 0` 计数器。每回合 fuel 消耗累加到 _totalFuelConsumed。_driveInterpreter 回合结束时检查 `_totalFuelConsumed >= maxTotalFuel` → 清空 _runQueue → 抛 DarticError
   - **executionTimeout**：DarticInterpreter 新增 `Duration? executionTimeout` 配置字段。execute() 启动时记录 Stopwatch。_driveInterpreter 回合结束时检查 `stopwatch.elapsed >= executionTimeout` → 清空 _runQueue → 抛 DarticError
   - **错误类型**：
     - DarticError 继承 Error，含 message 字段
     - DarticInternalError 继承 Error，含 message + originalException 字段
     - FuelExhaustedError 继承 DarticError
     - TimeoutError 继承 DarticError
     - StackOverflowError（已有，确认使用 DarticError 子类）
   - **错误恢复**：DarticError catch 后，重置解释器内部状态（清空 _runQueue, 重置栈 sp, 重置 _totalFuelConsumed）

4. **运行** — `fvm dart analyze && fvm dart test test/sandbox/resource_limits_test.dart`

---

### Task 6.4.3: 沙箱集成测试 + 加载验证管线

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`（集成 DarticVerifier 到加载路径）
- Test: `test/sandbox/sandbox_integration_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch8"验证 → 加载 → 执行流水线"：(1) 反序列化 bytes → DarticModule (2) DarticVerifier 静态验证 → 失败则 DarticLoadError (3) Bridge 依赖检查（确认所需宿主 API 已注册）→ 缺失则 DarticLoadError (4) 返回已验证模块 → 运行时零安全开销执行

2. **写测试** — 端到端安全验证：
   - **格式错误字节码拒绝**：手工构造 magic 错误的 bytes → 反序列化 + 验证 → DarticLoadError
   - **校验和篡改检测**：正常 .darb 修改一个字节 → CRC 不匹配 → DarticLoadError
   - **非法操作码拒绝**：手工构造含非法 opcode 的模块 → 验证失败
   - **越界跳转拒绝**：手工构造跳转目标超出代码范围的模块 → 验证失败
   - **无限循环终止**：编译 `while(true) {}` → 执行 → fuel 耗尽 → DarticError（不卡死）
   - **无限递归终止**：编译 `void f() { f(); }` → 执行 → maxCallDepth → DarticError
   - **Bridge 依赖检查**：模块引用未注册的绑定 → DarticLoadError
   - **正常模块端到端**：编译器产出 → 序列化 → 反序列化 → 验证 → 执行 → 正确结果
   - **错误后恢复**：DarticError 后，同一解释器执行另一正常模块 → 成功

3. **实现** —
   - **加载管线集成**：在 DarticInterpreter 中增加 `loadAndVerify(Uint8List bytes)` 方法或修改现有 execute() 方法：
     - 反序列化 → DarticModule
     - 调用 DarticVerifier.verify() → 失败则抛 DarticLoadError
     - 绑定解析（resolveBindingTable）→ 未注册绑定则抛 DarticLoadError
     - 返回已验证模块
   - **Bridge 依赖检查**：遍历 module.bindingNames，每个绑定名在 HostBindings 中查找 → 缺失则加入错误列表
   - **文档更新**：更新 Ch8 设计文档中"已知局限"的实现状态

4. **运行** — `fvm dart analyze && fvm dart test test/sandbox/sandbox_integration_test.dart`

---

## Commit

```
feat(sandbox): add DarticVerifier bytecode validation and resource limits
```

**提交文件：** `lib/src/sandbox/`（新目录）+ 修改的 interpreter.dart + 全部新测试

## 核心发现

_(执行时填写：验证器的检查项覆盖情况、CRC32 校验的实际开销、fuel 粒度对用户体验的影响、maxTotalFuel/executionTimeout 的合理默认值、已发现的安全问题、Bridge 依赖检查对模块加载速度的影响等)_

## Batch 完成检查

- [ ] 6.4.1 DarticVerifier 字节码验证器
- [ ] 6.4.2 资源限制增强 — maxTotalFuel + executionTimeout + 错误分类
- [ ] 6.4.3 沙箱集成测试 + 加载验证管线
- [ ] `fvm dart analyze` 零警告
- [ ] `fvm dart test` 全部通过
- [ ] commit 已提交
- [ ] overview.md 已更新
- [ ] code review 已完成
