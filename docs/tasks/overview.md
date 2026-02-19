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

## Phase 4: 高级 OOP + 泛型

**目标：** 实现泛型运行时系统（Ch6）、mixin/接口/类修饰符、完整子类型检查，通过 co19 harness v2 验证

**Task 目录：** [`docs/tasks/phase4/`](phase4/README.md)

| Batch | 描述 | Task 数 | 状态 |
|-------|------|---------|------|
| [4.1](phase4/batch-4.1-mixin-interface.md) | Mixin 与接口 | 3 | |
| [4.2](phase4/batch-4.2-generics-core.md) | 泛型核心 (Ch6) | 6 | |
| [4.3](phase4/batch-4.3-type-system.md) | 类型系统 | 3 | |
| [4.4](phase4/batch-4.4-co19-harness-v2.md) | co19 Harness v2 | 4 | |

**里程碑：**
- [ ] co19 `Language/Generics` 通过率 > 50%
- [ ] co19 `Language/Mixins` 通过率 > 50%
- [ ] co19 `Language/Interfaces` 通过率 > 50%
- [ ] co19 `TypeSystem/subtyping` 核心子集通过率 > 30%
- [ ] co19 `LanguageFeatures/Class-modifiers` 通过率 > 30%（约 60% 为负面测试）
- [ ] Phase 2-3 类别零回归（或回归已修复）
- [ ] Phase 2-3 类别通过率较上期有提升（泛型解锁大量之前的类型相关测试）

---

## Phase 5-6: 待规划

详见 [`docs/plans/development-roadmap.md`](../plans/development-roadmap.md)
