# Compiler Visitor 覆盖率报告

> 生成日期：2026-02-20（更新）
> 基于 commit：`c968dcb`（完成 5 个 visitor 重构后）
> 更新：Phase 4 按需实现的 5 个 visitor 方法已完成（`visitInstanceConstant`、`visitTypeLiteral`、`visitTypeLiteralConstant`、`visitInstantiation`、`visitInstantiationConstant`）

## 概述

编译器当前使用 5 个 Kernel Visitor 类进行 AST 节点派发。本报告列出各 visitor 中未 override 的 `visitXxx` 方法（即 fall through 到 `defaultXxx` 的方法），标识当前未支持的语言特性。

> **注意**：`visitAuxiliaryXxx` 和 `visitInvalidXxx` 为 Kernel 内部节点，正常编译不会出现，下文不列出。`visitAbstractSuperPropertyGet/Set` 和 `visitAbstractSuperMethodInvocation` 同理。

---

## 1. `_ExprCompileVisitor`（Expression 编译）

**文件**：`lib/src/compiler/compiler_expressions.dart`
**Mixin**：`ExpressionVisitorDefaultMixin<(int, ResultLoc)>`
**`defaultExpression`**：throw `UnsupportedError`
**已实现**：38 / 69（+2：visitTypeLiteral, visitInstantiation）

### 未实现方法

| 方法 | 对应语言特性 | 优先级 |
|------|-------------|--------|
| `visitStringConcatenation` | `'Hello $name'` 字符串插值 | **高** |
| `visitListLiteral` | `[1, 2, 3]` 列表字面量 | **高** |
| `visitMapLiteral` | `{'a': 1}` Map 字面量 | **高** |
| `visitSetLiteral` | `{1, 2, 3}` Set 字面量 | 中 |
| `visitRecordLiteral` | `(1, name: 'a')` Record 字面量 | 中 |
| `visitDynamicGet` | `obj.field` dynamic 访问 | 中 |
| `visitDynamicSet` | `obj.field = x` dynamic 赋值 | 中 |
| `visitDynamicInvocation` | `obj.method()` dynamic 调用 | 中 |
| `visitInstanceTearOff` | `obj.method`（不加括号取方法引用） | 中 |
| `visitInstanceGetterInvocation` | `obj.getter()` getter 返回值当函数调用 | 中 |
| `visitFunctionTearOff` | 函数变量 tear-off | 低 |
| `visitConstructorTearOff` | `MyClass.new` | 低 |
| `visitRedirectingFactoryTearOff` | factory 构造 tear-off | 低 |
| `visitTypedefTearOff` | typedef tear-off | 低 |
| `visitSymbolLiteral` | `#symbol` | 低 |
| `visitTypeLiteral` | `int`（作为值传递） | 低 |
| `visitRecordIndexGet` | Record 位置字段访问 `r.$1` | 低 |
| `visitRecordNameGet` | Record 命名字段访问 `r.name` | 低 |
| `visitAwaitExpression` | `await expr` | 低（async 未实现） |
| `visitSwitchExpression` | `switch (x) { ... }` 表达式形式 | 低 |
| `visitPatternAssignment` | `(a, b) = expr` 模式赋值 | 低 |
| `visitInstantiation` | 泛型函数实例化 `foo<int>` | 低 |
| `visitListConcatenation` | 列表 spread `[...a, ...b]` | 低 |
| `visitSetConcatenation` | Set spread `{...a, ...b}` | 低 |
| `visitMapConcatenation` | Map spread `{...a, ...b}` | 低 |
| `visitInstanceCreation` | 内部 const 构造（Kernel 特殊节点） | 低 |
| `visitFileUriExpression` | 调试用 URI 包装 | 低 |
| `visitLoadLibrary` | deferred import 加载 | 低 |
| `visitCheckLibraryIsLoaded` | deferred import 检查 | 低 |

---

## 2. `_StmtCompileVisitor`（Statement 编译）

**文件**：`lib/src/compiler/compiler_statements.dart`
**Mixin**：`StatementVisitorDefaultMixin<void>`
**`defaultStatement`**：throw `UnsupportedError`
**已实现**：16 / 21

### 未实现方法

