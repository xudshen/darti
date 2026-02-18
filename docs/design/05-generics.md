# Chapter 5: 泛型系统

## 模块定位

泛型系统负责在运行时表示、传递和检查参数化类型。它将 Kernel AST 中的类型信息编译为紧凑的 TypeTemplate，在运行时按需实例化为驻留的 DarticType，并提供 `is`/`as` 所需的子类型判定。泛型系统位于运行时（Ch2）之上、编译器（Ch4）之下，为 Bridge 层（Ch3）的跨边界类型保真提供基础。

## 与其他模块的关系

| 方向 | 模块 | 接口 |
|------|------|------|
| 输入 | Ch4 编译器 | 编译器从 Kernel 提取类型信息，生成 TypeTemplate 和 SuperTypeMap，写入 .darticb 常量池 |
| 输入 | Ch2 运行时 | 栈帧提供 ITA/FTA 槽位；分发循环执行 INSTANCEOF/CAST 等指令 |
| 输出 | Ch2 运行时 | isSubtypeOf 结果驱动 INSTANCEOF/CAST 指令的分支 |
| 输出 | Ch3 Bridge | 跨边界对象的类型提取和泛型类型保真 |
| 契约 | Ch1 ISA | 泛型相关指令语义（PUSH_ITA, INSTANTIATE_TYPE, LOAD_TYPE_ARG 等，详见 Ch1） |

## 泛型数据流

```
编译期                                             运行时
┌─────────────────┐                        ┌──────────────────────┐
│ Kernel AST      │                        │  栈帧 ITA/FTA 槽位    │
│ InterfaceType   │──► TypeTemplate ──────►│  resolveType()       │
│ FunctionType    │    (常量池 refs)        │       │              │
│ TypeParameterType│                       │       ▼              │
└─────────────────┘                        │  TypeRegistry.intern │
                                           │       │              │
┌─────────────────┐                        │       ▼              │
│ 类继承关系       │──► SuperTypeMap ──────►│  DarticType (驻留)   │
│ (编译器预计算)   │    (常量池 refs)        │       │              │
└─────────────────┘                        │       ▼              │
                                           │  isSubtypeOf()      │
                                           │       │              │
                                           │       ▼              │
                                           │  INSTANCEOF/CAST 结果│
                                           └──────────────────────┘
```

## 设计决策

| 决策项 | 选择 | 备选方案与拒绝理由 | 理由 |
|--------|------|-------------------|------|
| 实化策略 | 延迟按需实化 | 立即实化：每次对象创建都需实例化完整类型树，大量泛型组合导致启动时内存膨胀 | 对象仅记录 classId + typeArgs 描述符，类型检查按需计算并缓存 |
| 类型相等性 | 驻留（canonicalization） | 结构比较：每次 == 需递归比较 classId + typeArgs，O(depth)；缓存键需完整哈希 | 驻留后 == 退化为 identical()（O(1)），hashCode 用 identityHashCode（O(1)） |
| 类型参数传递 | ITA + FTA 栈帧槽位 | 字典传递：每次调用需查字典 O(n)；堆分配传递：GC 压力 | 编译期确定偏移，运行时零查找，仅 8-16 字节栈开销 |
| 跨边界泛型 | 编译器分析实际使用组合，预生成类型化 Bridge | 运行时动态反射泛型参数：Dart 无法运行时创建参数化类型 | 消除运行时泛型实例化问题 |
| 类型参数向量 | 树形结构（不扁平化） | 扁平化 TypeArguments 向量（Dart VM 方案）：需要维护类继承深度的偏移表，泛型 mixin 导致偏移计算复杂度爆炸 | 树形结构简单直接，驻留保证性能，Phase 1 复杂度可控 |

## Kernel 中的泛型信息

CFE 已完成所有类型推断，解释器无需重做。Kernel 的 `DartType` 共 16 种子类，按运行时处理方式分为三组：

**运行时需表示的类型**（编译器生成 TypeTemplate，运行时 resolveType 处理）：

