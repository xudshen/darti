# Chapter 5: 泛型系统

## 设计决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 实化策略 | 延迟按需实化 | 对象仅记录 classId + typeArgs 描述符，类型检查按需计算并缓存 |
| RuntimeType | 驻留（canonicalization） | 相同结构共享实例，== 退化为 identical()，缓存键高效 |
| 类型参数传递 | ITA + FTA 栈帧槽位 | 编译期确定偏移，运行时零查找 |
| 跨边界泛型 | 编译器分析实际使用组合，预生成类型化 Bridge | 消除运行时泛型实例化问题 |
| 不实现 | 扁平化 TypeArguments 向量 | Dart VM 的扁平化过于复杂，树形结构已足够 |

## Kernel 中的泛型信息

CFE 已完成所有类型推断，解释器无需重做。关键节点：

| Kernel 节点 | 解释器关注点 |
|-------------|------------|
| `InterfaceType` | 携带 `classReference` + `typeArguments`，是 `List<int>` 的表示 |
| `FunctionType` | 携带 `typeParameters`（泛型函数形参）和参数/返回类型 |
| `TypeParameterType` | 引用作用域内的类型参数，使用 de Bruijn 风格索引 |
| `FutureOrType` | `FutureOr<T>` 特殊处理 |
| `RecordType` | Dart 3 记录类型 |

方法调用中推断的类型参数已填入 `Arguments.types`。编译器只需读取并传播。

## RuntimeType 驻留系统

### 数据结构

```dart
class RuntimeType {
  final int classId;
  final List<RuntimeType> typeArgs;  // 驻留后的子类型引用
  final Nullability nullability;

  // 驻留后由 TypeRegistry 设置
  late final int _canonicalHash;

  RuntimeType._({
    required this.classId,
    required this.typeArgs,
    required this.nullability,
  });
}

enum Nullability { nonNullable, nullable, legacy }
```

### TypeRegistry（驻留表）

```dart
class TypeRegistry {
  final Map<int, List<RuntimeType>> _buckets = {};

  /// 常用类型预注册
  late final RuntimeType intType = _intern(RuntimeType._(classId: ClassIds.int, typeArgs: const [], nullability: Nullability.nonNullable));
  late final RuntimeType doubleType = _intern(RuntimeType._(classId: ClassIds.double, typeArgs: const [], nullability: Nullability.nonNullable));
  late final RuntimeType stringType = _intern(RuntimeType._(classId: ClassIds.string, typeArgs: const [], nullability: Nullability.nonNullable));
  late final RuntimeType boolType = _intern(RuntimeType._(classId: ClassIds.bool, typeArgs: const [], nullability: Nullability.nonNullable));
  late final RuntimeType dynamicType = _intern(RuntimeType._(classId: ClassIds.dynamic_, typeArgs: const [], nullability: Nullability.nullable));
  late final RuntimeType objectNullableType = _intern(RuntimeType._(classId: ClassIds.object, typeArgs: const [], nullability: Nullability.nullable));
  late final RuntimeType neverType = _intern(RuntimeType._(classId: ClassIds.never_, typeArgs: const [], nullability: Nullability.nonNullable));

  /// 驻留：相同结构返回同一实例（桶链处理哈希碰撞）
  RuntimeType intern(int classId, List<RuntimeType> typeArgs, Nullability nullability) {
    final hash = _structuralHash(classId, typeArgs, nullability);
    final bucket = _buckets[hash];
    if (bucket != null) {
      for (final existing in bucket) {
        if (_structuralEquals(existing, classId, typeArgs, nullability)) {
          return existing;  // 结构匹配，返回驻留实例
        }
      }
    }
    // 无匹配，创建新类型并加入桶
    final type = RuntimeType._(classId: classId, typeArgs: List.unmodifiable(typeArgs), nullability: nullability);
    type._canonicalHash = hash;
    (_buckets[hash] ??= []).add(type);
    return type;
  }

  bool _structuralEquals(RuntimeType existing, int classId, List<RuntimeType> typeArgs, Nullability nullability) {
    if (existing.classId != classId) return false;
    if (existing.nullability != nullability) return false;
    if (existing.typeArgs.length != typeArgs.length) return false;
    for (int i = 0; i < typeArgs.length; i++) {
      if (!identical(existing.typeArgs[i], typeArgs[i])) return false;  // 子类型已驻留，用 identical
    }
    return true;
  }

  int _structuralHash(int classId, List<RuntimeType> typeArgs, Nullability nullability) {
    var hash = classId * 31 + nullability.index;
    for (final arg in typeArgs) {
      hash = hash * 31 + identityHashCode(arg);  // 子类型已驻留，用 identityHashCode
    }
    return hash;
  }
}
```