| 方法 | 对应语言特性 | 优先级 |
|------|-------------|--------|
| `visitForInStatement` | `for (var x in list)` 迭代循环 | **高** |
| `visitContinueSwitchStatement` | switch case fall-through | 中 |
| `visitPatternSwitchStatement` | Dart 3 pattern switch 语句 | 低 |
| `visitIfCaseStatement` | `if (x case Pattern())` | 低 |
| `visitYieldStatement` | `yield` / `yield*`（generator） | 低（async 未实现） |
| `visitAssertBlock` | assert 语句块 | 低 |

---

## 3. `_ConstantCompileVisitor`（常量编译）

**文件**：`lib/src/compiler/compiler_expressions.dart`
**Mixin**：`ConstantVisitorDefaultMixin<(int, ResultLoc)>`
**`defaultConstant`**：throw `UnsupportedError`
**已实现**：9 / 19（+3：visitInstanceConstant, visitTypeLiteralConstant, visitInstantiationConstant）

### 未实现方法

| 方法 | 对应语言特性 | 优先级 |
|------|-------------|--------|
| `visitListConstant` | `const [1, 2, 3]` | **高** |
| `visitMapConstant` | `const {'a': 1}` | **高** |
| `visitInstanceConstant` | `const MyClass(...)` 用户自定义 const 对象 | **高** |
| `visitSetConstant` | `const {1, 2, 3}` | 中 |
| `visitRecordConstant` | `const (1, 'a')` | 中 |
| `visitConstructorTearOffConstant` | `const [MyClass.new]` | 低 |
| `visitRedirectingFactoryTearOffConstant` | factory tear-off 常量 | 低 |
| `visitInstantiationConstant` | 泛型函数实例化常量 | 低 |
| `visitTypeLiteralConstant` | `Type` 常量 | 低 |
| `visitSymbolConstant` | `#symbol` 常量 | 低 |
| `visitTypedefTearOffConstant` | typedef tear-off 常量 | 低 |
| `visitUnevaluatedConstant` | 未求值常量（Kernel 内部） | 低 |

---

## 4. `_InitializerCompileVisitor`（构造器初始化）

**文件**：`lib/src/compiler/compiler_classes.dart`
**Mixin**：`InitializerVisitorDefaultMixin<void>`
**`defaultInitializer`**：throw `UnsupportedError`
**已实现**：5 / 5（排除 Auxiliary/Invalid）

**完备** — 所有实际语言特性的 initializer 类型均已处理：
- `FieldInitializer`、`SuperInitializer`、`RedirectingInitializer`、`LocalInitializer`、`AssertInitializer`

---

## 5. `_ExprTypeInferVisitor`（类型推断）

**文件**：`lib/src/compiler/compiler_types.dart`
**Mixin**：`ExpressionVisitorDefaultMixin<DartType?>`
**`defaultExpression`**：return `null`（安全降级，表示类型未知）
**已实现**：30 / 69

### 未实现但有意义的方法

| 方法 | 应返回的类型 | 影响 |
|------|-------------|------|
| `visitStringConcatenation` | `String` | 字符串插值结果丢失类型信息 |
| `visitListLiteral` | `List<T>` | 容器类型推断缺失 |
| `visitMapLiteral` | `Map<K, V>` | 容器类型推断缺失 |
| `visitSetLiteral` | `Set<T>` | 容器类型推断缺失 |
| `visitRecordLiteral` | `RecordType` | Record 类型推断缺失 |
| `visitFunctionExpression` | `FunctionType` | lambda 类型推断缺失 |
| `visitStaticTearOff` | 函数类型 | tear-off 类型推断缺失 |
| `visitInstanceTearOff` | 函数类型 | tear-off 类型推断缺失 |
| `visitDynamicInvocation` | `dynamic` | dynamic 调用类型推断缺失 |
| `visitAwaitExpression` | unwrap `Future<T>` → `T` | async 类型推断缺失 |
| `visitRethrow` | `Never` | 已在编译 visitor 实现但类型推断缺失 |

> **注意**：由于 `defaultExpression` 返回 `null` 是安全降级，这些缺失不会导致运行时错误。影响仅限于：无法走 int/double 值栈特化路径，退化为通用 ref 栈操作。当对应 expression 编译支持加入后，应同步补充类型推断。

---

