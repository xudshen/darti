# Batch 4.4: co19 Harness v2 — 实验标志与类型负面测试

## 概览

扩展 co19 测试运行器支持 `SharedOptions` 实验标志解析和类型相关负面测试完善，验证 Phase 4 新增的 co19 测试类别（Generics/Mixins/Interfaces/TypeSystem/subtyping/Class-modifiers），并重跑 Phase 2-3 全部类别确认零回归。

> **注意**：`static_type_helper.dart` 使用 `extension StaticType<T> on T`，extension method 要到 Phase 6.2 才实现，因此延迟到 Phase 6 harness v4。

**设计参考：** `tool/co19_runner.dart`（当前 harness v1 实现）、`docs/plans/development-roadmap.md`（harness 演进路线）

**依赖：** Batch 4.1-4.3（mixin/接口/泛型/类型系统全部就绪）

---

### Task 4.4.1: SharedOptions 实验标志解析

**产出文件：**
- Modify: `tool/co19_runner.dart`（TestEntry 扩展 + 解析逻辑）
- Test: `test/tool/co19_experiment_test.dart`

**TDD 步骤：**

1. **读设计文档** — co19 测试文件中 `// SharedOptions=--enable-experiment=<flag>` 注释格式。多个标志可逗号分隔（`--enable-experiment=records,patterns`）。部分 co19 测试（如 Class-modifiers、Records）需要实验标志才能正确编译
2. **写测试** — 验证：
   - 解析单个实验标志：`// SharedOptions=--enable-experiment=class-modifiers` → `['class-modifiers']`
   - 解析多个实验标志：`// SharedOptions=--enable-experiment=records,patterns` → `['records', 'patterns']`
   - 无 SharedOptions 的文件 → 空列表
   - 多行 SharedOptions（罕见但可能）→ 合并所有标志
   - 实验标志传递到 `fvm dart compile kernel` 命令
   - 不影响无标志测试的正常执行
3. **实现** —
   - TestEntry 增加 `List<String> experimentFlags` 字段（默认空列表）
   - discoverTests 中增加 SharedOptions 解析：读取文件前 20 行，正则匹配 `// SharedOptions=--enable-experiment=(.+)`，提取并分割实验标志
   - runTest 中传递实验标志：`Process.run('fvm', ['dart', 'compile', 'kernel', ...entry.experimentFlags.expand((f) => ['--enable-experiment=$f']), entry.path, '-o', dillPath])`
4. **运行** — `fvm dart analyze && fvm dart test test/tool/co19_experiment_test.dart`

---

### Task 4.4.2: 类型错误负面测试完善

**产出文件：**
- Modify: `tool/co19_runner.dart`（负面测试检测增强）
- Test: `test/tool/co19_negative_type_test.dart`

**TDD 步骤：**

1. **读设计文档** — 当前负面测试检测仅匹配 `// [analyzer]` 和 `// [cfe]` 标记。Phase 4 新增的 TypeSystem 和 Generics 测试中，部分测试文件包含更复杂的负面标记模式。review co19 的负面测试标记规范，确认是否有额外标记格式需要支持
2. **写测试** — 验证：
   - 现有标记仍正确识别：`// [analyzer]` + `// [cfe]` 成对出现
   - 类型相关负面测试：包含泛型约束违反、类型不匹配等编译错误的测试正确标记为 negative
   - 多个错误位置的文件：一个文件中多处 `// [analyzer]` 标记 → 整个文件标记为 negative
   - 区分静态错误和运行时错误：部分测试预期运行时抛出异常（如 `TypeError`），这些不是 negative test（它们应该编译成功但执行时抛异常）——当前逻辑已正确处理（negative 仅指编译失败）
   - 统计 Phase 4 新类别中 negative test 占比，评估影响
3. **实现** —
   - Review 并加固现有 isNegativeTest 函数：确认正则表达式覆盖 co19 标记规范的所有变体
   - 增加负面测试统计输出：在报告中显示每个类别的 negative/positive test 数量，帮助理解通过率
   - 对于预期运行时异常的测试（编译成功但执行应抛异常），确认当前逻辑：它们不是 negative test，执行时抛异常则 fail（这是预期行为——这些测试需要 dartic 正确实现异常语义才能 pass）
   - 可选增强：检测 `@dart=X.Y` 版本标记，跳过需要比当前支持更高 Dart 版本的测试
