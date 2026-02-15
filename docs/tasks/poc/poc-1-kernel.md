# POC-1: Kernel 加载与遍历

> 方案来源: `docs/plans/2026-02-15-poc-implementation.md` Task 2–6

## 目标

验证 package:kernel 能否加载 .dill 并高效遍历 AST，验证 StackKind 分类和脱糖假设。

## 任务

### Task 2: 编译测试用 .dill 文件

**依赖:** Task 1
**产出文件:**
- `packages/poc_kernel/test/fixtures/simple.dart`
- `packages/poc_kernel/test/fixtures/generics.dart`
- `packages/poc_kernel/test/fixtures/async_closures.dart`
- `packages/poc_kernel/tool/compile_fixtures.sh`
- `packages/poc_kernel/test/fixtures/*.dill`（生成产物）

**TDD 步骤:**
- [x] 创建 3 个 fixture 源文件
- [x] 创建编译脚本 `tool/compile_fixtures.sh`
- [x] 运行脚本生成 .dill 文件
- [x] **Commit** `cc0190f`

### Task 3: KernelWalker 加载与遍历

**依赖:** Task 2
**产出文件:**
- `packages/poc_kernel/lib/src/kernel_walker.dart`
- `packages/poc_kernel/test/kernel_walker_test.dart`

**TDD 步骤:**
- [x] 写失败测试 `kernel_walker_test.dart`
- [x] 运行验证测试失败
- [x] 实现 `kernel_walker.dart`
- [x] 运行验证测试通过
- [x] **Commit** `ab9a71d`（fixtures + KernelWalker）

### Task 4: TypeClassifier StackKind 分类

**依赖:** Task 3
**产出文件:**
- `packages/poc_kernel/lib/src/type_classifier.dart`
- `packages/poc_kernel/test/type_classifier_test.dart`

**TDD 步骤:**
- [x] 写失败测试 `type_classifier_test.dart`
- [x] 运行验证测试失败
- [x] 实现 `type_classifier.dart`
- [x] 运行验证测试通过

### Task 5: DesugarChecker 脱糖验证

**依赖:** Task 3
**产出文件:**
- `packages/poc_kernel/lib/src/desugar_checker.dart`
- `packages/poc_kernel/test/desugar_checker_test.dart`

**TDD 步骤:**
- [x] 写失败测试 `desugar_checker_test.dart`
- [x] 运行验证测试失败
- [x] 实现 `desugar_checker.dart`
- [x] 运行验证测试通过
- [x] **Commit** `cfbb1a3`（TypeClassifier + DesugarChecker）

### Task 6: CLI 入口与综合报告

**依赖:** Task 3, 4, 5
**产出文件:**
- `packages/poc_kernel/bin/explore.dart`
- `packages/poc_kernel/lib/poc_kernel.dart`（修改，添加导出）

**TDD 步骤:**
- [x] 创建 `bin/explore.dart` CLI
- [x] 更新 `lib/poc_kernel.dart` 导出
- [x] 对所有 fixture 运行 CLI 验证输出
- [x] **Commit** `1966479`（POC-1 完成）

## 关键发现

### 1. `--no-link-platform` .dill 的未链接引用

`dart compile kernel --no-link-platform` 生成的 .dill 不包含 dart:core/dart:async 的 AST 节点。所有指向平台类型的 `Reference` 未绑定（`node == null`）。

**影响：**
- `InterfaceType.classNode` / `Supertype.classNode` 直接访问会崩溃
- `Reference.asClass` / `asProcedure` / `asMember` 在未绑定时 **`throw` 裸字符串**（非标准异常类型）
- `RecursiveVisitor` 的 `node.visitChildren(this)` 会触发深层引用解析崩溃

**解决模式：**
- 类型名称获取：通过 `Reference.node` 检查是否绑定，回退到 `Reference.canonicalName.name`
- 类型分类（StackKind）：通过 canonical name 字符串匹配（`'int'`/`'double'`/`'bool'`），不依赖 `CoreTypes` 对象相等
- AST 遍历：`try { node.visitChildren(this); } catch (e)` + 字符串匹配 `'is not bound to an AST node'`

### 2. `package:kernel` API 版本差异 (SDK 3.10.7)

| 计划假设 | 实际 API |
|---------|---------|
| `RecursiveVisitor<void>` | `RecursiveVisitor`（无类型参数） |
| `super.visitXxx(node)` 可调 | mixin 链导致 `super` 找不到方法 |
| `InterfaceType.classNode.name` | 需用 `classReference` + `Reference.canonicalName` |
| `cls.superclass?.name` | 需用 `cls.supertype?.className`（`Reference` 类型） |
| `CoreTypes(component)` 可用 | `--no-link-platform` 下不可用，dart:core 类未链接 |

### 3. CFE 脱糖确认

| 源码语法 | Kernel AST 表示 | 是否脱糖 |
|---------|----------------|---------|
| Cascade `..` | `Let` + `BlockExpression` | ✅ 已脱糖 |
| `await expr` | `AwaitExpression` | ❌ 保留 |
| `for-in` | 已转为 while 等 | ✅ 已脱糖 |
| Lambda `(e) => ...` | `FunctionExpression` | ❌ 保留 |

### 4. .dill 文件大小

| Fixture | 大小 | 说明 |
|---------|------|------|
| simple.dill | 912 B | fibonacci + main |
| generics.dill | 1,424 B | Box<T> 泛型类 |
| async_closures.dill | 1,464 B | async + cascade + lambda |

`--no-link-platform` 极大减小文件体积，仅包含用户代码 AST。

### 5. StackKind 分类数据

| Fixture | value 数 | ref 数 | value 比例 |
|---------|---------|--------|-----------|
| simple (fibonacci) | 2 | 1 | 66.7% |
| generics (Box<T>) | 0 | 5 | 0.0% |
| async_closures | 0 | 2 | 0.0% |

int 密集型代码（fibonacci）的 value 比例高，验证了双视图栈对数值运算的优化潜力。泛型/async 代码全部走 ref 栈，符合预期。