| Kernel 节点 | 解释器关注点 |
|-------------|------------|
| `InterfaceType` | 携带 `classReference` + `typeArguments`，是 `List<int>` 的表示 |
| `FunctionType` | 携带 `typeParameters`（`StructuralParameter` 列表）、`positionalParameters`、`namedParameters`（含 `isRequired` 标志）、`requiredParameterCount` 和 `returnType` |
| `TypeParameterType` | 引用类/方法级 `TypeParameter`，使用 de Bruijn 风格索引，运行时从 ITA/FTA 查找 |
| `StructuralParameterType` | 引用 `FunctionType` 内部的 `StructuralParameter`，索引方式同 `TypeParameterType`（详见 Ch4 DartType 分类表） |
| `FutureOrType` | `FutureOr<T>` 特殊处理（驻留时规范化，子类型判定特殊规则） |
| `RecordType` | Dart 3 记录类型（positional + named 字段），Phase 2 支持 |
| `DynamicType` | 编译为 `TypeTemplate(DYNAMIC)`，isSubtypeOf 顶类型规则处理 |
| `VoidType` | 编译为 `TypeTemplate(VOID)`，语义与 dynamic 类似 |
| `NeverType` | 编译为 `TypeTemplate(NEVER)`，isSubtypeOf 底类型规则处理 |
| `NullType` | 编译为 `TypeTemplate(NULL)`，等价于 `Never?`（驻留时规范化） |

**CFE 已消除的类型**（不进入代码生成阶段）：

| Kernel 节点 | CFE 处理 |
|-------------|---------|
| `ExtensionType` | CFE 已擦除为底层表示类型（`InterfaceType`） |
| `TypedefType` | CFE 已展开为底层类型引用 |
| `IntersectionType` | CFE 类型提升产物，编译器取 promoted type（`right`）生成 TypeTemplate（详见 Ch4） |
| `InvalidType` | 编译错误标记，不应进入代码生成阶段；若出现则编译器报错 |

方法调用中推断的类型参数已填入 `Arguments.types`。编译器只需读取并传播。

## 核心概念

### DarticType（驻留类型实例）

运行时所有类型信息的统一表示。经 TypeRegistry 驻留后，结构相同的类型共享唯一实例。

| 属性 | 类型 | 说明 |
|------|------|------|
| classId | int | 类的编译期 ID（与 DarticObject.classId 一致） |
| typeArgs | `List<DarticType>` | 类型参数列表（驻留后的子类型引用，不可变） |
| nullability | Nullability | nonNullable / nullable / undetermined 三态 |
| _canonicalHash | int | 驻留时计算的结构哈希，用于桶定位 |

**Nullability 映射**：Kernel 的 `Nullability` 枚举有三个值——`nonNullable`、`nullable`、`undetermined`。`undetermined` 出现在类型参数边界中（如 `T extends Object?` 时 `T` 的可空性取决于实例化），运行时 resolveType 将类型参数替换为实际类型后，`undetermined` 不再出现。对于尚未解析的 TypeParameterTemplate，保留 `undetermined` 标记，resolveType 时由实际类型参数的 nullability 替代。

**不变式**：驻留后 typeArgs 中的每个元素本身也已驻留，因此子类型比较可用 `identical()` 代替 `==`。

### TypeTemplate（编译期类型描述）

编译器将 Kernel 类型节点编码为 TypeTemplate，存入 .darticb 常量池 refs 分区。三种变体：

| 变体 | 含义 | resolveType 行为 |
|------|------|-----------------|
| ConcreteTypeTemplate | 不含类型参数引用的具体类型（如 `int`, `String`） | 直接返回预驻留的 DarticType |
| TypeParameterTemplate | 对作用域内类型参数的引用（de Bruijn 索引） | 按 isClassTypeParam 标志从 ITA 或 FTA 中按 index 查找 |
| GenericTypeTemplate | 含类型参数引用的参数化类型（如 `List<T>`） | 递归 resolveType 每个 typeArgTemplate，然后 intern 结果 |

#### FunctionTypeTemplate 编码

FunctionType 的 TypeTemplate 需保留完整的参数签名信息，用于运行时函数子类型检查：

| 字段 | 类型 | 说明 |
|------|------|------|
| typeParamBounds | `List<TypeTemplate>` | 泛型参数的上界（如 `T extends Comparable<T>` 的 `Comparable<T>`） |
| requiredParamCount | int | 必需位置参数数量 |
| positionalParams | `List<TypeTemplate>` | 所有位置参数类型（必需 + 可选） |
| namedParams | `List<(String name, TypeTemplate type, bool isRequired)>` | 命名参数三元组，按 name 字典序排列 |
| returnType | TypeTemplate | 返回类型 |
| nullability | Nullability | 函数类型自身的可空性 |