## 按 Roadmap Phase 排列的实现顺序

> 对照 `docs/plans/development-roadmap.md`，将每个未实现方法映射到对应 Phase/Batch。
> `_ExprTypeInferVisitor` 为安全降级（返回 null），不单独排期——在对应 Expression 编译实现时顺便补充。

### Phase 4: 高级 OOP + 泛型（当前阶段）— ✅ visitor 方法已全部实现

Phase 4 按需实现的 5 个 visitor 方法已全部完成：

| 方法 | Visitor | 状态 | 说明 |
|------|---------|------|------|
| `visitInstanceConstant` | ConstCompile | ✅ | `const MyClass()` — 内联 NEW_INSTANCE + SET_FIELD 构建 const 对象 |
| `visitTypeLiteral` | ExprCompile | ✅ | Type 作为值 — TypeTemplate → INSTANTIATE_TYPE 管线 |
| `visitTypeLiteralConstant` | ConstCompile | ✅ | const 上下文中的 Type 值 |
| `visitInstantiation` | ExprCompile | ✅ | 泛型函数实例化 `foo<int>` — 生成 bridge thunk 解决 value/ref 栈不匹配 |
| `visitInstantiationConstant` | ConstCompile | ✅ | const 上下文中的泛型函数实例化 |

> **核心发现**：`visitInstantiation` 需要生成 bridge thunk 函数。原因：泛型函数参数 `T x` 在编译时分类为 ref 栈（因 T 是类型参数），但实例化后类型 `int Function(int)` 的调用者会将 `int` 参数发送到 value 栈。thunk 负责 BOX/UNBOX 转换，确保两侧调用约定匹配。

---

### Phase 5: 标准库与互调

Phase 5 是 visitor 缺口的**集中消化期**，对应 Batch 5.3（集合与字符串扩展）。

#### Batch 5.3.1: 集合操作 CREATE_LIST/MAP/SET

| 实现顺序 | 方法 | Visitor | 说明 |
|---------|------|---------|------|
| 1 | `visitListLiteral` | ExprCompile | `[1, 2, 3]` — 最常用集合 |
| 2 | `visitListConstant` | ConstCompile | `const [1, 2]` |
| 3 | `visitMapLiteral` | ExprCompile | `{'a': 1}` |
| 4 | `visitMapConstant` | ConstCompile | `const {'a': 1}` |
| 5 | `visitSetLiteral` | ExprCompile | `{1, 2, 3}` |
| 6 | `visitSetConstant` | ConstCompile | `const {1, 2}` |
| — | TypeInfer 同步 | TypeInfer | `visitListLiteral` → `List<T>` 等 |

#### Batch 5.3.2: 字符串插值 STRING_INTERP

| 实现顺序 | 方法 | Visitor | 说明 |
|---------|------|---------|------|
| 7 | `visitStringConcatenation` | ExprCompile | `'Hello $name'`，需 `toString()` 虚调用 |
| — | TypeInfer 同步 | TypeInfer | `visitStringConcatenation` → `String` |

#### Batch 5.3.3: Spread 操作

| 实现顺序 | 方法 | Visitor | 说明 |
|---------|------|---------|------|
| 8 | `visitListConcatenation` | ExprCompile | `[...a, ...b]` |
| 9 | `visitSetConcatenation` | ExprCompile | `{...a, ...b}` |
| 10 | `visitMapConcatenation` | ExprCompile | `{...a, ...b}` Map 版 |

#### Batch 5.3 附带（for-in 需要 Iterator Bridge）

| 实现顺序 | 方法 | Visitor | 说明 |
|---------|------|---------|------|
| 11 | `visitForInStatement` | StmtCompile | `for (var x in list)` — 需 `Iterator.moveNext()`/`current` |

#### Phase 5 按需补充（co19 测试触发时加入）

| 方法 | Visitor | 说明 |
|------|---------|------|
| `visitDynamicGet` | ExprCompile | dynamic 属性访问——部分 co19 测试使用 `dynamic` 类型 |
| `visitDynamicSet` | ExprCompile | dynamic 赋值 |
| `visitDynamicInvocation` | ExprCompile | dynamic 方法调用 |
| `visitInstanceTearOff` | ExprCompile | `obj.method` 取方法引用——Phase 5 或 6 |
| `visitInstanceGetterInvocation` | ExprCompile | `obj.getter()` getter 返回 callable |
| `visitFunctionTearOff` | ExprCompile | 函数变量自动 tear-off |
| `visitContinueSwitchStatement` | StmtCompile | switch fall-through `continue label` |

