# Phase 1: 最小可运行管线

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 能编译并执行 `int add(int a, int b) => a + b;` 级别的 Dart 函数

**Architecture:** 按设计文档依赖拓扑搭建：Ch1 ISA（指令编解码与常量池）→ Ch2 Object Model（三栈 + 对象表示）→ Ch3 Execution Engine（分发循环）→ Ch5 Compiler（Kernel→字节码）。Batch 1.5 补充模块格式、异常处理表等被遗漏的关键组件。

**Tech Stack:** Pure Dart, `package:kernel`, `package:test`

---

## 设计文档依赖

| Batch | 主要设计章节 | 关键参考节 |
|-------|-------------|-----------|
| 1.1 | Ch1 字节码 ISA | 指令编码格式、操作码分类、四分区常量池、WIDE 前缀 |
| 1.2 | Ch2 内存模型 | 三栈模型、StackKind、DarticObject、DarticClassInfo、DarticFuncProto、DarticFrame |
| 1.3 | Ch3 执行引擎 | 分发循环、调用约定、IC 分发、异常分发 |
| 1.4 | Ch5 编译器 | 编译管线、寄存器分配、表达式/语句编译、Kernel 加载 |
| 1.5 | Ch1 + Ch2 + Ch3 + Ch5 | .darticb 格式、异常处理表、StackKind 分类、IC 表初始化 |

## Batch 索引

| Batch | 文件 | Task 数 | 依赖 |
|-------|------|---------|------|
| [1.1 字节码基础设施](batch-1.1-bytecode-infra.md) | 4 | 无 |
| [1.2 三栈与对象模型](batch-1.2-stack-object-model.md) | 4 | 1.1 |
| [1.3 分发循环](batch-1.3-dispatch-loop.md) | 6 | 1.1, 1.2 |
| [1.4 最小编译器](batch-1.4-minimal-compiler.md) | 6 | 1.1, 1.2, 1.3 |
| [1.5 模块格式与运行时补全](batch-1.5-module-format.md) | 6 | 1.1, 1.2, 1.3, 1.4 |

## 里程碑验证

```dart
// 能编译并执行这段代码，返回正确结果
int add(int a, int b) => a + b;
int main() => add(1, 2); // => 3
```

- [ ] 手工构造字节码能在分发循环中正确执行
- [ ] 编译器能将简单 Kernel AST 编译为字节码
- [ ] 编译 → 序列化 → 反序列化 → 执行 roundtrip 通过

## 执行节奏

- 每个 Task 遵循 TDD：读设计文档 → 写测试 → 最小实现 → `fvm dart analyze` → `fvm dart test` → 重构
- 每完成一个 Batch 勾选 checkbox → 填写"核心发现" → 更新 `docs/tasks/overview.md` -> 提交 commit