驻留后：
- `==` 退化为 `identical()`（O(1)）
- `hashCode` 使用 `identityHashCode`（O(1)）
- SubtypeTestCache 的键比较极快

## 类型参数传递

### 栈帧中的 ITA 和 FTA

每个栈帧预留两个引用栈槽位：

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

### ITA 加载

实例方法入口时，从 receiver 的 RuntimeType 提取 ITA。编译器在方法入口生成序列：

```
// 将 receiver 的类型参数加载到 ITA 槽位
// 编译器根据类的 typeArgs 数量生成对应数量的 LOAD_TYPE_ARG
LOAD_TYPE_ARG  rITA_0, rReceiver, 0   // rITA_0 = receiver.runtimeType.typeArgs[0]
LOAD_TYPE_ARG  rITA_1, rReceiver, 1   // rITA_1 = receiver.runtimeType.typeArgs[1] (如有)
// ... 按类型参数数量展开
```

对于无泛型参数的类，此序列为空。对于单类型参数类（如 `List<T>`），仅一条 `LOAD_TYPE_ARG` 指令。

### FTA 传递

泛型方法调用时，调用者将推断的类型参数作为 FTA 推入新帧：

```dart
// 源码: myList.map<String>((e) => e.toString())
// 编译为:
CREATE_TYPE_ARGS  rFTA, 1          // FTA = [String]
PUSH_FTA          rFTA             // 设置被调用帧的 FTA 槽位
CALL_VIRTUAL      rResult, rList, 'map'
```

### 嵌套泛型函数的 FTA 连接

多层泛型函数嵌套时，FTA 是所有封闭泛型函数类型参数的连接向量：

```dart
class Box<A> {
  void method<B>() {
    void inner<C>() {
      // 需要访问 A (ITA[0]), B (FTA[0]), C (FTA[1])
    }
  }
}
```

编译器在编译 `inner` 时知道 FTA 布局为 `[B, C]`（B 从外层 method 的 FTA[0] 捕获，C 是 inner 自己的）。TypeParameterType 的 de Bruijn 索引直接映射到 FTA 偏移。

### 闭包中的类型参数捕获

闭包在泛型上下文中创建时，捕获当前的 ITA 和 FTA：

```dart
class ClosureObject {
  final FuncProto function;
  final List<Upvalue> upvalues;
  final RuntimeType? capturedITA;   // 创建时的 ITA
  final List<RuntimeType>? capturedFTA;  // 创建时的 FTA（连接向量）
}
```

闭包执行时，capturedITA / capturedFTA 恢复到新帧的对应槽位。

## is / as 类型检查

### 子类型检查策略

初期使用直接子类型计算（递归遍历类层级 + 类型参数匹配 + 可空性/Null/FutureOr 特殊规则）。调用点缓存和全局缓存留待 profiling 后添加。

### 子类型检查算法

```dart
bool isSubtypeOf(RuntimeType sub, RuntimeType sup) {
  // 驻留后直接 identical 比较
  if (identical(sub, sup)) return true;

  // 顶类型快速路径
  if (identical(sup, typeRegistry.dynamicType)) return true;
  if (identical(sup, typeRegistry.objectNullableType)) return true;

  // 底类型
  if (identical(sub, typeRegistry.neverType)) return true;

  // 可空性检查
  if (sub.nullability == Nullability.nullable &&
      sup.nullability == Nullability.nonNullable) {
    // 例外：Null <: Never? 等已由底类型规则处理
    // T? <: S（S 非空）→ 需要 T <: S 且 Null <: S，此处直接拒绝
    return false;
  }

  // Null 类型特殊处理
  if (sub.classId == ClassIds.null_) {
    // Null <: T? → true（对任意 T）
    return sup.nullability == Nullability.nullable;
  }

  // 非空到可空提升：T <: T?
  if (sup.nullability == Nullability.nullable &&
      sub.nullability == Nullability.nonNullable &&
      sub.classId == sup.classId) {
    // 快速路径：相同 classId，检查类型参数
    if (sub.typeArgs.length == sup.typeArgs.length) {
      bool match = true;
      for (int i = 0; i < sub.typeArgs.length; i++) {
        if (!identical(sub.typeArgs[i], sup.typeArgs[i])) { match = false; break; }
      }
      if (match) return true;
    }
  }

  // 查找 sub 在 sup 类层级中的对应超类型
  final superTypeArgs = _findSuperTypeArgs(sub.classId, sup.classId);
  if (superTypeArgs == null) return false;  // 无继承关系

  // 用 sub 的类型参数实例化超类型参数
  final instantiated = _instantiate(superTypeArgs, sub.typeArgs);

  // 递归检查每个类型参数（协变）
  for (int i = 0; i < sup.typeArgs.length; i++) {
    if (!isSubtypeOf(instantiated[i], sup.typeArgs[i])) return false;
  }
  return true;
}
```

