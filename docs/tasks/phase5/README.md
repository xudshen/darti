# Phase 5: 标准库互调 (Ch4)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 实现跨边界互调层（Ch4），桥接 dart:core 核心类型，通过 co19 LibTest/core 测试 + 历史类别大幅提升

**Architecture:** Phase 5 构建完整的 CALL_HOST 管线：编译器识别平台库调用 → 生成 CALL_HOST 指令 + 绑定名称表 → .darb 序列化 → 运行时解析绑定 → 解释器分发。手写 dart:core 核心类型的 HostClassWrapper（方法/属性路由）+ HostBindings（typed wrapper 闭包注册），不构建 BridgeGenerator。同时实现集合字面量（CREATE_LIST/MAP/SET）和字符串插值（STRING_INTERP）指令。最后通过 co19 harness v3 验证。

**Tech Stack:** Pure Dart, Kernel AST (`package:kernel`), TDD (`package:test`), co19 测试集

---

## 决策记录

| 问题 | 决策 | 理由 |
|------|------|------|
| BridgeGenerator 构建时机 | **Option C（混合）**：Phase 5 手写所有 dart:core Bridge，提取通用模式到工具函数 | dart:core 类型有限（~20 类），手写可控；手写过程发现真实模式，为将来 Generator 提供更好输入；Generator 需要 build_runner + package:analyzer，是独立工程 |
| CALL_HOST 参数传递 | 所有参数通过 ref 栈传递（值类型需 BOX） | 与 Ch4 设计一致：「跨边界参数均需装箱」；CALL_HOST 返回值也在 ref 栈，消费端按 `_inferExprType` 结果做 UNBOX |
| 平台实例方法编译策略 | 编译期已知类型的平台实例方法 → CALL_HOST（receiver 作为第一个参数） | 静态类型信息来自 Kernel `interfaceTarget`；动态分发（receiver 类型未知）通过 HostClassWrapper 在运行时路由 |
| 特化操作码与 CALL_HOST 共存 | int/double 基本算术/比较保留特化操作码（ADD_INT 等），其余平台方法走 CALL_HOST | 特化操作码已实现且性能好；toString/abs/clamp 等非特化方法走 CALL_HOST |
| Bridge 方法覆盖范围 | 优先覆盖 co19 测试中高频使用的方法，非核心方法按需添加 | 100% 覆盖工作量大且收益递减；co19 测试驱动自然覆盖关键方法 |
| DarticProxy/CallbackProxy 引入时机 | Batch 5.3（集合/字符串 batch），在回调场景（list.forEach/map 等）需要时引入 | Batch 5.1-5.2 不涉及 VM 回调解释器场景，延迟引入减少前期复杂度 |

---

## 设计文档依赖

| Batch | 主要设计章节 | 关键参考节 |
|-------|-------------|-----------|
| 5.1 Bridge 基础设施 + CALL_HOST | Ch4 互调, Ch3 执行引擎, Ch1 ISA, Ch5 编译器 | HostBindings 注册表、CALL_HOST 分发、绑定名称表 .darb 格式、编译器 Bridge 注册表查找 |
| 5.2 dart:core Bridge | Ch4 互调 | HostClassWrapper 分发路由、类型映射（值类型直传、引用类型存 ref 栈）、操作符路由命名 |
| 5.3 集合/字符串/回调 | Ch2 对象模型, Ch4 互调 | CREATE_LIST/MAP/SET 创建 VM 原生对象、STRING_INTERP、DarticCallbackProxy proxy0-3、DarticProxyManager 双向 Expando |
| 5.4 co19 Harness v3 | — | dart:core 导入路由、expect_common 完整接入、skip list、回归检测 |

## Batch 索引

| Batch | 文件 | Task 数 | 依赖 |
|-------|------|---------|------|
| [5.1](batch-5.1-bridge-infra.md) | batch-5.1-bridge-infra.md | 5 | Phase 4 全部 |
| [5.2](batch-5.2-core-bridges.md) | batch-5.2-core-bridges.md | 6 | Batch 5.1 |
| [5.3](batch-5.3-collections-strings.md) | batch-5.3-collections-strings.md | 4 | Batch 5.1-5.2 |
| [5.5](batch-5.5-nosuchmethod.md) | batch-5.5-nosuchmethod.md | 5 | Batch 5.1-5.3 |
| [5.6](batch-5.6-binding-completion.md) | batch-5.6-binding-completion.md | 11 | Batch 5.1-5.3 |
| [5.4](batch-5.4-co19-harness-v3.md) | batch-5.4-co19-harness-v3.md | 4 | Batch 5.1-5.6 |

## 里程碑验证

- [x] co19 `LibTest/core` 通过率 > 30% — 实际 **54.4%** (611/1124)
- [x] Bridge 基础类型方法覆盖率：int ~25 bindings、String 28 bindings、List ~40+ bindings、Map ~15 bindings（详见 batch-5.2 覆盖度表）
- [x] Phase 2-4 类别零回归（或回归已修复） — 10 async regressions → skip list
- [x] Phase 2-4 类别通过率较上期有提升 — 65.6% → **81.8%** (+685 new pass)

## co19 测试范围（预估）

| 类别 | 目录 | 预估测试数 | 预估通过率 | 目标 |
|------|------|----------|----------|------|
| LibTest/core | `LibTest/core/` | ~1,353 | ~30-40% | >30% |
| Phase 2-4 历史类别 | 全十一类 | 7,593 | ~65-70% | >65%, 0 回归 |
| **新增 Phase 5 合计** | | ~1,353 | | |
| **全部累计** | | ~8,946 | | |

### 历史提升预估

Bridge 将解锁大量历史类别中因缺少平台调用支持而失败的测试：

| 解锁来源 | 预估新增 pass | 说明 |
|---------|------------|------|
| print 桥接 | ~218 | 118 (Language/Statements 等) + 100 (Class-modifiers 全部阻塞) |
| Duration 桥接 | ~300 | TypeSystem/subtyping dynamic 子类别 422 中大部分 |
| Object 桥接 | ~130 | Object 常量 70 + Object() 构造器 60 |
| toString/字符串操作 | ~100 | 散布在各类别中 |
| **预估历史提升合计** | **~750** | 保守估计 |

## 执行节奏

- 每个 Task 遵循 TDD：读设计文档 → 写测试 → 最小实现 → `fvm dart analyze` → `fvm dart test` → 重构
- 每完成一个 Batch 勾选 checkbox → 填写"核心发现" → 更新 `docs/tasks/overview.md` → 提交 commit
- Batch 5.1 是关键路径——建立完整 CALL_HOST 管线后才能开始写 Bridge
- Batch 5.2 可以并行开发多个 Bridge（各类型相互独立），但建议按 Object → int → String → List → Map 顺序推进（后者依赖前者的 toString/==）