4. **运行** — `fvm dart analyze && fvm dart test test/tool/co19_negative_type_test.dart`

---

### Task 4.4.3: 验证——跑 Phase 4 新增 co19 类别

**产出文件：**
- Modify: `tool/co19_runner.dart`（新类别配置）
- 产出: `tool/co19_results/phase4.json`（结果快照）

**TDD 步骤：**

1. **读设计文档** — Phase 4 co19 测试目录：`Language/Generics/`（~195 测试）、`Language/Mixins/`（~143 测试）、`Language/Interfaces/`（~100 测试）、`TypeSystem/subtyping/`（~2,821 测试）、`LanguageFeatures/Class-modifiers/`（~267 测试）。里程碑目标：Generics > 50%、Mixins > 50%、TypeSystem/subtyping > 30%
2. **执行验证** —
   - 配置 co19_runner 扫描 Phase 4 新增的 5 个目录
   - 执行全量测试（预估 ~3,526 测试，并行度 8）
   - 收集并分析各类别通过率
   - 识别主要失败原因（按 Kernel AST 节点类型或错误类型分类）
   - 保存结果快照到 `tool/co19_results/phase4.json`
3. **结果分析** —
   - 对比里程碑目标，记录实际通过率
   - 列出 top 10 失败原因（帮助规划 Phase 5 的优先级）
   - 识别因缺少 Phase 5+ 特性而失败的测试类型（如 String 方法、集合操作等需要 Bridge 的测试）
4. **产出** — 更新 `docs/plans/development-roadmap.md` Phase 4 实际通过率

---

### Task 4.4.4: 回归跑——重跑 Phase 2-3 全部类别

**产出文件：**
- 产出: `tool/co19_results/phase4-regression.json`（回归快照）

**TDD 步骤：**

1. **读设计文档** — Phase 2-3 历史类别：`Language/Variables`、`Language/Expressions`、`Language/Statements`、`Language/Functions`、`Language/Classes`、`Language/Reference`。Phase 3 基线快照：`tool/co19_results/phase3.json`。回归 = 上次 pass 本次 fail
2. **执行回归检测** —
   - 重跑 Phase 2-3 全部 6 个类别（~4,167 测试）
   - 保存结果到 `tool/co19_results/phase4-regression.json`
   - diff phase3.json vs phase4-regression.json
   - 输出：新增 pass / 回归 fail / 持续 pass / 持续 fail
3. **回归修复** —
   - 回归项必须在本 Batch 内修复，不得带入 Phase 5
   - 分析回归原因：通常是泛型/mixin 代码修改对已有路径的副作用
   - 修复后重跑确认零回归
4. **产出** —
   - 更新 `docs/plans/development-roadmap.md` Phase 4 回归数据
   - 记录历史提升（Phase 4 新能力解锁的历史类别通过数）
   - 预估 Phase 4 新能力对历史类别的提升数（泛型、mixin、接口的 `is` 检查解锁部分之前 fail 的测试）

---

## Commit

```
feat: co19 harness v2 — experiment flags and type error tests
```

**提交文件：** 修改的 co19_runner.dart + 新测试 + 结果快照文件

## 核心发现

_(执行时填写：SharedOptions 实际使用频率、Phase 4 各类别通过率、主要失败原因 top 10、历史回归数和新增 pass 数、TypeSystem/subtyping 的通过率分布——static vs dynamic 子类别差异等)_

## Batch 完成检查

- [ ] 4.4.1 SharedOptions 实验标志解析
- [ ] 4.4.2 类型错误负面测试完善
- [ ] 4.4.3 验证——跑 Phase 4 新增 co19 类别
- [ ] 4.4.4 回归跑——重跑 Phase 2-3 全部类别
- [ ] `fvm dart analyze` 零警告
- [ ] `fvm dart test` 全部通过
- [ ] 零回归（或回归已修复）
- [ ] commit 已提交
- [ ] overview.md 已更新
- [ ] development-roadmap.md Phase 4 里程碑已更新
- [ ] code review 已完成