### TypeParameterType 解析

`INSTANCEOF` / `CAST` 指令的目标类型可能包含 `TypeParameterType` 引用（如 `value is T`，其中 T 是泛型函数的类型参数）。运行时必须在调用 `isSubtypeOf` 之前将类型模板中的 `TypeParameterType` 解析为具体的 `RuntimeType`。

解析路径：

```dart
/// 将类型模板中的 TypeParameterType 解析为具体类型
RuntimeType resolveType(
  TypeTemplate template,
  List<RuntimeType>? ita,  // 类的实例化类型参数
  List<RuntimeType>? fta,  // 函数的类型参数
) {
  if (template is ConcreteTypeTemplate) {
    // 已是具体类型（如 int, String），直接返回驻留实例
    return template.runtimeType;
  }

  if (template is TypeParameterTemplate) {
    // TypeParameterType：de Bruijn 索引 → ITA/FTA 查找
    if (template.isClassTypeParam) {
      return ita![template.index];   // 类型参数来自类（ITA）
    } else {
      return fta![template.index];   // 类型参数来自泛型函数（FTA）
    }
  }

  if (template is GenericTypeTemplate) {
    // 泛型类型（如 List<T>）：递归解析类型参数
    final resolvedArgs = [
      for (final arg in template.typeArgTemplates)
        resolveType(arg, ita, fta),
    ];
    return typeRegistry.intern(
      template.classId, resolvedArgs, template.nullability);
  }

  throw DarticInternalError('Unknown type template: $template');
}
```

INSTANCEOF 指令的完整执行流（以 `value is T` 为例）：

```dart
case OpCode.INSTANCEOF:
  // INSTANCEOF A, B, Cx — valueStack[A] = refStack[B] is type[Cx] ? 1 : 0
  final typeTemplate = constPool.refs[cx] as TypeTemplate;
  // 用当前帧的 ITA/FTA 解析类型参数引用
  final targetType = resolveType(typeTemplate, frame.ita, frame.fta);
  final objType = extractType(refStack[b], typeRegistry);
  valueStack[a] = isSubtypeOf(objType, targetType) ? 1 : 0;
```

这确保了泛型函数体内的 `value is T` 在运行时正确解析为调用者传入的实际类型参数。编译器在生成 INSTANCEOF 时，将目标类型编码为 `TypeTemplate`（可能含 `TypeParameterTemplate`），由运行时的 `resolveType` 延迟绑定。

### TypeParameterType 边界约束

当子类型检查涉及有界类型参数时（如 `<T extends num>`），需要在 `isSubtypeOf` 中处理类型参数的边界：

```dart
// 在 isSubtypeOf 中，当 sub 来自已解析的 TypeParameterType 时，
// 其实际类型由 resolveType 替换为调用者传入的具体类型。
// 但函数类型的子类型检查需要验证类型参数边界的协变/逆变关系。

// 示例：检查 void Function<T extends num>(T) <: void Function<U extends Object>(U)
// 需要验证 num <: Object（边界的协变检查）
bool isFunctionSubtype(RuntimeFunctionType sub, RuntimeFunctionType sup) {
  // 类型参数数量必须一致
  if (sub.typeParams.length != sup.typeParams.length) return false;

  // 类型参数边界检查：sub 的边界必须是 sup 边界的子类型
  for (int i = 0; i < sub.typeParams.length; i++) {
    if (!isSubtypeOf(sub.typeParams[i].bound, sup.typeParams[i].bound)) {
      return false;
    }
  }

  // 返回类型：协变
  if (!isSubtypeOf(sub.returnType, sup.returnType)) return false;

  // 参数类型：逆变
  for (int i = 0; i < sup.positionalTypes.length; i++) {
    if (!isSubtypeOf(sup.positionalTypes[i], sub.positionalTypes[i])) return false;
  }
  return true;
}
```

编译器需要在 `RuntimeFunctionType` 中保留类型参数边界信息（`TypeParam.bound`），运行时 `resolveType` 在解析 `FunctionType` 模板时同时解析边界。

### FutureOr\<T\> 特殊处理

`FutureOr<T>` 不是普通的接口类型，子类型检查需要拆分处理：

```dart
// 在 isSubtypeOf 主流程中插入 FutureOr 分支：

// FutureOr 作为超类型：sub <: FutureOr<T> ⟺ sub <: Future<T> || sub <: T
if (sup.classId == ClassIds.futureOr) {
  final futureType = typeRegistry.intern(
    ClassIds.future, sup.typeArgs, sup.nullability);
  return isSubtypeOf(sub, futureType) ||
         isSubtypeOf(sub, sup.typeArgs[0]);
}

// FutureOr 作为子类型：FutureOr<T> <: sup ⟺ Future<T> <: sup && T <: sup
if (sub.classId == ClassIds.futureOr) {
  final futureType = typeRegistry.intern(
    ClassIds.future, sub.typeArgs, sub.nullability);
  return isSubtypeOf(futureType, sup) &&
         isSubtypeOf(sub.typeArgs[0], sup);
}
```

