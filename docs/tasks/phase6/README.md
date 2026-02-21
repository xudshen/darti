# Phase 6: 异步 + 高级语言特性

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 实现 async/await、sync*/async* 生成器、extension methods、records、pattern matching、constructor tearoffs 等高级语言特性，构建字节码加载验证器（沙箱），通过 co19 harness v4 验证 LibTest/async + LanguageFeatures/* 新类别

**Architecture:** Phase 6 分为四条工作线。(1) 异步核心（Ch7）：基于帧即续体（Frame-as-Continuation）模型，DarticFrame 挂起时将全局栈区间快照到帧对象，恢复时在栈顶重新分配空间并拷回，通过 Completer/StreamController 桥接返回 VM 原生 Future/Stream。(2) 高级语言特性：Records 需新增 CREATE_RECORD 指令 + 编译器 visitor；Constructor tearoffs 需生成 thunk FuncProto；Extension methods/Enhanced enums/Patterns/Super parameters 主要依赖 CFE 脱糖，验证+修补即可。(3) co19 harness v4：接入 static_type_helper + async_utils + dart:async Bridge，支持异步测试协议。(4) 沙箱（Ch8）：DarticVerifier 加载时静态验证 + 运行时资源限制增强。

**Tech Stack:** Pure Dart, Kernel AST (`package:kernel`), TDD (`package:test`), co19 测试集

---

## 决策记录

| 问题 | 决策 | 理由 |
|------|------|------|
| dart:async Bridge 引入时机 | Batch 6.3（harness v4 验证前） | Batch 6.1 的运行时异步直接使用 Dart API（Completer/StreamController），不需要 CALL_HOST bridge；LibTest/async 用户代码需要 bridge 才能通过 |
| Pattern matching 实现策略 | 先验证 CFE 脱糖，仅在需要时实现 visitors | `05-compiler.md` 标注 patterns "已由 CFE 脱糖到 if-else 链"，但需编译实际测试验证 |
| Records 运行时表示 | 使用 host Dart VM Record 对象（pass-through） | 与 List/Map/Set 一致的策略，复用 host VM 的 structural equality 和 hashCode |
| Extension methods | 依赖 CFE 脱糖（StaticInvocation），不写特殊编译器逻辑 | 设计文档确认已脱糖；`05-compiler.md` line 486 |
| Enhanced enums | 作为普通 Class 处理 + Enum 基类 Bridge | Kernel 将 enhanced enum 表示为 Class + Procedure，仅需 Enum.index/values/name Bridge |
| async* yield* 背压传播 | Phase 6 不实现 | Ch7 设计文档明确标注为已知局限，Phase 2 演进 |
| await 同步快速路径 | Phase 6 不实现（总是让出 microtask） | Dart 语言规范要求 await 总是让出 >=1 次 microtask |
| SyncStarIterable 实现位置 | dartic 运行时内部类（非 Bridge） | sync* 的 moveNext() 需要驱动解释器帧执行，不能委托给 host VM |

---

## 设计文档依赖

| Batch | 主要设计章节 | 关键参考节 |
|-------|-------------|-----------|
| 6.1 异步核心 | Ch7 异步与生成器 | 帧即续体、DarticFrame 字段、挂起/恢复流程、异步帧状态机、sync*/async* 生成器、AWAIT 语义、栈恢复不变式 |
| 6.2 高级语言特性 | Ch5 编译器 | CFE 脱糖状态（line 476-504）、Tearoff 编译（line 424-436）、Record 编译（line 381-383）、Generator 编译（line 456-474） |
| 6.3 Harness v4 | — | co19 Utils 分层依赖、async_utils.dart 协议、static_type_helper.dart 需 extension method |
| 6.4 沙箱 | Ch8 安全与沙箱 | DarticVerifier 验证项（12 项）、威胁模型、错误分类、资源限制语义 |

## Batch 索引

