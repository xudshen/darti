# Batch 3.5: co19 Harness v1 — 接入 expect.dart（类已就绪）

## 概览

Phase 3 的类和多文件编译已就绪，从 Phase 2 的函数 shim（expectEquals 等纯函数）切换到 co19 的真正 `Utils/expect.dart`（class Expect + class ExpectException）。实现相对路径 import 解析、多文件测试编译、工厂模式测试支持。在新增类别（Functions/Classes/Reference）和历史类别（Variables/Expressions/Statements）上运行验证和回归测试。

**设计参考：** 无新设计章节。依赖 Batch 3.2-3.4 的类/import 功能

**依赖：** Batch 3.3（继承——ExpectException extends Error）+ Batch 3.4（多文件 import——expect.dart 路径解析）

---

### Task 3.5.1: 编译 Utils/expect.dart

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`（如需适配）
- Modify: `tool/co19_runner.dart`
- Test: `test/e2e/expect_dart_test.dart`

**TDD 步骤：**

1. **读 expect.dart 源码** — `vendor/co19/Utils/expect.dart`，理解其结构：import expect_common.dart、class Expect（全静态方法）、class ExpectException。注意顶层 `import 'dart:async'`——Phase 3 无 async 支持，需处理此 import（忽略或 stub）
2. **写测试** — 验证：
   - 编译 expect.dart 的简化版本（去除 dart:async import 和 async 相关方法）→ DarticModule 包含 Expect 和 ExpectException 类
   - Expect.equals(expected, actual) 在值相等时无异常
   - Expect.equals(expected, actual) 在值不等时抛 ExpectException
   - Expect.isTrue / Expect.isFalse 正常工作
   - Expect.throws 捕获到异常 → pass
3. **实现** —
   - 在 co19_runner 编译流程中，将 expect.dart 与测试文件一起编译为单个 Component（利用 Kernel 的多库编译）
   - 处理 `import 'dart:async'`：Phase 3 暂不支持 dart:async，需要在编译前过滤或 stub。选项：(a) 跳过 dart:* import 库的编译，只编译用户代码引用的成员；(b) Kernel loader 已包含 platform libraries，编译器忽略未使用的 dart:async 成员
   - 测试 Expect 的核心静态方法能通过 CALL_STATIC 正确调用
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/expect_dart_test.dart`

---

### Task 3.5.2: 相对路径 import 解析

**产出文件：**
- Modify: `tool/co19_runner.dart`
- Test: `test/e2e/relative_import_test.dart`

**TDD 步骤：**

1. **读设计文档** — 理解 co19 测试的 import 模式：`import '../../Utils/expect.dart'`。Kernel 编译（`fvm dart compile kernel`）已自动解析相对路径——只要所有源文件在同一次编译中可达。co19_runner 当前只编译单个测试文件
2. **写测试** — 验证：
   - 含 `import '../helper.dart'` 的测试文件能正确编译（Kernel resolve 所有依赖）
   - 含 `import '../../Utils/expect.dart'` 的 co19 测试能编译和执行
   - 循环 import 不死循环（Kernel 已处理）
   - import 的类/函数在测试代码中可用
3. **实现** —
   - 修改 co19_runner 的编译步骤：将测试文件路径传给 `fvm dart compile kernel`，Kernel 编译器自动解析所有 import 依赖并打包到 .dill
   - 编译器端：Component 中包含多个 Library（测试文件 + expect.dart + 其他依赖），遍历所有非 dart:* Library
   - 验证 `fvm dart compile kernel` 能正确处理 co19 测试的相对路径 import
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/relative_import_test.dart`

---

### Task 3.5.3: 多文件测试支持

**产出文件：**
- Modify: `tool/co19_runner.dart`
- Modify: `lib/src/compiler/compiler.dart`（如需扩展多库处理）
- Test: `test/e2e/multi_file_test.dart`

**TDD 步骤：**

1. **分析 co19 多文件测试模式** — co19 中部分测试使用 `library` 声明 + `import` 其他测试辅助文件 + `part` 指令。理解 Kernel 中 Library.parts（PartOf 关系）
2. **写测试** — 验证：
   - 含 library 声明 + part 的测试文件能编译
   - 测试文件 import 同目录其他 Dart 文件
   - 多个 library 中的类和函数互相引用
   - part 文件中的声明在主 library 中可见
3. **实现** —
   - Kernel 编译器已将 part 文件合并到主 Library 中，编译器无需特殊处理 part
   - 确保编译器能处理 Component 中多个 Library 的依赖关系
   - co19_runner 无需特殊修改——Kernel 编译步骤已解析所有依赖
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/multi_file_test.dart`