> **Dynamic 派发说明**：Kernel 中 `dynamic` 类型的访问/调用产生 `DynamicGet/Set/Invocation` 节点（区别于静态类型已知的 `InstanceGet/Set/Invocation`）。实现方式与 Instance 版类似但无 interfaceTarget，需纯运行时 method lookup。Phase 4/5 co19 中少量测试会触发（如 `Language/Expressions` 中 `dynamic` 相关），碰到时补充。

---

### Phase 6: 异步 + 高级语言特性

#### Batch 6.1: 异步核心

| 方法 | Visitor | 说明 |
|------|---------|------|
| `visitAwaitExpression` | ExprCompile | `await expr` — 需 Frame-as-Continuation 机制 |
| `visitYieldStatement` | StmtCompile | `yield` / `yield*` — sync*/async* generator |

#### Batch 6.2.3: Records

| 方法 | Visitor | 说明 |
|------|---------|------|
| `visitRecordLiteral` | ExprCompile | `(1, name: 'a')` — CREATE_RECORD 指令 |
| `visitRecordIndexGet` | ExprCompile | `r.$1` 位置字段 |
| `visitRecordNameGet` | ExprCompile | `r.name` 命名字段 |
| `visitRecordConstant` | ConstCompile | `const (1, 'a')` |

#### Batch 6.2.4: Pattern matching

| 方法 | Visitor | 说明 |
|------|---------|------|
| `visitPatternSwitchStatement` | StmtCompile | Dart 3 pattern switch 语句 |
| `visitSwitchExpression` | ExprCompile | `switch (x) { ... }` 表达式形式 |
| `visitPatternAssignment` | ExprCompile | `(a, b) = expr` 解构赋值 |
| `visitIfCaseStatement` | StmtCompile | `if (x case Pattern())` |

#### Batch 6.2.5: Constructor tearoffs

| 方法 | Visitor | 说明 |
|------|---------|------|
| `visitConstructorTearOff` | ExprCompile | `MyClass.new` |
| `visitRedirectingFactoryTearOff` | ExprCompile | factory 构造 tear-off |
| `visitTypedefTearOff` | ExprCompile | typedef tear-off |
| `visitConstructorTearOffConstant` | ConstCompile | const 上下文 |
| `visitRedirectingFactoryTearOffConstant` | ConstCompile | const 上下文 |
| `visitTypedefTearOffConstant` | ConstCompile | const 上下文 |

---

### 不排期（边缘场景 / Kernel 内部）

| 方法 | Visitor | 说明 |
|------|---------|------|
| `visitSymbolLiteral` | ExprCompile | `#symbol` — dart:mirrors 相关，dartic 不支持 |
| `visitSymbolConstant` | ConstCompile | 同上 |
| `visitInstanceCreation` | ExprCompile | Kernel 内部 const 构造节点，正常代码不产生 |
| `visitFileUriExpression` | ExprCompile | Kernel 调试包装节点 |
| `visitLoadLibrary` | ExprCompile | deferred import — 超出 dartic 范围 |
| `visitCheckLibraryIsLoaded` | ExprCompile | 同上 |
| `visitUnevaluatedConstant` | ConstCompile | Kernel 内部未求值节点 |
| `visitAssertBlock` | StmtCompile | assert 语句块——极少见，当前 assert 已通过 `visitAssertStatement` 处理 |

---

## 实现量汇总

| Phase | 新增 visitor 方法数 | 涉及 Visitor |
|-------|-------------------|-------------|
| **Phase 4** | 5 ✅ 已完成 | ExprCompile ×2, ConstCompile ×3 |
| **Phase 5** | ~17（集中） | ExprCompile ×10, ConstCompile ×3, StmtCompile ×1, TypeInfer ×跟随 |
| **Phase 6** | ~15 | ExprCompile ×8, ConstCompile ×4, StmtCompile ×3 |
| 不排期 | 8 | — |
| **合计** | ~37 / 45 有意义方法（已完成 5） | — |