| Batch | 文件 | Task 数 | 依赖 |
|-------|------|---------|------|
| [6.1](batch-6.1-async-core.md) | batch-6.1-async-core.md | 5 | Phase 5 全部 |
| [6.2](batch-6.2-language-features.md) | batch-6.2-language-features.md | 6 | Phase 5 全部（可与 6.1 并行，建议 6.1 之后） |
| [6.3](batch-6.3-co19-harness-v4.md) | batch-6.3-co19-harness-v4.md | 6 | Batch 6.1 + 6.2 |
| [6.4](batch-6.4-sandbox.md) | batch-6.4-sandbox.md | 3 | Phase 5 全部（可与 6.1/6.2 并行） |

## 里程碑验证

- [ ] co19 `LibTest/async` 通过率 > 30%
- [ ] co19 `LanguageFeatures/Patterns` 通过率 > 40%
- [ ] co19 `LanguageFeatures/Records` 通过率 > 50%
- [ ] co19 `LanguageFeatures/Extension-methods` 通过率 > 60%
- [ ] co19 `LanguageFeatures/Constructor-tear-offs` 通过率 > 50%
- [ ] Phase 2-5 全量零回归（或回归已修复）
- [ ] Phase 2-5 类别通过率较上期有提升（async + 语言特性解锁历史测试）

## co19 测试范围（预估）

| 类别 | 目录 | 预估测试数 | 预估通过率 | 目标 |
|------|------|----------|----------|------|
| LibTest/async | `LibTest/async/` | ~557 | 25-40% | >30% |
| Extension-methods | `LanguageFeatures/Extension-methods/` | ~275 | 50-70% | >60% |
| Extension-types | `LanguageFeatures/Extension-types/` | ~360 | 40-60% | >40% |
| Enhanced-Enum | `LanguageFeatures/Enhanced-Enum/` | ~156 | 50-70% | >50% |
| Records | `LanguageFeatures/Records/` | ~172 | 35-50% | >50% |
| Patterns | `LanguageFeatures/Patterns/` | ~786 | 20-40% | >40% |
| Constructor-tear-offs | `LanguageFeatures/Constructor-tear-offs/` | ~378 | 40-60% | >50% |
| Super-parameters | `LanguageFeatures/Super-parameters/` | ~139 | 50-70% | >50% |
| **新增合计** | | **~2,823** | | |
| Phase 2-5 历史类别 | 全十二类 | ~8,717 | ~70-75% | >70%, 0 回归 |
| **全部累计** | | **~11,540** | | |

### 历史提升预估

async + 高级语言特性将解锁历史类别中之前因特性缺失而失败的测试：

| 解锁来源 | 预估新增 pass | 说明 |
|---------|------------|------|
| async/await 编译 | ~100 | Language/* 中包含 async 函数声明的测试，之前因 _emitAsyncStub 失败 |
| extension methods | ~50 | 散布在各类别中使用 extension 的测试 |
| records/patterns | ~80 | Expressions/Statements 中的 record/pattern 语法 |
| constructor tearoffs | ~70 | Classes/Functions 中的构造器 tearoff 和类型参数化 |
| **预估历史提升合计** | **~300** | 保守估计 |

### 累计预估

| | 乐观 | 保守 |
|---|------|------|
| 新增类别 pass | ~1,500 | ~1,000 |
| 历史提升 | ~500 | ~200 |
| Phase 5 累计 | 5,852 | 5,852 |
| **Phase 6 累计** | **~7,850** | **~7,050** |

## 执行节奏

- 每个 Task 遵循 TDD：读设计文档 -> 写测试 -> 最小实现 -> `fvm dart analyze` -> `fvm dart test` -> 重构
- 每完成一个 Batch 勾选 checkbox -> 填写"核心发现" -> 更新 `docs/tasks/overview.md` -> 提交 commit
- Batch 6.1 是关键路径——async 就绪后才能跑 LibTest/async 和大量依赖 async 的 LanguageFeatures 测试
- Batch 6.2 理论上可与 6.1 并行（多数特性不依赖 async），但建议 6.1 先行以最大化验证覆盖
- Batch 6.4（沙箱）独立性最高，可在 Phase 6 任何时间点并行执行