---

### Task 3.5.4: 工厂模式测试支持

**产出文件：**
- Modify: `tool/co19_runner.dart`（如需适配）
- Test: `test/e2e/factory_pattern_test.dart`

**TDD 步骤：**

1. **分析 co19 工厂测试模式** — 部分 co19 测试使用 `test(Factory create)` 回调模式：定义工厂函数，测试代码传入不同工厂以测试多种构造方式
2. **写测试** — 验证：
   - 工厂函数作为参数传递（Function 类型参数 + 闭包调用）
   - `test()` 函数接受回调并调用
   - 工厂模式与 Expect 断言组合使用
3. **实现** —
   - 工厂模式依赖 Batch 3.1 的一等公民函数支持（CALL 闭包）
   - 确保函数类型参数（`void Function(Factory)` 等）正确编译
   - co19_runner 可能需要识别并处理 `test()` 入口模式（非标准 main()）
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/factory_pattern_test.dart`

---

### Task 3.5.5: 验证跑——新增类别（Functions / Classes / Reference）

**产出文件：**
- Modify: `tool/co19_runner.dart`（添加新类别目录）
- Create: `tool/co19_results/phase3.json`

**TDD 步骤：**

1. **配置 co19_runner** — 添加 `Language/Functions`、`Language/Classes`、`Language/Reference` 到扫描目录列表
2. **首轮运行** — 执行 `fvm dart run tool/co19_runner.dart` 包含新增三个类别
3. **分析结果** — 统计各类别通过率，识别主要失败原因（预期：大量测试依赖泛型/async/collection 等 Phase 3 未支持的特性）
4. **保存快照** — 将结果保存为 `tool/co19_results/phase3.json`
5. **记录通过率** — 更新 roadmap 中 Phase 3 里程碑的实际通过率

---

### Task 3.5.6: 回归跑——重跑 Phase 2 全部类别

**产出文件：**
- Update: `tool/co19_results/phase3.json`（包含历史类别结果）

**TDD 步骤：**

1. **重跑历史类别** — 运行 co19_runner 包含 Phase 2 的三个类别（Variables / Expressions / Statements）
2. **对比基线** — 使用 co19_runner 的 diff 功能对比 Phase 2 快照（`tool/co19_results/phase2.json`）
3. **回归分析** — 识别回归项（上次 pass → 本次 fail）。回归项必须在 Phase 3 内修复
4. **新增 pass 统计** — 记录因类/闭包/继承等新能力而新增通过的测试数
5. **修复回归** — 如有回归，分析原因并修复。常见原因：编译器扩展引入的副作用、参数约定变化、新 opcode 与旧逻辑冲突
6. **更新里程碑** — 更新 roadmap 和 overview.md 中的回归和新增 pass 数据

---

## Commit

```
feat: co19 harness v1 — integrate expect.dart with class support
```

**提交文件：** 修改的 co19_runner.dart + compiler.dart + 新测试 + co19_results/phase3.json

## 核心发现

### Task 3.5.1
1. **EqualsCall generic path 未 box 操作数** — `_compileEqualsCall` 在 generic 路径（非 int/double）直接使用 `EQ_GENERIC`（读 ref stack），但未确保操作数在 ref stack 上。当 `Object?` 类型变量与 `true`/`false` 字面量比较时，字面量在 value stack 上，导致比较结果错误。修复：在 `else` 分支中对 value-stack 操作数调用 `_emitBoxToRef`。
2. **跨帧异常传播未实现** — THROW/RETHROW 仅搜索当前帧的 exception table，不在的话直接 `throw exception!` 到宿主 VM。当 `Expect.throws(() { throw 'error'; })` 执行时，`throw 'error'` 在内层闭包帧中发生，无法被外层 `Expect.throws` 的 try/catch 捕获。修复：实现跨帧异常展开——循环弹出帧并搜索 caller 的 exception table，直到找到 handler 或回到 entry frame。
3. **简化 expect.dart 策略** — 去除 `implements Exception`（避免平台类型 is 检查问题）、`dart:async`、泛型、字符串插值等不支持特性。ExpectException 使用普通 class 而非 `implements Exception`。

### Task 3.5.3
1. **Kernel CFE 已完整处理 part 合并** — `library` + `part` 指令在 Kernel 编译阶段（`fvm dart compile kernel`）已被完全解析：part 文件中的所有声明被合并到主 Library 的 members 中。DarticCompiler 遍历 `component.libraries` 时自然处理了这些合并后的声明，无需任何编译器修改。
2. **跨 part 文件的双向引用正常** — part 文件可以调用主 library 中定义的函数（如 `computed() => baseValue() * 3`），不同 part 文件之间也可以互相引用（如 part2 调用 part1 的 `getA()`）。这是因为 Kernel 将它们视为同一 Library 的成员。
3. **多 Library 交叉引用无需特殊处理** — 多个独立 library 被 main 文件 import 后，Kernel Component 中包含多个 Library 节点，DarticCompiler 的多 pass 编译（Pass 1a/1b/1c → Pass 2a/2b/2c）自然遍历所有非 platform library，函数/类的跨库引用通过 `_procToFuncId` 映射正确解析。

### Task 3.5.5
1. **noSuchMethod forwarder 报 `Unknown constructor: _InvocationMirror._withType`** — 原因不是 `Invocation` 类未定义，而是 CFE 为含 `noSuchMethod` 覆写的类自动生成了 synthetic forwarder 方法，其方法体使用了 `dart:core` 内部私有类 `_InvocationMirror._withType`、`List.unmodifiable`、`_GrowableList._literal1` 等平台 API。dartic 不编译 `dart:core` 内部代码，因此无法处理这些调用。影响约 54 个 co19 测试。修复方案：在 `_compileProcedure` 中检测 `proc.isNoSuchMethodForwarder`，跳过 CFE 生成的方法体，改为自己生成字节码（加载 null 作为 Invocation 参数 → CALL_VIRTUAL noSuchMethod → 返回结果）。此修复不随 Phase 4/5 自动解决，需要专门处理。
2. **三个新类别通过率均远超目标** — Functions 72.2%（目标 >50%）、Classes 76.8%（目标 >40%）、Reference 81.4%（目标 >40%）。主要失败原因：`InstanceConstant`（常量对象构造）占大多数 fail，其次是 `_InvocationMirror._withType`（noSuchMethod forwarder）、`YieldStatement`（async/generator）、`DynamicInvocation`（dynamic 调用）。

### Task 3.5.6
1. **Phase 2 类别零回归** — 对比 phase2-baseline.json，0 个回归、78 个新通过。总通过率从 53.2% (1373/2581) 提升到 56.2% (1451/2581)。新通过主要分布在 Expressions（+57，包括 Instance_Creation、Property_Extraction、Function_Expressions 等因类/闭包支持而新通过的测试）和 Statements（+18，主要是 Return/If/Local_Variable 相关）。

### Task 3.5.4
1. **工厂模式已完整支持，无需编译器修改** — Batch 3.1 的一等公民函数支持（StaticTearOff + CLOSURE + CALL）和 Batch 3.2 的类支持已覆盖工厂模式所需的全部能力：函数作为参数传递（StaticTearOff）、lambda 作为参数（FunctionExpression）、通过函数参数创建对象实例、多个回调组合。
2. **co19 的 `test(Factory create)` 回调模式可正常工作** — 验证了完整的 co19 风格模式：定义类 → 传入 lambda 作为工厂函数 → 在回调中调用工厂创建实例 → 断言实例属性。与 Expect 断言类组合使用也无问题。

## Batch 完成检查

- [x] 3.5.1 编译 Utils/expect.dart
- [x] 3.5.2 相对路径 import 解析
- [x] 3.5.3 多文件测试支持
- [x] 3.5.4 工厂模式测试支持
- [x] 3.5.5 验证跑新增类别
- [x] 3.5.6 回归跑 Phase 2 类别 — 0 回归，+78 new pass
- [x] co19 Language/Functions 通过率 > 50% — 实际 72.2% (135/187)
- [x] co19 Language/Classes 通过率 > 40% — 实际 76.8% (649/845)
- [x] co19 Language/Reference 通过率 > 40% — 实际 81.4% (451/554)
- [x] Phase 2 类别零回归（或回归已修复） — 0 回归，+78 new pass
- [ ] commit 已提交
- [x] overview.md 已更新
- [x] code review 已完成
