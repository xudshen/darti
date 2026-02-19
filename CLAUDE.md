## 文档导航

| 先读 | 文件 | 内容 |
|------|------|------|
| 1 | `ARCHITECTURE.md` | 架构设计、核心理念、关键决策 |
| 2 | `docs/design/` | 各包详细设计 |
| 3 | `docs/tasks/overview.md` | 任务总索引（各阶段进度 + 待做方案链接） |

使用指南在 `docs/guides/`，调研存档在 `docs/research/`。

## 归档区（不要读）

`archive/` 目录是已完成阶段的归档（包括 POC 代码和相关文档）。**做方案或执行任务时不要读取 `archive/` 下的任何文件**——那些是历史产物，不反映当前设计。如需参考历史决策，读设计文档 `docs/design/` 即可。

## 文件去向

**写方案（writing-plan）注意**：
- 方案产出放 `docs/plans/`，从方案拆出的执行记录放 `docs/tasks/<topic>/`
- 方案中的决策用"决策记录"表格（问题 / 决策 / 理由），留空的决策标注"先试后决定"并说明何时回填
- Task 文件中每个 task 必须写明：依赖关系、产出文件列表、TDD 步骤
- 在合适的Task位置添加commit要求
- 在合适的Task位置添加更新文档的要求
- 方案写完后不要直接开始执行——先让用户审阅确认

生成新文档时，按产出类型放到对应目录：

| 产出类型 | 目录 | 说明 |
|---------|------|------|
| brainstorm 方案 | `docs/plans/` | 大纲/设计方案，写完基本不动 |
| 任务进度 | `docs/tasks/<phase>/` | 从方案拆出的 checkbox 执行记录 |
| 包设计文档 | `docs/design/` | 包级 API/架构设计 |
| 调研报告 | `docs/research/` | 技术调研存档 |
| 使用指南 | `docs/guides/` | 教程和参考 |

## 开发流程

- 采用 **TDD**。执行协议：读设计文档 → 先写测试 → 最小实现 → analyze → test → 重构。
- 进度更新顺序：先更新 `docs/tasks/xxx.md` checkbox，再更新 `overview.md` 汇总表。
- **每完成一个 batch（通常 3 个 task）必须立即更新**，不要攒到最后。
- 关键发现需要及时更新到文档。

## 关键陷阱

- **排查不动时加日志** — 静态读代码超过 2 轮没定位到根因，立刻在关键路径（guard 条件、async 衔接点、回调触发点）加 `debugPrint`，用实际运行数据定位，不要靠猜
- **双栈 coercion：`_compileExpression` 返回的 `ResultLoc` 不能随意丢弃** — 编译器采用 value/ref 双栈架构，`_compileExpression` 返回 `(reg, ResultLoc)` 表示结果所在栈。在以下消费端必须检查 loc 并做 coercion（unbox 或 box）：条件跳转（if/while/for/do/assert/not/logical/conditional）、函数参数传递、变量赋值、接收者表达式（虚调用/getter/setter 分发）。只有**确定结果一定在 ref 栈**的场景（闭包、常量 case 表达式）才可以安全丢弃 loc

## 初始化

首次 clone 后需要初始化 vendor 依赖（`vendor/` 在 `.gitignore` 中，不随仓库分发）：

```bash
git clone --depth 1 --filter=blob:none --branch 3.10.7 \
  https://github.com/dart-lang/sdk.git vendor/dart-sdk
git clone --depth 1 --filter=blob:none \
  https://github.com/dart-lang/co19.git vendor/co19
fvm dart pub get
```

| vendor 目录 | 用途 |
|-------------|------|
| `vendor/dart-sdk/pkg/kernel` | `pubspec.yaml` 中 `kernel` 包的本地依赖 |
| `vendor/co19` | Dart 语言与标准库一致性测试集 |

## 命令

```bash
fvm dart *                 # Pure Dart 包
```