### 类型规范化

TypeRegistry 在驻留时执行类型规范化，确保等价类型共享实例：

```
FutureOr<Never>   → Future<Never>
FutureOr<Object?> → Object?
FutureOr<Object>  → Object
FutureOr<dynamic> → dynamic
FutureOr<void>    → void
FutureOr<Null>    → Future<Null>?
FutureOr<T?>      → FutureOr<T>?（可空性提升到外层）
Null              → Never?（在可空性层面）
```

### 函数类型子类型检查

函数类型的参数是**逆变**的，返回类型是**协变**的，类型参数边界是**协变**的。完整算法见上方「TypeParameterType 边界约束」节的 `isFunctionSubtype`。

### Record 类型子类型检查

> **Phase 2**：Dart 3 Record 类型的子类型检查基于结构化比较（字段数量 + 字段类型 + 命名字段名），与接口类型的名义子类型检查不同。Phase 1 中 Record 字面量可创建和访问字段，但 `is (int, String)` 等类型检查不支持。需要补充：
>
> 1. `RuntimeRecordType` 数据结构（位置字段类型列表 + 命名字段映射）
> 2. `isRecordSubtype` 算法（逐字段协变检查 + 命名字段集合包含关系）
> 3. `RecordShape`（Ch1 `CREATE_RECORD` 的 Bx 常量池条目）到 `RuntimeRecordType` 的映射

### _findSuperTypeArgs

编译器预计算每个类的**超类型参数映射表**：对于 `class StringList extends List<String>`，映射为 `List → [String]`。运行时直接查表。

```dart
// 编译期生成的超类型映射
// classId → { superClassId → typeArgTemplate }
final Map<int, Map<int, List<TypeArgTemplate>>> _superTypeMap;
```

`TypeArgTemplate` 可以是具体类型（如 `String`）或类型参数引用（如 `T` → "取 ITA[0]"）。

## 跨边界泛型

### 解释器 → VM

初期统一使用 `List<dynamic>.from()` 等动态类型兜底。

**已知局限**：解释器创建的集合跨边界传递时，VM 侧的 `is List<int>` 等泛型类型检查会失败（运行时类型为 `List<dynamic>`），功能不受影响但违反静态类型约束。

**Phase 1 Workaround**：业务代码中避免对跨边界集合做精确泛型类型检查。

> **Phase 2**：为高频泛型组合预生成类型化创建路径。Bridge 生成器分析解释器代码中的集合创建点，为 `List<int>`、`List<String>`、`Map<String, dynamic>` 等常见组合生成专用工厂，确保跨边界后 `is` 检查正确。

### VM → 解释器

VM 对象进入解释器时，通过类型提取器获取 RuntimeType：

```dart
RuntimeType extractType(Object obj, TypeRegistry reg) {
  if (obj is int) return reg.intType;
  if (obj is double) return reg.doubleType;
  if (obj is String) return reg.stringType;
  if (obj is bool) return reg.boolType;
  if (obj is List) return _extractListType(obj, reg);
  // ...
  return reg.dynamicType;  // 未知类型退化为 dynamic
}

RuntimeType _extractListType<E>(List<E> list, TypeRegistry reg) {
  // 利用 Dart reified generics：E 在运行时是具体类型
  final elemType = _resolveTypeParam<E>(reg);
  return reg.intern(ClassIds.list, [elemType], Nullability.nonNullable);
}
```

### 协变检查

CFE 生成的 forwarding stub（`AsExpression`）在字节码中表现为 `CHECK_COVARIANT` 指令。对于 Bridge 类，Dart 编译器自身会在协变赋值场景插入运行时检查，无需解释器额外处理——前提是 Bridge 类以正确的泛型参数实例化。

## 性能优化

### 类型参数传递开销

每次泛型调用额外传递 1-2 个 RuntimeType 引用（ITA/FTA），约 8-16 字节栈空间。由于 RuntimeType 已驻留，传递的是指针而非深拷贝。

### 实例化缓存

> **Phase 2**：当 Kernel 类型模板含 TypeParameterType 引用时，需要用 ITA/FTA 实例化。初期每次实例化直接计算，缓存留待 profiling 显示类型实例化成为热点时引入。

### 静态消除

> **Phase 2**：编译器可省略未使用的 FTA 传递和冗余类型检查，具体消除规则留待实现阶段确定。
