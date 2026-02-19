# 任务总索引

## POC 阶段 — ✅ 已完成，已归档

代码与文档均已归档至 `archive/poc/` 和 `archive/poc-docs/`，不再维护。

---

## Phase 1: 最小可运行管线 — ✅ 已完成

**目标：** 能编译并执行 `int add(int a, int b) => a + b;`

**Task 目录：** [`docs/tasks/phase1/`](phase1/README.md)

| Batch | 描述 | Task 数 | 状态 |
|-------|------|---------|------|
| [1.1](phase1/batch-1.1-bytecode-infra.md) | 字节码基础设施 (Ch1) | 4 | ✅ |
| [1.2](phase1/batch-1.2-stack-object-model.md) | 三栈与对象模型 (Ch2) | 4 | ✅ |
| [1.3](phase1/batch-1.3-dispatch-loop.md) | 分发循环 (Ch3) | 6 | ✅ |
| [1.4](phase1/batch-1.4-minimal-compiler.md) | 最小编译器 (Ch5) | 6 | ✅ |
| [1.5](phase1/batch-1.5-module-format.md) | 模块格式与运行时补全 | 6 | ✅ |

**里程碑：**
- [x] 手工字节码端到端执行通过
- [x] Dart 源码 → Kernel → 字节码 → 执行通过
- [x] 编译→序列化→反序列化→执行 roundtrip 通过

---

## Phase 2: 基础语言特性 — ✅ 已完成

**目标：** 支持变量声明（含全局变量）、完整表达式求值、控制流语句，并通过 co19 harness v0 验证

**Task 目录：** [`docs/tasks/phase2/`](phase2/README.md)

| Batch | 描述 | Task 数 | 状态 |
|-------|------|---------|------|
| [2.1](phase2/batch-2.1-variables.md) | 变量与赋值 | 3 | ✅ |
| [2.2](phase2/batch-2.2-expressions.md) | 表达式 | 6 | ✅ |
| [2.3](phase2/batch-2.3-statements.md) | 语句与控制流 | 6 | ✅ |
| [2.4](phase2/batch-2.4-co19-harness.md) | co19 Harness v0 | 6 | ✅ |

**里程碑：**
- [x] co19 `Language/Variables` 通过率 > 50% — 实际 65.8% (73/111)
- [x] co19 `Language/Expressions` 基础子集通过率 > 30% — 实际 53.4% (1032/1933)
- [x] co19 `Language/Statements` 通过率 > 30% — 实际 49.9% (268/537)

---

## Phase 3: 函数与类 — ✅ 已完成

**目标：** 支持函数进阶（可选参数、闭包）、类（实例化/字段/方法/构造器/继承），通过 co19 harness v1 验证

**Task 目录：** [`docs/tasks/phase3/`](phase3/README.md)

| Batch | 描述 | Task 数 | 状态 |
|-------|------|---------|------|
| [3.1](phase3/batch-3.1-functions.md) | 函数进阶 | 4 | ✅ |
| [3.2](phase3/batch-3.2-class-basics.md) | 类基础 | 6 | ✅ |
| [3.3](phase3/batch-3.3-inheritance.md) | 继承与多态 | 4 | ✅ |
| [3.4](phase3/batch-3.4-scope-resolution.md) | 作用域与名称解析 | 3 | ✅ |
| [3.5](phase3/batch-3.5-co19-harness-v1.md) | co19 Harness v1 | 6 | ✅ |
| [3.6](phase3/batch-3.6-type-template.md) | 泛型编译预备 | 3 | ✅ |

**里程碑：**
- [x] co19 `Language/Functions` 通过率 > 50% — 实际 72.2% (135/187)
- [x] co19 `Language/Classes` 基础子集通过率 > 40% — 实际 76.8% (649/845)
- [x] co19 `Language/Reference` 通过率 > 40% — 实际 81.4% (451/554)
- [x] Phase 2 类别零回归（或回归已修复） — 0 回归
- [x] Phase 2 类别通过率较上期有提升 — 53.2% → 56.2% (+78 new pass)

---

## Phase 4: 高级 OOP + 泛型 — ✅ 已完成

**目标：** 实现泛型运行时系统（Ch6）、mixin/接口/类修饰符、完整子类型检查，通过 co19 harness v2 验证

**Task 目录：** [`docs/tasks/phase4/`](phase4/README.md)