resolveType 处理 FunctionTypeTemplate 时，递归解析所有内嵌 TypeTemplate（参数类型、返回类型、边界），然后 intern 为 DarticFunctionType。

### TypeRegistry（驻留表）

采用 bucket-hash 方案：以 `_structuralHash(classId, typeArgs, nullability)` 为键分桶，桶内线性扫描。碰撞率低（典型程序的类型组合有限），查找接近 O(1)。

**三个不变式**：

1. **`==` 退化为 `identical()`**：驻留保证结构相同的类型返回同一实例，所有类型比较只需指针比较
2. **`hashCode` 使用 `identityHashCode`**：子类型已驻留，哈希计算无需递归遍历类型树
3. **SubtypeTestCache 键比较极快**：缓存键为 `(DarticType, DarticType)` 对，两次 `identical()` 即可判等

预注册的常用类型（启动时即驻留）：`int`, `double`, `String`, `bool`, `dynamic`, `Object?`, `Never`。

### SuperTypeMap（超类型参数映射表）

编译器预计算每个类对其所有超类型的类型参数映射。

**生成时机**：编译期，遍历类继承图为每个类生成条目，写入 .darticb。

**数据结构**：`classId → { superClassId → List<TypeArgTemplate> }`。每个 TypeArgTemplate 可以是具体类型（如 `String`）或类型参数引用（如 "取 ITA[0]"）。

**多重继承处理**：Dart 的 implements/with 产生多条超类型路径。编译器为每条路径生成独立映射条目。例如 `class A<T> extends B<T> implements C<int>` 同时包含 `B → [TypeParam(0)]` 和 `C → [Concrete(int)]` 两条映射。

**查找复杂度**：O(1) 两级 Map 查找（先 classId，再 superClassId），返回 TypeArgTemplate 列表。

## 工作流程

### 类型参数传递（ITA / FTA）

每个栈帧预留两个引用栈槽位传递类型参数：

```
引用栈帧布局：
  rsp+0:  instantiator_type_args (ITA)  ← 类的类型参数（来自 this 对象）
  rsp+1:  function_type_args (FTA)      ← 方法的类型参数（来自调用者）
  rsp+2:  this / receiver
  rsp+3:  arg0
  rsp+4:  arg1
  ...
  rsp+N:  局部变量
```

**ITA 加载**：实例方法入口时，编译器生成 `LOAD_TYPE_ARG` 序列从 receiver 的 DarticType 提取类型参数到 ITA 槽位。无泛型参数的类此序列为空；单类型参数类（如 `List<T>`）仅一条指令。

**FTA 传递**：泛型方法调用时，调用者将推断的类型参数组装为 FTA 推入新帧。编译器生成 `CREATE_TYPE_ARGS` + `PUSH_FTA` 序列。

**嵌套泛型函数的 FTA 连接**：多层泛型函数嵌套时，FTA 是所有封闭泛型函数类型参数的连接向量。编译器在编译内层函数时确定 FTA 布局（如 `[B, C]`），TypeParameterType 的 de Bruijn 索引直接映射到 FTA 偏移。

**闭包中的类型参数捕获**：闭包在泛型上下文中创建时，捕获当前的 ITA 和 FTA（作为 capturedITA / capturedFTA 存储在闭包对象中）。闭包执行时恢复到新帧的对应槽位。

### resolveType：类型模板解析

`INSTANCEOF` / `CAST` 指令的目标类型编码为 TypeTemplate（可能含 TypeParameterTemplate），运行时必须在调用 isSubtypeOf 之前解析为具体 DarticType。

**解析三分支**：

1. **ConcreteTypeTemplate** → 直接返回预驻留的 DarticType（O(1)）
2. **TypeParameterTemplate** → 读取 isClassTypeParam 标志，从当前帧的 ITA（类类型参数）或 FTA（函数类型参数）中按 index 取值（O(1)）
3. **GenericTypeTemplate** → 对每个 typeArgTemplate 递归调用 resolveType，收集解析后的类型参数列表，调用 `TypeRegistry.intern(classId, resolvedArgs, nullability)` 驻留并返回

