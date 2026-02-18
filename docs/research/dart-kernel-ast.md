# Dart Kernel AST 完整定义调研

> **来源**: `vendor/dart-sdk/pkg/kernel` (Dart SDK 3.10.7)
> **目的**: 列举 Kernel AST 全部节点/枚举/标志位，用于校验设计文档覆盖度
> **日期**: 2026-02-18

---

## 目录

1. [基础类层次](#1-基础类层次)
2. [Expression 节点](#2-expression-节点)
3. [Statement 节点](#3-statement-节点)
4. [Pattern 节点](#4-pattern-节点)
5. [Initializer 节点](#5-initializer-节点)
6. [Member 节点](#6-member-节点)
7. [Declaration 节点](#7-declaration-节点)
8. [DartType 节点](#8-darttype-节点)
9. [Constant 节点](#9-constant-节点)
10. [FunctionNode 与参数表示](#10-functionnode-与参数表示)
11. [Reference 与 CanonicalName 体系](#11-reference-与-canonicalname-体系)
12. [枚举定义](#12-枚举定义)
13. [节点标志位 (Flags)](#13-节点标志位-flags)
14. [Visitor 模式](#14-visitor-模式)
15. [源文件索引](#15-源文件索引)
16. [与设计文档的交叉引用](#16-与设计文档的交叉引用)

---

## 1. 基础类层次

```
Node (abstract)                          ← 所有 AST 节点的根
├── TreeNode (abstract)                  ← 可变 AST 节点，有 parent 指针
│   ├── NamedNode (abstract)             ← 有 CanonicalName 引用
│   ├── FileUriNode (abstract)           ← 有源文件 URI
│   ├── Annotatable (abstract)           ← 可带 annotation
│   ├── GenericDeclaration (sealed)      ← 带 typeParameters 的声明
│   └── GenericFunction (sealed)         ← 带 typeParameters 的函数
├── Constant (sealed)                    ← 编译期常量 (DAG 结构，非树)
├── DartType (sealed)                    ← 类型节点
└── Name (abstract)                      ← 标识符名
    ├── _PublicName
    └── _PrivateName
```

| 基类 | 定义文件 | 职责 |
|------|---------|------|
| `Node` | `src/ast/misc.dart` | accept/visitChildren 接口 |
| `TreeNode` | `src/ast/misc.dart` | parent 指针 + transformChildren |
| `NamedNode` | `src/ast/misc.dart` | Reference 绑定 |
| `GenericDeclaration` | `src/ast/misc.dart` | typeParameters 列表 |
| `GenericFunction` | `src/ast/misc.dart` | extends GenericDeclaration，函数特化 |

---

## 2. Expression 节点

> `sealed class Expression extends TreeNode`
> 定义文件: `src/ast/expressions.dart`

### 2.1 抽象基类

| 类名 | 说明 |
|------|------|
| `AuxiliaryExpression` | 扩展点（abstract） |
| `InvocationExpression` | 调用类表达式基类 |
| `InstanceInvocationExpression` | 实例调用基类 (extends InvocationExpression) |
| `BasicLiteral` | 字面量基类 |
| `LocalFunction` | 局部函数基类 (implements GenericFunction) |

### 2.2 变量访问

| 节点 | 说明 |
|------|------|
| `VariableGet` | 读取局部变量 |
| `VariableSet` | 写入局部变量 |

### 2.3 Record 字段访问

| 节点 | 说明 |
|------|------|
| `RecordIndexGet` | 按位置索引访问 Record 字段 |
| `RecordNameGet` | 按名称访问 Record 字段 |

### 2.4 Dynamic 访问

| 节点 | 说明 |
|------|------|
| `DynamicGet` | dynamic 类型属性读取 |
| `DynamicSet` | dynamic 类型属性写入 |
| `DynamicInvocation` | dynamic 类型方法调用 (extends InstanceInvocationExpression) |

### 2.5 Instance 成员访问

| 节点 | 说明 |
|------|------|
| `InstanceGet` | 实例属性读取 |
| `InstanceSet` | 实例属性写入 |
| `InstanceTearOff` | 实例方法撕裂 |
| `InstanceInvocation` | 实例方法调用 |
| `InstanceGetterInvocation` | getter 返回值的调用 |

### 2.6 Tear-off 表达式

| 节点 | 说明 |
|------|------|
| `FunctionTearOff` | 函数撕裂（直接调用） |
| `StaticTearOff` | 静态方法撕裂 |
| `ConstructorTearOff` | 构造函数撕裂 |
| `RedirectingFactoryTearOff` | 重定向工厂撕裂 |
| `TypedefTearOff` | typedef 撕裂 |

### 2.7 Super 成员访问

| 节点 | 说明 |
|------|------|
| `AbstractSuperPropertyGet` | 抽象 super 属性读取 |
| `AbstractSuperPropertySet` | 抽象 super 属性写入 |
| `SuperPropertyGet` | super 属性读取 |
| `SuperPropertySet` | super 属性写入 |
| `AbstractSuperMethodInvocation` | 抽象 super 方法调用 |
| `SuperMethodInvocation` | super 方法调用 |

### 2.8 Static 访问

| 节点 | 说明 |
|------|------|
| `StaticGet` | 静态字段/top-level 变量读取 |
| `StaticSet` | 静态字段/top-level 变量写入 |
| `StaticInvocation` | 静态方法/top-level 函数调用 |

### 2.9 调用表达式

| 节点 | 说明 |
|------|------|
| `LocalFunctionInvocation` | 局部函数调用 |
| `FunctionInvocation` | 函数类型调用 (call()) |
| `EqualsNull` | `== null` 优化节点 |
| `EqualsCall` | `==` 方法调用 |
| `ConstructorInvocation` | 构造函数调用 |

### 2.10 运算与控制流

| 节点 | 说明 |
|------|------|
| `InvalidExpression` | 编译错误占位 |
| `Not` | 逻辑非 `!` |
| `NullCheck` | 非空断言 `!` (后缀) |
| `LogicalExpression` | `&&` / `||` |
| `ConditionalExpression` | 三元 `a ? b : c` |
| `Throw` | throw 表达式 |
| `Rethrow` | rethrow 表达式 |
| `AwaitExpression` | await 表达式 |

### 2.11 字面量

| 节点 | 基类 | 说明 |
|------|------|------|
| `StringLiteral` | BasicLiteral | 字符串 |
| `IntLiteral` | BasicLiteral | 整数 |
| `DoubleLiteral` | BasicLiteral | 浮点数 |
| `BoolLiteral` | BasicLiteral | 布尔值 |
| `NullLiteral` | BasicLiteral | null |
| `SymbolLiteral` | Expression | #symbol |
| `TypeLiteral` | Expression | 类型字面量 (如 `int`) |
| `ThisExpression` | Expression | this |
| `ConstantExpression` | Expression | 引用 Constant 节点 |

### 2.12 集合字面量

| 节点 | 说明 |
|------|------|
| `ListLiteral` | List 字面量 |
| `SetLiteral` | Set 字面量 |
| `MapLiteral` | Map 字面量 |
| `RecordLiteral` | Record 字面量 |
| `ListConcatenation` | List 拼接（展开） |
| `SetConcatenation` | Set 拼接 |
| `MapConcatenation` | Map 拼接 |

### 2.13 类型操作

| 节点 | 说明 |
|------|------|
| `IsExpression` | `is` 类型检查 |
| `AsExpression` | `as` 类型转换 |

### 2.14 其他表达式

| 节点 | 说明 |
|------|------|
| `InstanceCreation` | 对象创建（const 上下文） |
| `Instantiation` | 泛型函数实例化 |
| `Let` | CFE 内部绑定表达式 |
| `BlockExpression` | 块表达式（Statement + Expression） |
| `FunctionExpression` | 匿名函数 / lambda (implements LocalFunction) |
| `StringConcatenation` | 字符串插值拼接 |
| `LoadLibrary` | 延迟加载库 |
| `CheckLibraryIsLoaded` | 检查延迟库加载状态 |
| `FileUriExpression` | 带文件 URI 的表达式包装 |
| `SwitchExpression` | switch 表达式 (Dart 3) |
| `PatternAssignment` | 模式赋值 |

### 2.15 辅助节点（非 Expression）

| 节点 | 说明 |
|------|------|
| `Arguments` | 函数调用参数 (positional + named + types) |
| `NamedExpression` | 命名参数 |
| `MapLiteralEntry` | Map 字面量键值对 |

---

## 3. Statement 节点

> `sealed class Statement extends TreeNode`
> 定义文件: `src/ast/statements.dart`

### 3.1 抽象基类

| 类名 | 说明 |
|------|------|
| `AuxiliaryStatement` | 扩展点（abstract） |
| `LoopStatement` | 循环语句接口 (abstract interface) |

### 3.2 基本语句

| 节点 | 说明 |
|------|------|
| `ExpressionStatement` | 表达式语句 |
| `Block` | 语句块 `{ ... }` |
| `AssertBlock` | 断言块 |
| `EmptyStatement` | 空语句 `;` |
| `AssertStatement` | assert 语句 |

### 3.3 标签与跳转

| 节点 | 说明 |
|------|------|
| `LabeledStatement` | 带标签语句 |
| `BreakStatement` | break（引用 LabeledStatement） |
| `ContinueSwitchStatement` | continue to switch case |

### 3.4 循环

| 节点 | implements | 说明 |
|------|-----------|------|
| `WhileStatement` | LoopStatement | while 循环 |
| `DoStatement` | LoopStatement | do-while 循环 |
| `ForStatement` | LoopStatement | for 循环 |
| `ForInStatement` | LoopStatement | for-in 循环 |

### 3.5 条件

| 节点 | 说明 |
|------|------|
| `IfStatement` | if-else 语句 |
| `IfCaseStatement` | if-case 模式匹配语句 (Dart 3) |

### 3.6 Switch

| 节点 | 说明 |
|------|------|
| `SwitchStatement` | 传统 switch 语句 |
| `PatternSwitchStatement` | 模式匹配 switch (Dart 3, implements SwitchStatement) |
| `SwitchCase` | switch case 分支 |
| `PatternSwitchCase` | 模式 switch case (implements SwitchCase) |

### 3.7 异常处理

| 节点 | 说明 |
|------|------|
| `TryCatch` | try-catch 语句 |
| `TryFinally` | try-finally 语句 |
| `Catch` | catch 子句（非 Statement，是 TreeNode） |

### 3.8 返回与生成器

| 节点 | 说明 |
|------|------|
| `ReturnStatement` | return 语句 |
| `YieldStatement` | yield / yield* 语句 |

### 3.9 声明语句

| 节点 | 说明 |
|------|------|
| `VariableDeclaration` | 变量声明 (implements Annotatable) |
| `FunctionDeclaration` | 局部函数声明 (implements LocalFunction) |
| `PatternVariableDeclaration` | 模式变量声明 (Dart 3) |

---

## 4. Pattern 节点

> `sealed class Pattern extends TreeNode`
> 定义文件: `src/ast/patterns.dart`

| 节点 | 说明 |
|------|------|
| `ConstantPattern` | 常量模式 |
| `AndPattern` | 模式与 (`&&`) |
| `OrPattern` | 模式或 (`\|\|`) |
| `CastPattern` | 类型转换模式 (`as Type`) |
| `NullAssertPattern` | 非空断言模式 (`!`) |
| `NullCheckPattern` | 空检查模式 (`?`) |
| `ListPattern` | 列表模式 |
| `MapPattern` | Map 模式 |
| `RecordPattern` | Record 模式 |
| `ObjectPattern` | 对象模式 |
| `NamedPattern` | 命名模式 (Record 字段) |
| `RelationalPattern` | 关系运算模式 (`< 10`, `== 'a'`) |
| `WildcardPattern` | 通配符 `_` |
| `VariablePattern` | 变量绑定模式 |
| `AssignedVariablePattern` | 已存在变量赋值模式 |
| `RestPattern` | 剩余模式 (`...`) |
| `InvalidPattern` | 错误占位 |

辅助节点:

| 节点 | 说明 |
|------|------|
| `MapPatternEntry` | Map 模式键值对 |
| `MapPatternRestEntry` | Map 模式剩余条目 |
| `PatternGuard` | 模式守卫 (`when expr`) |
| `SwitchExpressionCase` | switch 表达式 case |

---

## 5. Initializer 节点

> `sealed class Initializer extends TreeNode`
> 定义文件: `src/ast/initializers.dart`

| 节点 | 说明 |
|------|------|
| `InvalidInitializer` | 错误占位 |
| `FieldInitializer` | 字段初始化 `this.x = expr` |
| `SuperInitializer` | super 构造函数调用 |
| `RedirectingInitializer` | 重定向构造函数 `this(...)` |
| `LocalInitializer` | 局部变量初始化（初始化列表中的 let） |
| `AssertInitializer` | 初始化列表中的 assert |
| `AuxiliaryInitializer` | 扩展点（abstract） |

---

## 6. Member 节点

> `sealed class Member extends NamedNode implements Annotatable, FileUriNode`
> 定义文件: `src/ast/members.dart`

| 节点 | 说明 |
|------|------|
| `Field` | 字段（实例/静态/top-level） |
| `Constructor` | 构造函数 |
| `Procedure` | 方法/getter/setter/operator/factory (implements GenericFunction) |

辅助:

| 类型 | 说明 |
|------|------|
| `RedirectingFactoryTarget` | 重定向工厂信息 |

---

## 7. Declaration 节点

> 定义文件: `src/ast/declarations.dart`, `src/ast/libraries.dart`, `src/ast/typedefs.dart`

### 7.1 类型声明

| 节点 | 说明 |
|------|------|
| `Class` | 类声明 (extends NamedNode, implements TypeDeclaration) |
| `Typedef` | 类型别名 (extends NamedNode) |
| `Extension` | 扩展声明 (extends NamedNode) |
| `ExtensionTypeDeclaration` | 扩展类型声明 (extends NamedNode, implements TypeDeclaration) |

### 7.2 扩展描述符

| 节点 | 说明 |
|------|------|
| `ExtensionMemberDescriptor` | 扩展成员描述 |
| `ExtensionTypeMemberDescriptor` | 扩展类型成员描述 |

### 7.3 库结构

| 节点 | 说明 |
|------|------|
| `Library` | 库声明 (extends NamedNode) |
| `LibraryDependency` | import/export 依赖 (implements Annotatable) |
| `LibraryPart` | part 声明 (implements Annotatable) |
| `Combinator` | show/hide 组合器 |
| `Component` | 顶层组件（整个 .dill 文件） |

---

## 8. DartType 节点

> `sealed class DartType extends Node`
> 定义文件: `src/ast/types.dart`

### 8.1 基本类型

| 节点 | 说明 |
|------|------|
| `InvalidType` | 错误类型 |
| `DynamicType` | dynamic |
| `VoidType` | void |
| `NeverType` | Never |
| `NullType` | Null |

### 8.2 声明类型

| 节点 | 基类 | 说明 |
|------|------|------|
| `InterfaceType` | TypeDeclarationType | 接口类型 (classReference + typeArguments) |
| `ExtensionType` | TypeDeclarationType | 扩展类型 |
| `TypedefType` | DartType | 类型别名引用 |

### 8.3 函数与 Record 类型

| 节点 | 说明 |
|------|------|
| `FunctionType` | 函数类型 (typeParameters + params + returnType) |
| `RecordType` | Record 类型 (positional + named fields) |

### 8.4 参数化与特殊类型

| 节点 | 说明 |
|------|------|
| `TypeParameterType` | 类型参数引用 |
| `StructuralParameterType` | 结构化类型参数（FunctionType 内部） |
| `FutureOrType` | FutureOr<T> 特殊类型 |
| `IntersectionType` | 交叉类型（类型提升产物） |

### 8.5 类型参数定义

| 节点 | 说明 |
|------|------|
| `TypeParameter` | 类型参数 (extends TreeNode, implements Annotatable) |
| `StructuralParameter` | 结构化类型参数 (extends Node) |
| `Supertype` | 超类型规范 (extends Node) |
| `NamedType` | Record/函数命名参数类型 (extends Node) |

---

## 9. Constant 节点

> `sealed class Constant extends Node` (注意: DAG 结构，非树)
> 定义文件: `src/ast/constants.dart`

### 9.1 原始常量

| 节点 | 基类 | 说明 |
|------|------|------|
| `NullConstant` | PrimitiveConstant\<Null\> | null |
| `BoolConstant` | PrimitiveConstant\<bool\> | true / false |
| `IntConstant` | PrimitiveConstant\<int\> | 整数常量 |
| `DoubleConstant` | PrimitiveConstant\<double\> | 浮点常量 |
| `StringConstant` | PrimitiveConstant\<String\> | 字符串常量 |

### 9.2 复合常量

| 节点 | 说明 |
|------|------|
| `SymbolConstant` | #symbol 常量 |
| `ListConstant` | const [...] |
| `SetConstant` | const {...} |
| `MapConstant` | const {k: v} |
| `RecordConstant` | const Record |
| `InstanceConstant` | const 对象实例 |
| `InstantiationConstant` | 泛型函数实例化常量 |
| `TypeLiteralConstant` | 类型字面量常量 |
| `UnevaluatedConstant` | 未求值常量（延迟计算） |

### 9.3 Tear-off 常量

| 节点 | 说明 |
|------|------|
| `StaticTearOffConstant` | 静态方法 tear-off 常量 |
| `ConstructorTearOffConstant` | 构造函数 tear-off 常量 |
| `RedirectingFactoryTearOffConstant` | 重定向工厂 tear-off 常量 |
| `TypedefTearOffConstant` | typedef tear-off 常量 |

辅助: `ConstantMapEntry` (Map 常量键值对)

---

## 10. FunctionNode 与参数表示

> 定义文件: `src/ast/functions.dart`

```dart
class FunctionNode extends TreeNode {
  AsyncMarker asyncMarker;                          // 运行时异步标记
  AsyncMarker dartAsyncMarker;                      // Dart 层异步标记
  List<TypeParameter> typeParameters;               // 泛型参数 <T, S>
  int requiredParameterCount;                       // 必需位置参数数量
  List<VariableDeclaration> positionalParameters;   // 所有位置参数
  List<VariableDeclaration> namedParameters;        // 所有命名参数
  DartType returnType;                              // 返回类型
  DartType? emittedValueType;                       // async/generator 产出类型
  RedirectingFactoryTarget? redirectingFactoryTarget;
}
```

**FunctionType 中的参数表示:**

```dart
class FunctionType extends DartType {
  List<StructuralParameter> typeParameters;
  int requiredParameterCount;
  List<DartType> positionalParameters;              // 位置参数类型列表
  List<NamedType> namedParameters;                  // 命名参数（按名称排序）
  DartType returnType;
  Nullability declaredNullability;
}
```

**NamedType:**

```dart
class NamedType {
  String name;
  DartType type;
  bool isRequired;       // required 修饰符
}
```

**参数分类规则:**
- 位置参数: `positionalParameters[0..requiredParameterCount-1]` 为必需, `[requiredParameterCount..]` 为可选
- 命名参数: 通过 `NamedType.isRequired` / `VariableDeclaration.isRequired` 区分必需/可选

---

## 11. Reference 与 CanonicalName 体系

> 定义文件: `canonical_name.dart`

### CanonicalName

前缀树结构，用于跨库标识 library/class/member:

```
root
├── package:foo/foo.dart              ← Library
│   ├── @typedefs
│   │   └── MyCallback
│   ├── MyClass                       ← Class
│   │   ├── @constructors
│   │   │   └── named
│   │   ├── @methods
│   │   │   └── doSomething
│   │   ├── @getters
│   │   │   └── value
│   │   ├── @setters
│   │   │   └── value
│   │   └── @fields
│   │       └── _data
│   └── @methods
│       └── topLevelFunc
```

**容器前缀:**

| 前缀 | 含义 |
|------|------|
| `@constructors` | 构造函数 |
| `@factories` | 工厂构造函数 |
| `@methods` | 方法 |
| `@fields` | 字段 |
| `@getters` | getter / 可读字段 |
| `@setters` | setter / 可写字段 |
| `@typedefs` | 类型别名 |

### Reference

节点间的间接引用，支持延迟绑定:

```dart
class Reference {
  CanonicalName? canonicalName;    // 绑定到 CanonicalName
  NamedNode? _node;                // 实际 AST 节点

  // 类型安全转换
  Library get asLibrary;
  Class get asClass;
  Member get asMember;
  Field get asField;
  Constructor get asConstructor;
  Procedure get asProcedure;
  Typedef get asTypedef;
  ExtensionTypeDeclaration get asExtensionTypeDeclaration;
}
```

---

## 12. 枚举定义

### AsyncMarker (`src/ast/functions.dart`)

| 值 | 说明 |
|----|------|
| `Sync` | 同步函数 |
| `SyncStar` | 同步生成器 (`sync*`) |
| `Async` | 异步函数 (`async`) |
| `AsyncStar` | 异步生成器 (`async*`) |

### ProcedureKind (`src/ast/members.dart`)

| 值 | 说明 |
|----|------|
| `Method` | 普通方法 |
| `Getter` | getter |
| `Setter` | setter |
| `Operator` | 运算符重载 |
| `Factory` | 工厂构造函数 |

### ProcedureStubKind (`src/ast/members.dart`)

| 值 | 说明 |
|----|------|
| `Regular` | 源码中的正常 Procedure |
| `AbstractForwardingStub` | 抽象协变转发桩 |
| `ConcreteForwardingStub` | 具体协变转发桩 |
| `MemberSignature` | 继承成员类型签名 (NNBD) |
| `NoSuchMethodForwarder` | noSuchMethod 转发器 |

### Nullability (`src/ast/types.dart`)

| 值 | 说明 |
|----|------|
| `undetermined` | 不确定（泛型边界） |
| `nullable` | 可空 (`T?`, `dynamic`, `void`, `Null`) |
| `nonNullable` | 非空 |

### DynamicAccessKind (`src/ast/expressions.dart`)

| 值 | 说明 |
|----|------|
| `Dynamic` | 接收者为 dynamic 类型 |
| `Never` | 接收者为 Never 类型 |
| `Invalid` | 无效类型 |
| `Unresolved` | 未解析目标 |

### InstanceAccessKind (`src/ast/expressions.dart`)

| 值 | 说明 |
|----|------|
| `Instance` | 非空接口类型上的访问 |
| `Object` | 非接口/可空类型上的 Object 成员 |
| `Inapplicable` | 错误: 参数不匹配 |
| `Nullable` | 错误: 可空类型上的非 Object 成员 |

### FunctionAccessKind (`src/ast/expressions.dart`)

| 值 | 说明 |
|----|------|
| `Function` | Function 类型上的 call |
| `FunctionType` | 函数类型上的 call |
| `Inapplicable` | 错误: 参数不匹配 |
| `Nullable` | 错误: 可空函数调用 |

### LogicalExpressionOperator (`src/ast/expressions.dart`)

| 值 | 说明 |
|----|------|
| `AND` | `&&` |
| `OR` | `\|\|` |

### ExtensionMemberKind (`src/ast/declarations.dart`)

| 值 | 说明 |
|----|------|
| `Field` / `Method` / `Getter` / `Setter` / `Operator` | 对应成员类型 |

### ExtensionTypeMemberKind (`src/ast/declarations.dart`)

| 值 | 说明 |
|----|------|
| `Constructor` / `Factory` / `Field` / `Method` | 对应成员类型 |
| `Getter` / `Setter` / `Operator` / `RedirectingFactory` | 对应成员类型 |

### RelationalPatternKind (`src/ast/patterns.dart`)

| 值 | 说明 |
|----|------|
| `equals` / `notEquals` | `==` / `!=` |
| `lessThan` / `lessThanEqual` | `<` / `<=` |
| `greaterThan` / `greaterThanEqual` | `>` / `>=` |

### RelationalAccessKind (`src/ast/patterns.dart`)

| 值 | 说明 |
|----|------|
| `Instance` / `Static` / `Dynamic` / `Never` / `Invalid` | 运算符解析方式 |

### ObjectAccessKind (`src/ast/patterns.dart`)

| 值 | 说明 |
|----|------|
| `Object` | Object 成员 |
| `Instance` | 接口成员 |
| `Extension` | 扩展成员 |
| `ExtensionType` | 扩展类型成员 |
| `RecordNamed` / `RecordIndexed` | Record 字段 |
| `Dynamic` / `Never` / `Invalid` | 特殊接收者 |
| `FunctionTearOff` / `Error` / `Direct` | 其他 |

---

## 13. 节点标志位 (Flags)

### Field 标志位

| 标志 | 位 | 属性 | 说明 |
|------|---|------|------|
| `FlagFinal` | 0 | `isFinal` | final 字段 |
| `FlagConst` | 1 | `isConst` | const 字段 |
| `FlagStatic` | 2 | `isStatic` | static 字段 |
| `FlagCovariant` | 3 | `isCovariantByDeclaration` | 声明协变 |
| `FlagCovariantByClass` | 4 | `isCovariantByClass` | 泛型协变 |
| `FlagLate` | 5 | `isLate` | late 字段 |
| `FlagExtensionMember` | 6 | `isExtensionMember` | 来自 extension |
| `FlagInternalImplementation` | 7 | `isInternalImplementation` | 合成/late 降级 |
| `FlagEnumElement` | 8 | `isEnumElement` | enum 元素 |
| `FlagExtensionTypeMember` | 9 | `isExtensionTypeMember` | 来自 extension type |
| `FlagErroneous` | 10 | `isErroneous` | 编译错误 |

### Constructor 标志位

| 标志 | 位 | 属性 | 说明 |
|------|---|------|------|
| `FlagConst` | 0 | `isConst` | const 构造函数 |
| `FlagExternal` | 1 | `isExternal` | external |
| `FlagSynthetic` | 2 | `isSynthetic` | 编译器合成 |
| `FlagErroneous` | 3 | `isErroneous` | 编译错误 |

### Procedure 标志位

| 标志 | 位 | 属性 | 说明 |
|------|---|------|------|
| `FlagStatic` | 0 | `isStatic` | static |
| `FlagAbstract` | 1 | `isAbstract` | abstract |
| `FlagExternal` | 2 | `isExternal` | external |
| `FlagConst` | 3 | `isConst` | const (仅 factory) |
| `FlagExtensionMember` | 4 | `isExtensionMember` | 来自 extension |
| `FlagSynthetic` | 5 | `isSynthetic` | 编译器合成 |
| `FlagInternalImplementation` | 6 | `isInternalImplementation` | 内部实现 |
| `FlagExtensionTypeMember` | 7 | `isExtensionTypeMember` | 来自 extension type |
| `FlagHasWeakTearoffReferencePragma` | 8 | `hasWeakTearoffReferencePragma` | 弱引用 pragma |
| `FlagErroneous` | 9 | `isErroneous` | 编译错误 |

**Procedure 派生属性:**
- `isGetter` / `isSetter` / `isAccessor` — 基于 `kind`
- `isFactory` — `kind == ProcedureKind.Factory`
- `isForwardingStub` / `isForwardingSemiStub` — 基于 `stubKind`
- `isMemberSignature` / `isNoSuchMethodForwarder` — 基于 `stubKind`
- `isRedirectingFactory` — 有 `redirectingFactoryTarget`

### InstanceInvocation 标志位

| 标志 | 位 | 属性 | 说明 |
|------|---|------|------|
| `FlagInvariant` | 0 | `isInvariant` | 协变检查安全 |
| `FlagBoundsSafe` | 1 | `isBoundsSafe` | 边界检查安全 |

### TypeParameter 标志位

| 标志 | 位 | 属性 | 说明 |
|------|---|------|------|
| `FlagCovariantByClass` | 0 | `isLegacyCovariant` | 泛型协变 |

---

## 14. Visitor 模式

### 14.1 Visitor 类层次

```
ExpressionVisitor<R>     ──┐
PatternVisitor<R>        ──┤
StatementVisitor<R>      ──├── TreeVisitor<R> ──┐
MemberVisitor<R>         ──┤                    │
InitializerVisitor<R>    ──┘                    │
                                                │
DartTypeVisitor<R>         ─────────────────────├── Visitor<R>
ConstantVisitor<R>         ─────────────────────┤
MemberReferenceVisitor<R>  ─────────────────────┤
ConstantReferenceVisitor<R>─────────────────────┘
```

### 14.2 Visitor 类清单

| 类 | 说明 |
|----|------|
| `ExpressionVisitor<R>` | 表达式访问 (72 个 visit 方法) |
| `PatternVisitor<R>` | 模式访问 (17 个) |
| `StatementVisitor<R>` | 语句访问 (24 个) |
| `MemberVisitor<R>` | 成员访问 (3 个) |
| `MemberVisitor1<R, A>` | 带参成员访问 |
| `InitializerVisitor<R>` | 初始化器访问 (7 个) |
| `InitializerVisitor1<R, A>` | 带参初始化器访问 |
| `TreeVisitor<R>` | 组合: Expression + Pattern + Statement + Member + Initializer + 结构节点 |
| `TreeVisitor1<R, A>` | 带参组合 |
| `DartTypeVisitor<R>` | 类型访问 (15 个) |
| `DartTypeVisitor1<R, A>` | 带参类型访问 |
| `ConstantVisitor<R>` | 常量访问 (22 个，注意 DAG 结构) |
| `ConstantVisitor1<R, A>` | 带参常量访问 |
| `ConstantReferenceVisitor<R>` | 常量引用访问 (20 个) |
| `ConstantReferenceVisitor1<R, A>` | 带参常量引用访问 |
| `MemberReferenceVisitor<R>` | 成员引用访问 (3 个) |
| `MemberReferenceVisitor1<R, A>` | 带参成员引用访问 |
| `Visitor<R>` | 全量组合 visitor |
| `Visitor1<R, A>` | 带参全量组合 |

### 14.3 具体实现

| 类 | 说明 |
|----|------|
| `RecursiveVisitor` | 默认递归遍历 (void 返回) |
| `RecursiveResultVisitor<R>` | 递归遍历 (可空返回值) |
| `Transformer` | AST 重写 (返回 TreeNode) |
| `RemovingTransformer` | 支持节点移除的重写器 |

### 14.4 Default Mixin 列表

每个 Visitor 都有对应的 DefaultMixin，将所有 visit 方法代理到单一 `default*` 方法:

- `ExpressionVisitorDefaultMixin<R>` → `defaultExpression()` / `defaultBasicLiteral()`
- `PatternVisitorDefaultMixin<R>` → `defaultPattern()`
- `StatementVisitorDefaultMixin<R>` → `defaultStatement()`
- `MemberVisitorDefaultMixin<R>` → `defaultMember()`
- `InitializerVisitorDefaultMixin<R>` → `defaultInitializer()`
- `DartTypeVisitorDefaultMixin<R>` → `defaultDartType()`
- `ConstantVisitorDefaultMixin<R>` → `defaultConstant()`
- `MemberReferenceVisitorDefaultMixin<R>` → `defaultMemberReference()`
- `ConstantReferenceVisitorDefaultMixin<R>` → `defaultConstantReference()`

---

## 15. 源文件索引

| 文件 | 主要内容 |
|------|---------|
| `lib/ast.dart` | barrel 导出（re-export 所有 src/ast/*.dart） |
| `src/ast/misc.dart` | Node, TreeNode, NamedNode, GenericDeclaration, Version |
| `src/ast/expressions.dart` | Expression 及其所有子类, Arguments, NamedExpression |
| `src/ast/statements.dart` | Statement 及其所有子类, SwitchCase, Catch |
| `src/ast/patterns.dart` | Pattern 及其所有子类, MapPatternEntry, PatternGuard |
| `src/ast/initializers.dart` | Initializer 及其所有子类 |
| `src/ast/members.dart` | Member, Field, Constructor, Procedure |
| `src/ast/declarations.dart` | Class, Extension, ExtensionTypeDeclaration |
| `src/ast/libraries.dart` | Library, LibraryDependency, Combinator, Component |
| `src/ast/typedefs.dart` | Typedef |
| `src/ast/functions.dart` | FunctionNode, AsyncMarker |
| `src/ast/types.dart` | DartType 及其所有子类, TypeParameter, NamedType, Nullability |
| `src/ast/constants.dart` | Constant 及其所有子类, ConstantMapEntry |
| `src/ast/names.dart` | Name, _PublicName, _PrivateName |
| `src/ast/helpers.dart` | BinarySink, BinarySource, DirtifyingList |
| `src/ast/components.dart` | Component, Location, Source, MetadataRepository |
| `canonical_name.dart` | CanonicalName, Reference |
| `visitor.dart` | 所有 Visitor / Transformer 定义 |

---

## 16. 与设计文档的交叉引用

### 16.1 Ch4 (编译器) 明确提及的节点

**已覆盖 (30+ 节点):**

| 类别 | 节点 |
|------|------|
| 顶层 | Component, Reference, Class, Typedef |
| 变量 | VariableDeclaration, VariableSet |
| 控制流 | IfStatement, ForStatement, WhileStatement, DoStatement, ForInStatement, SwitchStatement, BreakStatement, ContinueSwitchStatement, LabeledStatement |
| 异常 | TryCatch, TryFinally, AssertStatement |
| 表达式 | ConditionalExpression, InstanceGet, InstanceSet, InstanceInvocation, StaticInvocation, ConstructorTearOff, StringConcatenation, Let, ConstantExpression |
| 声明 | Procedure, FunctionDeclaration |
| 字面量 | RecordLiteral |
| 类型 | InterfaceType, FunctionType, TypeParameterType, FutureOrType, RecordType |

**CFE 已脱糖（编译器无需直接处理）:**
- Cascade → Let + 连续 InstanceGet/InstanceInvocation
- Pattern matching → IfStatement 链
- Extension methods → StaticInvocation
- Extension types → 类型擦除
- Spread → add/addAll 调用
- Collection if/for → 命令式代码
- Type aliases → 展开为底层类型

### 16.2 设计文档中未明确提及但 Kernel 中存在的节点

以下节点在设计文档中未被逐一讨论，需要校验是否需要补充处理方案:

#### Expression 类

| 节点 | 可能处理方式 |
|------|-------------|
| `VariableGet` | 隐含在变量访问中，应已覆盖 |
| `DynamicGet` / `DynamicSet` / `DynamicInvocation` | 需 dynamic 调度支持 |
| `InstanceGetterInvocation` | getter 返回值调用 |
| `FunctionTearOff` | 函数撕裂 |
| `StaticTearOff` | 静态撕裂 |
| `RedirectingFactoryTearOff` / `TypedefTearOff` | 工厂/typedef 撕裂 |
| `AbstractSuperPropertyGet/Set` | 抽象 super 访问（可能不在运行时出现） |
| `AbstractSuperMethodInvocation` | 抽象 super 调用 |
| `SuperPropertyGet/Set` | super 属性访问 |
| `SuperMethodInvocation` | super 方法调用 |
| `LocalFunctionInvocation` | 局部函数调用 |
| `FunctionInvocation` | 函数类型 call() |
| `EqualsNull` / `EqualsCall` | == 优化 |
| `Not` | 逻辑非 |
| `NullCheck` | 非空断言 |
| `LogicalExpression` | && / \|\| |
| `Throw` / `Rethrow` | 抛出异常 |
| `IsExpression` / `AsExpression` | 类型检查/转换 |
| `InstanceCreation` | const 对象创建 |
| `Instantiation` | 泛型函数实例化 |
| `BlockExpression` | 块表达式 |
| `FunctionExpression` | 匿名函数 |
| `LoadLibrary` / `CheckLibraryIsLoaded` | 延迟加载 |
| `FileUriExpression` | URI 包装（可能透传） |
| `SwitchExpression` | switch 表达式 |
| `PatternAssignment` | 模式赋值 |
| `RecordIndexGet` / `RecordNameGet` | Record 字段访问 |
| `ListConcatenation` / `SetConcatenation` / `MapConcatenation` | 集合拼接 |

#### Statement 类

| 节点 | 可能处理方式 |
|------|-------------|
| `Block` | 隐含覆盖 |
| `ExpressionStatement` | 隐含覆盖 |
| `EmptyStatement` | 空操作 |
| `AssertBlock` | 类似 AssertStatement |
| `IfCaseStatement` | Dart 3 if-case |
| `PatternSwitchStatement` | Dart 3 pattern switch |
| `PatternVariableDeclaration` | 模式变量声明 |
| `ReturnStatement` | 隐含覆盖 |
| `ContinueSwitchStatement` | 与 BreakStatement 类似 |

#### Initializer 类

| 节点 | 说明 |
|------|------|
| 全部 6 个 | 设计文档未单独讨论初始化器编译策略 |

#### Constant 类

| 节点 | 说明 |
|------|------|
| `SymbolConstant` | #symbol 常量 |
| `SetConstant` / `RecordConstant` | Set/Record 常量 |
| `InstantiationConstant` | 泛型实例化常量 |
| `TypeLiteralConstant` | 类型字面量常量 |
| `UnevaluatedConstant` | 延迟求值常量 |
| Tear-off 常量 (4 种) | 函数引用常量 |

### 16.3 覆盖度总结

| 类别 | Kernel 节点总数 | 设计文档明确提及 | CFE 脱糖 | 需补充讨论 |
|------|----------------|-----------------|----------|-----------|
| Expression | ~70 | ~15 | ~10 (cascade, spread, collection-if 等) | ~45 |
| Statement | ~25 | ~12 | ~3 (pattern 相关) | ~10 |
| Pattern | 17 | 0 (CFE 脱糖) | 17 | 0 (确认脱糖覆盖) |
| Initializer | 6 | 0 | 0 | 6 |
| Member | 3 | 2 | 0 | 1 (Field 单独处理) |
| DartType | ~16 | 5 | 0 | ~11 |
| Constant | ~20 | 2 | 0 | ~18 |
| **合计** | **~157** | **~36** | **~30** | **~91** |

> **注**: "需补充讨论" 中很多节点的处理方式是显而易见的（如 `Not` → `NOT` 指令），但建议在设计文档中建立完整映射表，确保编译器实现时不遗漏。
