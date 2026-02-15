# 任务总索引

## 当前阶段: POC 验证

> 方案: `docs/plans/2026-02-15-poc-tasks-design.md`
> 实现计划: `docs/plans/2026-02-15-poc-implementation.md`

### 进度

| POC | 说明 | 任务文件 | 状态 |
|-----|------|----------|------|
| 基础 | 工作区与 Package 骨架 | `poc/setup.md` | ✅ 完成 |
| POC-1 | Kernel 加载与遍历 | `poc/poc-1-kernel.md` | ✅ 完成 |
| POC-2 | 双视图值栈性能 | `poc/poc-2-bench.md` | ✅ 完成 |
| POC-3 | Bridge / 互调机制 | `poc/poc-3-bridge.md` | ✅ 完成 |
| POC-4 | 端到端最小原型 | `poc/poc-4-e2e.md` | ✅ 完成 |

### 依赖关系

```
setup ──► POC-1 ──┐
          POC-2 ──┤──► POC-4
          POC-3 ──┘
```

POC-1/2/3 可并行，POC-4 依赖前三者的产出。