**INSTANCEOF 指令执行流**（以 `value is T` 为例）：

1. 从常量池取 TypeTemplate
2. 用当前帧的 ITA/FTA 调用 resolveType 得到 targetType
3. 从对象提取 objType（extractType）
4. 调用 `isSubtypeOf(objType, targetType)` 得到布尔结果
5. 写入 valueStack

### 泛型函数实例化（Instantiation）

Kernel 的 `Instantiation` 节点表示泛型函数的类型实例化（如 `identity<int>`），产生一个绑定了类型参数的新函数值。Ch4 将其编译为"实例化包装闭包"，运行时语义如下：

1. 编译器为 `Instantiation` 生成包装闭包的 `DarticFuncProto`，其参数签名与原函数一致（去掉类型参数部分）
2. 将实例化的类型参数编译为 TypeTemplate 列表，存入常量池
3. 运行时创建包装闭包时，resolveType 解析类型参数列表为具体 DarticType，存入闭包的 capturedFTA
4. 调用包装闭包时，capturedFTA 恢复到新帧的 FTA 槽位，然后转发调用原函数

`InstantiationConstant`（常量池中的泛型函数实例化）在编译期即完成类型参数绑定，运行时直接使用预计算的闭包常量。

### isSubtypeOf：子类型判定

子类型判定采用分层策略：先做快速路径排除（identical / 顶类型 / 底类型 / 可空性），再处理特殊类型（Null / FutureOr / FunctionType / RecordType），最后通过 SuperTypeMap 递归检查类层级中的类型参数匹配。

规则表**从上到下依次检查**，首个匹配的规则决定结果：

| # | 规则 | 条件 | 结果 |
|---|------|------|------|
| 1 | identical 快速路径 | `identical(sub, sup)` | true |
| 2 | 顶类型 | sup 为 `dynamic`、`void` 或 `Object?` | true |
| 3 | 底类型 | sub 为 `Never` | true |
| 4 | 可空性拒绝 | sub 为 nullable 且 sup 为 nonNullable | false |
| 5 | Null 类型 | sub.classId 为 Null | sup 为 nullable 则 true，否则 false |
| 6 | 非空到可空提升 | sup 为 nullable，构造 sup 的 nonNullable 版本 supBase，递归 `isSubtypeOf(sub, supBase)` | 递归结果 |
| 7 | FutureOr 作为超类型 | sup.classId 为 FutureOr | `sub <: Future<T> \|\| sub <: T` |
| 8 | FutureOr 作为子类型 | sub.classId 为 FutureOr | `Future<T> <: sup && T <: sup` |
| 9 | 函数类型分发 | sub 或 sup 为 FunctionType | 详见下方分发逻辑 |
| 10 | Record 类型分发 | sub 或 sup 为 RecordType | 详见下方分发逻辑（Phase 2） |
| 11 | 超类型参数查找 | 查 SuperTypeMap 获取 sub 在 sup 类层级中的映射 | 无映射 → false |
| 12 | 类型参数递归检查 | 用 sub 的 typeArgs 实例化超类型映射，逐参数递归 isSubtypeOf | 全部通过 → true |

**规则 6 说明**：旧版将非空到可空提升简化为 classId + typeArgs 匹配，但这无法处理继承关系（如 `int <: num?`）。正确做法是剥离 sup 的可空性后递归，由后续规则处理类层级关系。

**规则 9 函数类型分发逻辑**：

| sub | sup | 处理 |
|-----|-----|------|
| FunctionType | FunctionType | 调用 `isFunctionSubtype(sub, sup)` |
| FunctionType | `Function` 类 / `Object` | true（所有函数类型都是 `Function` 和 `Object` 的子类型） |
| 非 FunctionType | FunctionType | false |
| FunctionType | 其他 InterfaceType | false |

**规则 10 Record 类型分发逻辑**（Phase 2）：

| sub | sup | 处理 |
|-----|-----|------|
| RecordType | RecordType | 调用 `isRecordSubtype(sub, sup)`——形状匹配 + 字段类型协变递归检查 |
| RecordType | `Record` 类 / `Object` | true |
| 非 RecordType | RecordType | false |

初期使用直接递归计算。调用点缓存和全局 SubtypeTestCache 留待 profiling 后添加。

### isFunctionSubtype：函数类型子类型

