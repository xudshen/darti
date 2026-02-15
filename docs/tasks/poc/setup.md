# POC 基础设施

> 方案来源: `docs/plans/2026-02-15-poc-implementation.md` Task 1

## 任务

### Task 1: 工作区与 Package 骨架

**依赖:** 无
**产出文件:**
- `pubspec.yaml`（修改，添加 workspace）
- `packages/poc_kernel/pubspec.yaml` + `lib/poc_kernel.dart`
- `packages/poc_bench/pubspec.yaml` + `lib/poc_bench.dart`
- `packages/poc_bridge/pubspec.yaml` + `lib/poc_bridge.dart`

**TDD 步骤:**
- [x] 修改 `pubspec.yaml`（添加 workspace）
- [x] 创建 `packages/poc_kernel/pubspec.yaml` + lib 入口
- [x] 创建 `packages/poc_bench/pubspec.yaml` + lib 入口
- [x] 创建 `packages/poc_bridge/pubspec.yaml` + lib 入口
- [x] 运行 `dart pub get` 验证依赖解析
- [x] **Commit** `441e660`

## 实施记录

### 依赖策略调整

计划中 `package:kernel` 使用 git 依赖，实际改为 **vendor 浅克隆 + path 依赖**：

- `dart-lang/sdk` 仓库过大，git 依赖 `pub get` 极慢
- 解决方案：`git clone --depth=1 --sparse` 到 `vendor/dart-sdk/`，仅检出 `pkg/kernel` 和 `pkg/_fe_analyzer_shared`
- `poc_kernel/pubspec.yaml` 用相对 path 引用：`../../vendor/dart-sdk/pkg/kernel`
- `_fe_analyzer_shared` 不做 `dependency_overrides`（会与 `analyzer` 包冲突），让其从 pub.dev 解析
