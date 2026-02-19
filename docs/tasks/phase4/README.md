# Phase 4: 高级 OOP + 泛型

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 实现泛型运行时系统（Ch6）、mixin/接口/类修饰符、完整子类型检查，通过 co19 Generics/Mixins/Interfaces/TypeSystem 测试

**Architecture:** Phase 3 末尾的 TypeTemplate 基础设施（Batch 3.6）提供编译期类型编码。Phase 4 在运行时侧构建 DarticType 驻留表和类型解析器，将编译期 TypeTemplate 实例化为运行时 DarticType。同时扩展编译器处理 mixin 线性化、接口契约和类修饰符。Ch6 泛型系统的核心是 ITA/FTA 类型参数传递 + isSubtypeOf 子类型判定。Batch 4.1 先完成 mixin/接口（扩展已有类系统），4.2 引入泛型运行时核心，4.3 完善类型系统，4.4 用 harness v2 验证。

**Tech Stack:** Pure Dart, Kernel AST (`package:kernel`), TDD (`package:test`), co19 测试集

---

## 设计文档依赖

| Batch | 主要设计章节 | 关键参考节 |
|-------|-------------|-----------|
| 4.1 Mixin 与接口 | Ch2 对象模型, Ch5 编译器 | Kernel mixin 线性化、implementedTypes、supertypeIds 扩展、类修饰符 |
| 4.2 泛型核心 | Ch6 泛型 | DarticType 驻留、ITA/FTA 槽位、resolveType 四分支、INSTANCEOF/CAST |
| 4.3 类型系统 | Ch6 泛型 | isSubtypeOf 12 规则、isFunctionSubtype 9 检查、FutureOr 规范化、空安全 |
| 4.4 co19 Harness v2 | — | SharedOptions 解析、类型负面测试、新类别验证、回归检测 |

## Batch 索引

| Batch | 文件 | Task 数 | 依赖 |
|-------|------|---------|------|
| [4.1](batch-4.1-mixin-interface.md) | batch-4.1-mixin-interface.md | 3 | Phase 3 全部 |
| [4.2](batch-4.2-generics-core.md) | batch-4.2-generics-core.md | 6 | Batch 3.6 + 4.1 |
| [4.3](batch-4.3-type-system.md) | batch-4.3-type-system.md | 3 | Batch 4.2 |
| [4.4](batch-4.4-co19-harness-v2.md) | batch-4.4-co19-harness-v2.md | 4 | Batch 4.1-4.3 |

## 里程碑验证

- [ ] co19 `Language/Generics` 通过率 > 50%
- [ ] co19 `Language/Mixins` 通过率 > 50%
- [ ] co19 `Language/Interfaces` 通过率 > 50%
- [ ] co19 `TypeSystem/subtyping` 核心子集通过率 > 30%
- [ ] co19 `LanguageFeatures/Class-modifiers` 通过率 > 30%（约 60% 为负面测试）
- [ ] Phase 2-3 类别零回归（或回归已修复）
- [ ] Phase 2-3 类别通过率较上期有提升（泛型解锁大量之前的类型相关测试）

## co19 测试范围

| 类别 | 目录 | 预估测试数 | 说明 |
|------|------|-----------|------|
| Generics | `Language/Generics/` | ~195 | 泛型类/方法/参数/FutureOr |
| Mixins | `Language/Mixins/` | ~143 | Mixin 声明/应用/类 |
| Interfaces | `Language/Interfaces/` | ~100 | 接口层次/成员签名/覆写 |
| TypeSystem/subtyping | `TypeSystem/subtyping/` | ~2,821 | 静态/动态子类型检查（占比最大） |
| Class-modifiers | `LanguageFeatures/Class-modifiers/` | ~267 | sealed/base/final/interface |
| **Phase 4 新增合计** | | **~3,526** | |
| Phase 2-3 历史类别 | | ~4,167 | 回归检测 + 历史提升 |

## 执行节奏

- 每个 Task 遵循 TDD：读设计文档 → 写测试 → 最小实现 → `fvm dart analyze` → `fvm dart test` → 重构
- 每完成一个 Batch 勾选 checkbox → 填写"核心发现" → 更新 `docs/tasks/overview.md` → 提交 commit
- Batch 4.2（泛型核心）是 Phase 4 最大 Batch（6 个 Task），建议按 4.2.1-4.2.3（运行时基础设施）和 4.2.4-4.2.6（编译器集成）两段推进