函数类型的子类型检查按以下规则**从上到下依次检查**，任一规则失败则返回 false：

| # | 检查项 | 方差 | 规则 |
|---|--------|------|------|
| 1 | 类型参数数量 | — | sub 和 sup 的泛型类型参数数量必须一致 |
| 2 | 类型参数边界 | 互等 | 对每对类型参数，`sub.bound[i] <: sup.bound[i]` 且 `sup.bound[i] <: sub.bound[i]`（边界须等价） |
| 3 | 返回类型 | 协变 | `sub.returnType <: sup.returnType` |
| 4 | 必需位置参数数量 | — | `sub.requiredParamCount ≤ sup.requiredParamCount`（sub 允许更少的必需参数） |
| 5 | 位置参数总数 | — | `sub.positionalParams.length ≥ sup.positionalParams.length`（sub 必须接受 sup 的所有位置参数） |
| 6 | 位置参数类型 | 逆变 | 对每个位置参数 i（0 到 sup 的位置参数数-1）：`sup.positionalParams[i] <: sub.positionalParams[i]` |
| 7 | 命名参数覆盖 | — | sup 的每个命名参数名必须在 sub 中存在（sub 可以有额外的命名参数） |
| 8 | 命名参数类型 | 逆变 | 对每个匹配的命名参数：`sup.namedParam.type <: sub.namedParam.type` |
| 9 | required 标志 | — | 若 sub 的某个命名参数为 `required`，则 sup 对应的命名参数也必须为 `required`（sub 不能比 sup 更严格） |

**示例**：`void Function(int, {required String name})` 是 `void Function(int)` 的子类型吗？
- 规则 4：sub.requiredParamCount(1) ≤ sup.requiredParamCount(1) ✓
- 规则 5：sub.positionalParams.length(1) ≥ sup.positionalParams.length(1) ✓
- 规则 6：位置参数类型 int <: int ✓
- 规则 7：sup 无命名参数，覆盖检查通过 ✓
- 结果：true（但反过来为 false——sup 缺少 sub 要求的 `name` 参数）

编译器需要在 FunctionTypeTemplate 中保留完整的参数签名信息（详见 FunctionTypeTemplate 编码），运行时 resolveType 在解析 FunctionType 模板时同时解析所有参数类型和边界。

### FutureOr\<T\> 规范化

TypeRegistry 在驻留时执行以下规范化规则，确保等价类型共享实例：

| 输入 | 规范化结果 | 理由 |
|------|-----------|------|
| `FutureOr<Never>` | `Future<Never>` | Never 不可能直接出现 |
| `FutureOr<Object?>` | `Object?` | Object? 已包含所有类型 |
| `FutureOr<Object>` | `Object` | Object 已包含非空类型 |
| `FutureOr<dynamic>` | `dynamic` | dynamic 已包含所有类型 |
| `FutureOr<void>` | `void` | void 已包含所有类型 |
| `FutureOr<Null>` | `Future<Null>?` | Null 只能 nullable |
| `FutureOr<T?>` | `FutureOr<T>?` | 可空性提升到外层 |
| `Null` | `Never?` | 在可空性层面等价 |

## 跨边界泛型

### 解释器 → VM

初期统一使用 `List<dynamic>.from()` 等动态类型兜底。

**已知局限**：解释器创建的集合跨边界传递时，VM 侧的 `is List<int>` 等泛型类型检查会失败（运行时类型为 `List<dynamic>`），功能不受影响但违反静态类型约束。

**Phase 1 Workaround**：业务代码中避免对跨边界集合做精确泛型类型检查。

> **Phase 2**：为高频泛型组合预生成类型化创建路径。Bridge 生成器分析解释器代码中的集合创建点，为 `List<int>`、`List<String>`、`Map<String, dynamic>` 等常见组合生成专用工厂，确保跨边界后 `is` 检查正确。触发条件：业务代码需要跨边界传递参数化集合并做类型检查。

### VM → 解释器

VM 对象进入解释器时，通过类型提取器（extractType）获取 DarticType。提取流程按以下优先级依次匹配：

