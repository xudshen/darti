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

## Phase 2-6: 待规划

详见 [`docs/plans/development-roadmap.md`](../plans/development-roadmap.md)