| Batch | 描述 | Task 数 | 状态 |
|-------|------|---------|------|
| [4.1](phase4/batch-4.1-mixin-interface.md) | Mixin 与接口 | 3 | ✅ |
| [4.2](phase4/batch-4.2-generics-core.md) | 泛型核心 (Ch6) | 6 | ✅ (含 review 后修复：ref/value 栈协调) |
| [4.3](phase4/batch-4.3-type-system.md) | 类型系统 | 3 | ✅ |
| [4.4](phase4/batch-4.4-co19-harness-v2.md) | co19 Harness v2 | 4 | ✅ |

**里程碑：**
- [x] co19 `Language/Generics` 通过率 > 50% — 实际 73.3% (143/195)
- [x] co19 `Language/Mixins` 通过率 > 50% — 实际 69.2% (99/143)
- [x] co19 `Language/Interfaces` 通过率 > 50% — 实际 80.0% (80/100)
- [x] co19 `TypeSystem/subtyping` 核心子集通过率 > 30% — 实际 49.4% (1345/2721)
- [x] co19 `LanguageFeatures/Class-modifiers` 通过率 > 30%（约 60% 为负面测试）— 实际 62.5% (167/267)
- [x] Phase 2-3 类别零回归（或回归已修复） — 0 回归
- [x] Phase 2-3 类别通过率较上期有提升（泛型解锁大量之前的类型相关测试）— +46 new pass, 64.5% → 65.6%

---

## Phase 5: 标准库互调 (Ch4) — 进行中

**目标：** 实现跨边界互调层（Ch4），桥接 dart:core 核心类型，通过 co19 LibTest/core 测试 + 历史类别大幅提升

**Task 目录：** [`docs/tasks/phase5/`](phase5/README.md)

| Batch | 描述 | Task 数 | 状态 |
|-------|------|---------|------|
| [5.1](phase5/batch-5.1-bridge-infra.md) | Bridge 基础设施 + CALL_HOST 管线 | 5 | |
| [5.2](phase5/batch-5.2-core-bridges.md) | dart:core 完整桥接 | 6 | |
| [5.3](phase5/batch-5.3-collections-strings.md) | 集合字面量、字符串插值与回调 | 4 | |
| [5.4](phase5/batch-5.4-co19-harness-v3.md) | co19 Harness v3 — 验证与回归 | 4 | |

**里程碑：**
- [ ] co19 `LibTest/core` 通过率 > 30%（~1353 测试）
- [ ] Bridge 基础类型方法覆盖率：int > 60%、String > 50%、List > 50%、Map > 40%
- [ ] Phase 2-4 类别零回归（或回归已修复）
- [ ] Phase 2-4 类别通过率较上期有提升（Bridge 解锁 print/toString/Duration 等）

---

## Phase 6: 异步 + 高级语言特性 — 待规划

**目标：** 支持 async/await、generators、pattern matching、records、extension methods，实现沙箱安全机制

**Task 目录：** 待创建

| Batch | 描述 | Task 数 | 状态 |
|-------|------|---------|------|
| 6.1 | 异步核心 (Ch7) | 5 | |
| 6.2 | 高级语言特性 | 6 | |
| 6.3 | co19 Harness v4 | 6 | |
| 6.4 | 沙箱 (Ch8) | 3 | |

**里程碑：**
- [ ] co19 `LibTest/async` 通过率 > 30%
- [ ] co19 `LanguageFeatures/Patterns` 通过率 > 40%
- [ ] co19 `LanguageFeatures/Records` 通过率 > 50%
- [ ] Phase 2-5 全量零回归

详见 [`docs/plans/development-roadmap.md`](../plans/development-roadmap.md)

---

## Phase 7: 公开 API + 代码生成 — 待规划

**目标：** 封装 DarticEngine 公开 API，实现 @DarticExport 代码生成器，提供 Flutter Bridge 和热更新 demo

**设计参考：** [`docs/plans/2026-02-20-bridge-api-design.md`](../plans/2026-02-20-bridge-api-design.md)

**Task 目录：** 待创建

| Batch | 描述 | Task 数 | 状态 |
|-------|------|---------|------|
| 7.1 | DarticEngine 公开 API | 5 | |
| 7.2 | @DarticExport 代码生成 | 5 | |
| 7.3 | Flutter Bridge + 热更新 Demo | 4 | |

**里程碑：**
- [ ] DarticEngine 3 行代码加载执行 .darb 脚本
- [ ] @DarticExport 生成的 Bridge 与手写 Bridge 功能等价
- [ ] Flutter 热更新 demo 端到端运行

详见 [`docs/plans/development-roadmap.md`](../plans/development-roadmap.md)