1. **基本类型**：`int` / `double` / `String` / `bool` / `Null` → 返回 TypeRegistry 中预注册的 DarticType（O(1)）
2. **集合类型**：`List<E>` / `Map<K,V>` / `Set<E>` → 利用 Dart reified generics 通过泛型辅助函数提取元素类型参数（如 `_extractListElementType<E>(List<E> list)`），递归 extractType 每个类型参数后 intern
3. **Bridge 对象**：对象本身是 Bridge 类实例 → 直接从 Bridge 关联的 DarticObject 获取已有的 DarticType
4. **未知类型**：以上均不匹配 → 退化为 `dynamic`

**设计约束**：Dart 的 `Type` 对象不提供结构化访问 API（无法编程提取类型参数），因此步骤 2 依赖泛型辅助函数——利用 Dart reified generics 在泛型函数签名中捕获类型参数。详见 Ch3 Bridge 层的类型映射设计。

### 协变检查

CFE 生成的 forwarding stub（`AsExpression`）在字节码中表现为 `CHECK_COVARIANT` 指令（详见 Ch1）。对于 Bridge 类，Dart 编译器自身会在协变赋值场景插入运行时检查，无需解释器额外处理——前提是 Bridge 类以正确的泛型参数实例化。

## 关键约束与边界条件

| 约束 | 值 | 来源 |
|------|-----|------|
| ITA/FTA 栈帧开销 | 每次泛型调用额外 1-2 个引用槽位（8-16 字节） | 引用栈帧布局（rsp+0, rsp+1） |
| TypeArgs 传递方式 | 指针传递（DarticType 已驻留） | 驻留设计保证 |
| TypeRegistry 桶内扫描 | 线性 O(k)，k 为桶内碰撞数（典型 k < 3） | bucket-hash 方案 |
| SuperTypeMap 查找 | O(1) 两级 Map 查找 | 编译器预计算 |
| isSubtypeOf 最坏复杂度 | O(depth * args)，depth 为继承深度，args 为类型参数数量 | 递归检查 + SuperTypeMap 查找 |
| FutureOr 规范化 | 驻留时一次性执行，后续查找 O(1) | TypeRegistry.intern 内部处理 |
| 类型参数最大嵌套深度 | 无硬限制，受栈深度约束（详见 Ch7） | 递归 resolveType 深度 |

## 已知局限与演进路径

| 局限 | 影响 | 演进计划 |
|------|------|---------|
| 无 SubtypeTestCache | 重复的相同类型对检查每次递归计算 | Phase 2：添加 `(sub, sup) → bool` 全局缓存。触发条件：profiling 显示 isSubtypeOf 成为热点 |
| 无实例化缓存 | TypeTemplate 含 TypeParameterType 时每次 resolveType 都重新计算 | Phase 2：缓存 `(template, ITA, FTA) → DarticType`。触发条件：profiling 显示类型实例化成为热点 |
| 跨边界集合类型丢失 | 解释器创建的 `List<dynamic>` 在 VM 侧无法通过 `is List<int>` | Phase 2：预生成类型化工厂（详见"跨边界泛型"节） |
| Record 类型检查未实现 | `is (int, String)` 等结构化类型检查不支持 | Phase 2：补充 RuntimeRecordType、isRecordSubtype 和 RecordShape 映射。触发条件：业务代码需要 Record 类型检查 |
| 静态消除未实现 | 未使用的 FTA 传递和冗余类型检查仍在执行 | Phase 2：编译器优化遍消除。触发条件：profiling 显示类型传递开销显著 |
| Type 对象表示未定义 | `runtimeType` 返回值和 `TypeLiteral` 的运行时表示未明确 | Phase 2：定义 Type 包装对象（包装 DarticType），实现 `==`（驻留后 identical）和 `toString`。触发条件：业务代码需要 `runtimeType` 反射 |

<details>
<summary>附录：参考实现</summary>

```dart
// TypeRegistry.intern —— bucket-hash 驻留核心逻辑
DarticType intern(int classId, List<DarticType> typeArgs, Nullability nullability) {
  final hash = _structuralHash(classId, typeArgs, nullability);
  final bucket = _buckets[hash];
  if (bucket != null) {
    for (final existing in bucket) {
      if (_structuralEquals(existing, classId, typeArgs, nullability)) {
        return existing;
      }
    }
  }
  final type = DarticType._(classId: classId, typeArgs: List.unmodifiable(typeArgs), nullability: nullability);
  type._canonicalHash = hash;
  (_buckets[hash] ??= []).add(type);
  return type;
}
```

</details>
