# Batch 4.2: 泛型核心 (Ch6)

## 概览

实现 Ch6 泛型运行时系统：DarticType 驻留表、ITA/FTA 类型参数传递、TypeTemplate→DarticType 运行时解析、INSTANCEOF/CAST 子类型检查、泛型类/方法编译。这是 Phase 4 最大最核心的 Batch，建议分两阶段推进：4.2.1-4.2.3（运行时基础设施）和 4.2.4-4.2.6（编译器集成 + 端到端）。

**设计参考：** `docs/design/06-generics.md`（完整参考：DarticType、TypeRegistry、ITA/FTA、resolveType、isSubtypeOf、SuperTypeMap、extractType）、`docs/design/01-bytecode-isa.md`（0x78-0x7F 泛型指令组）

**依赖：** Batch 3.6（TypeTemplate 基础设施）、Batch 4.1（mixin/接口的 supertypeIds 完整性，SuperTypeMap 多路径）

---

### Task 4.2.1: DarticType 数据结构 + 驻留表

**产出文件：**
- Create: `lib/src/runtime/dartic_type.dart`
- Create: `lib/src/runtime/type_registry.dart`
- Test: `test/runtime/dartic_type_test.dart`
- Test: `test/runtime/type_registry_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch6"DarticType"结构（DarticInterfaceType: classId + typeArgs + nullability + canonicalHash；DarticFunctionType: typeParamBounds + requiredParamCount + positionalParams + namedParams + returnType + nullability）。Ch6"TypeRegistry"驻留机制（bucket-hash 方案，桶内线性扫描，intern/internFunction 两入口，预注册常用类型）。驻留后 `==` 退化为 `identical()` 的设计意图
2. **写测试** — 验证：
   - DarticInterfaceType 正确持有 classId、typeArgs、nullability
   - DarticFunctionType 正确持有完整函数签名
   - TypeRegistry.intern() 相同参数返回 identical 实例
   - TypeRegistry.intern() 不同参数返回不同实例
   - TypeRegistry.internFunction() 驻留函数类型
   - 预注册类型：`registry.intType`、`registry.doubleType`、`registry.stringType`、`registry.boolType`、`registry.nullType`、`registry.objectType`、`registry.dynamicType`、`registry.voidType`、`registry.neverType` 均可直接访问
   - nullable 变体：`registry.intern(intClassId, [], nullable: true)` 返回 `int?` 类型
   - canonicalHash 正确计算：相同结构的类型哈希相同
3. **实现** —
   - DarticType 定义为 sealed class，两个子类 DarticInterfaceType 和 DarticFunctionType
   - DarticInterfaceType 持有 classId (int)、typeArgs (List<DarticType>)、isNullable (bool)、canonicalHash (int，构造时计算)
   - DarticFunctionType 持有 typeParamBounds (List<DarticType>)、requiredParamCount (int)、positionalParams (List<DarticType>)、namedParams (Map<String, DarticType>)、returnType (DarticType)、isNullable (bool)
   - TypeRegistry 使用 bucket-hash 实现：桶数组 `List<List<DarticType>>`，intern 时计算 hash → 定位桶 → 桶内线性扫描逐字段比较 → 命中返回已有实例 → 未命中创建新实例并插入
   - 预注册：构造器中为 int/double/String/bool/Null/Object/Object?/dynamic/void/Never 创建预驻留实例，提供命名 getter 访问
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/dartic_type_test.dart test/runtime/type_registry_test.dart`

---

### Task 4.2.2: ITA/FTA 槽位 + PUSH_ITA/PUSH_FTA

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`（pushIta、pushFta 指令处理）
- Test: `test/runtime/ita_fta_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch6"ITA/FTA 槽位"（所有帧 rsp+0 为 ITA, rsp+1 为 FTA, rsp+2 为 this/receiver）。PUSH_ITA (0x78) 语义：将当前帧 rsp+0 的 ITA 推送到指定 ref 寄存器。PUSH_FTA (0x79) 语义：将当前帧 rsp+1 的 FTA 推送到指定 ref 寄存器。LOAD_TYPE_ARG (0x7A) 语义：从对象的 DarticType 中提取指定索引的类型参数
2. **写测试** — 手工构造字节码验证：
   - PUSH_ITA 将 rsp+0 处的类型参数列表加载到目标 ref 寄存器
   - PUSH_FTA 将 rsp+1 处的类型参数列表加载到目标 ref 寄存器
   - ITA/FTA 为 null 时的安全处理（非泛型上下文）
   - LOAD_TYPE_ARG 从 DarticObject 的 runtimeType.typeArgs 中按索引提取
   - 调用链中 ITA/FTA 正确传递：caller 的类型参数通过帧传递到 callee
3. **实现** —
   - 解释器 PUSH_ITA (0x78)：从 `refStack[rBase + 0]` 读取 ITA（`List<DarticType>?` 或 `DarticType?`），存入 `refStack[rBase + A]`
   - 解释器 PUSH_FTA (0x79)：从 `refStack[rBase + 1]` 读取 FTA，存入 `refStack[rBase + A]`
   - 解释器 LOAD_TYPE_ARG (0x7A)：从 `refStack[rBase + B]` 取出 DarticObject/DarticType，提取 `typeArgs[C]`，存入 `refStack[rBase + A]`
   - 确保 CALL_VIRTUAL/CALL_STATIC 建立新帧时，ITA/FTA 槽位正确初始化（实例方法：从 receiver 的 runtimeType 设置 ITA；静态/顶层方法：ITA 为 null）
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/ita_fta_test.dart`

---

### Task 4.2.3: INSTANTIATE_TYPE + 类型参数传递

**产出文件：**
- Create: `lib/src/runtime/type_resolver.dart`
- Modify: `lib/src/runtime/interpreter.dart`（instantiateType、createTypeArgs 指令）
- Test: `test/runtime/type_resolver_test.dart`
- Test: `test/runtime/instantiate_type_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch6"resolveType 四分支"算法：1) ConcreteTypeTemplate → 直接返回预驻留 DarticType (O(1))；2) TypeParameterTemplate → 从 ITA/FTA 按 index 取值 (O(1))；3) GenericTypeTemplate → 递归 resolveType 每个 typeArgTemplate 后 intern (O(n))；4) FunctionTypeTemplate → 递归所有内嵌类型后 internFunction。Ch6"CREATE_TYPE_ARGS"（组装类型参数数组，用于泛型调用传参）
2. **写测试** — 验证：
   - ConcreteTypeTemplate 解析：`InterfaceTypeTemplate(intClassId, [])` → registry 中的 `intType`
   - TypeParameterTemplate 从 ITA 解析：ITA = `[intType, stringType]`，`TypeParameterTemplate(0, false)` → `intType`
   - TypeParameterTemplate 从 FTA 解析：FTA = `[doubleType]`，`TypeParameterTemplate(0, true)` → `doubleType`
   - GenericTypeTemplate 递归解析：`InterfaceTypeTemplate(listClassId, [TypeParameterTemplate(0, false)])` + ITA = `[intType]` → `List<int>`
   - 嵌套泛型：`Map<String, List<T>>` 正确递归解析
   - INSTANTIATE_TYPE 指令将常量池中的 TypeTemplate 解析为 DarticType
   - CREATE_TYPE_ARGS 将多个 DarticType 打包为类型参数数组
3. **实现** —
   - `resolveType(TypeTemplate, List<DarticType>? ita, List<DarticType>? fta, TypeRegistry)` 函数：按 TypeTemplate 类型分支处理四种情况，递归调用自身处理嵌套类型
   - NullableTemplate 处理：内部 resolve 后创建 nullable 变体（`registry.intern(classId, args, nullable: true)`）
   - INSTANTIATE_TYPE (0x7B)：A = 目标 ref 寄存器，B = 常量池 ref 索引（TypeTemplate）。从常量池取 TypeTemplate → 从当前帧取 ITA/FTA → resolveType → 存入 refStack[A]
   - CREATE_TYPE_ARGS (0x7C)：组装 A 个 DarticType（从 ref 寄存器连续读取）为 `List<DarticType>`，用于后续 ALLOC_GENERIC 或 PUSH_FTA
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/type_resolver_test.dart test/runtime/instantiate_type_test.dart`

---

### Task 4.2.4: INSTANCEOF / CAST 子类型检查

**产出文件：**
- Create: `lib/src/runtime/subtype_checker.dart`
- Modify: `lib/src/runtime/interpreter.dart`（instanceOf、cast 指令）
- Modify: `lib/src/compiler/compiler.dart`（编译 IsExpression、AsExpression）
- Test: `test/runtime/subtype_checker_test.dart`
- Test: `test/e2e/type_check_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch6"isSubtypeOf"12 条规则（重点先实现规则 1-3, 11-12：identical 快速路径、顶类型、底类型、SuperTypeMap 查找 + 类型参数递归）。Ch6"extractType"（从 DarticObject 提取 DarticType：解释器对象直接读 runtimeType；基本类型 int/double/String/bool/null → 预注册类型）。Kernel 的 IsExpression 和 AsExpression 结构
2. **写测试** — 验证：
   - 基本 instanceof：`obj is SomeClass` → true/false
   - 继承链 instanceof：`sub is SuperClass` → true
   - 接口 instanceof：`obj is Interface` → true（依赖 4.1.1 的 supertypeIds）
   - 基本 cast：`obj as SomeClass` → 成功返回对象
   - cast 失败抛 TypeError
   - 泛型 instanceof：`List<int>() is List<int>` → true（需 DarticType 比较）
   - 子类型规则：`int` is `num` → true（通过 SuperTypeMap）
   - 顶类型：任何对象 `is Object` → true，`is dynamic` → true
   - 底类型：`Never` 是所有类型子类型
   - null 检查：`null is int` → false，`null is int?` → true
   - 编译器端到端：`if (x is String) { ... }` 正确编译为 INSTANTIATE_TYPE + INSTANCEOF + JUMP_IF_FALSE
3. **实现** —
   - SubtypeChecker 类：持有 TypeRegistry + SuperTypeMap 引用，实现 `isSubtypeOf(DarticType sub, DarticType sup)` 方法
   - 先实现核心规则：1（identical）→ 2（顶类型）→ 3（底类型）→ 11（SuperTypeMap 查找）→ 12（类型参数递归检查）。规则 4-10 在 Batch 4.3 完善
   - extractType 函数：DarticObject → 读取 runtimeType 字段；int/double/bool → 从 valueStack 上下文判断使用预注册类型；String/null → 预注册类型；其他宿主对象 → dynamic
   - INSTANCEOF (0x65)：A = 结果 val 寄存器（bool），B = 对象 ref 寄存器，C = 类型 ref 寄存器。extractType(obj) → isSubtypeOf(objType, targetType) → 存入 valStack[A]（1 或 0）
   - CAST (0x66)：类似 INSTANCEOF 但失败时抛 TypeError
   - 编译器：IsExpression → 编译 operand + INSTANTIATE_TYPE(targetType) + INSTANCEOF；AsExpression → 编译 operand + INSTANTIATE_TYPE(targetType) + CAST
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/subtype_checker_test.dart test/e2e/type_check_test.dart`

---

### Task 4.2.5: 泛型类编译

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`（泛型类/构造器编译）
- Modify: `lib/src/runtime/object.dart`（DarticObject.runtimeType 字段）
- Modify: `lib/src/runtime/interpreter.dart`（ALLOC_GENERIC 指令）
- Test: `test/e2e/generic_class_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch6"泛型类编译"。DarticObject.runtimeType 字段（存储完整的 DarticInterfaceType，含类型参数）。ALLOC_GENERIC (0x7D) 语义（类似 NEW_INSTANCE 但额外接收类型参数，设置到新对象的 runtimeType）。编译器在泛型 ConstructorInvocation 中发射类型参数组装 + ALLOC_GENERIC。实例方法入口时从 receiver.runtimeType.typeArgs 加载 ITA
2. **写测试** — 验证：
   - 泛型类实例化：`class Box<T> { T value; Box(this.value); }` → `Box<int>(42).value == 42`
   - runtimeType 正确：`Box<int>(42)` 的 runtimeType 为 `Box<int>`（classId 匹配 + typeArgs = [intType]）
   - 多类型参数：`class Pair<A, B> { A first; B second; Pair(this.first, this.second); }`
   - 泛型嵌套：`Box<Box<int>>(Box<int>(1))` → 类型参数递归正确
   - 泛型方法中使用类型参数：`class Box<T> { bool isType(Object o) => o is T; }` → 类型检查使用 ITA
   - 同一类不同类型参数的多次实例化共存：`Box<int>(1)` 和 `Box<String>('a')` 同时存在
   - 继承泛型类：`class IntBox extends Box<int> { IntBox(int v) : super(v); }`
3. **实现** —
   - DarticObject 增加 `DarticType? runtimeType` 字段（可选，非泛型对象为 null 或基础类型）
   - ALLOC_GENERIC (0x7D)：A = 目标 ref 寄存器，B = classId，C = 类型参数 ref 寄存器。创建 DarticObject + 从 TypeRegistry intern 创建 DarticInterfaceType → 赋值给 runtimeType
   - 编译器 ConstructorInvocation 处理泛型：检查 Class.typeParameters 非空 → 编译类型实参（Kernel InterfaceType.typeArguments）→ 发射 INSTANTIATE_TYPE 序列 + CREATE_TYPE_ARGS → 发射 ALLOC_GENERIC（替代 NEW_INSTANCE）
   - 实例方法入口：编译器检测当前类有 typeParameters → 发射 LOAD_TYPE_ARG 序列从 receiver 提取类型参数到 ITA 槽位
   - SuperTypeMap 条目生成：编译器在 Pass 1c 为每个有泛型超类型的类调用 `buildSuperTypeEntries`（Batch 3.6 已实现），结果存入编译上下文供运行时使用
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/generic_class_test.dart`

---

### Task 4.2.6: 泛型方法编译

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`（泛型方法调用 + FTA 传递）
- Test: `test/e2e/generic_method_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch6"FTA 传递"（泛型方法调用时，调用者组装推断的类型参数为 FTA，通过 CREATE_TYPE_ARGS + 帧传递到 callee 的 rsp+1）。Kernel 中泛型方法表示：`Procedure.function.typeParameters` 非空；MethodInvocation 的 `arguments.types` 包含推断的类型实参。TypeParameterTemplate 的 `isFunctionTypeParam=true` 标志区分 ITA 和 FTA 来源
2. **写测试** — 验证：
   - 泛型顶层函数：`T identity<T>(T x) => x;` → `identity<int>(42) == 42`
   - 泛型实例方法：`class C { T cast<T>(Object o) => o as T; }` → FTA 正确传递
   - 泛型方法中的类型参数使用：`T first<T>(List<T> items) => items[0];` → FTA 用于类型检查
   - 多类型参数方法：`R map<T, R>(T value, R Function(T) f) => f(value);`
   - 泛型类上的泛型方法：`class Box<T> { R transform<R>(R Function(T) f) => f(value); }` → ITA 和 FTA 共存
   - 泛型方法链式调用：`list.map<int>((x) => x + 1).first`
   - 类型参数推断：Kernel CFE 已完成类型推断，`arguments.types` 包含具体类型
3. **实现** —
   - 编译泛型方法调用（InstanceInvocation/StaticInvocation）：检查 `arguments.types` 非空 → 为每个类型实参发射 INSTANTIATE_TYPE → CREATE_TYPE_ARGS 组装 FTA → 将 FTA 放入 callee 帧的 rsp+1 槽位
   - 编译泛型方法体：方法入口不需额外操作（FTA 已在 rsp+1），方法体中 TypeParameterType(isFunctionTypeParam=true) → PUSH_FTA + 按索引访问
   - 闭包中的 FTA 捕获：泛型方法内创建闭包时，FTA 作为额外 upvalue 捕获到 DarticClosure.upvalues 中。闭包执行时从 upvalues 恢复 FTA 到新帧 rsp+1
   - TypeParameterTemplate 解析优先级：`isFunctionTypeParam=true` → 从 FTA 读取；`isFunctionTypeParam=false` → 从 ITA 读取
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/generic_method_test.dart`

---

## Commit

```
feat(generics): add reified generics with DarticType residency
```

**提交文件：** `dartic_type.dart`、`type_registry.dart`、`type_resolver.dart`、`subtype_checker.dart`（新）+ 修改的 compiler.dart + interpreter.dart + object.dart + 全部新测试

## 核心发现

- **TypeRegistry bucket 大小**：初始 64 桶，自动扩展。常用基本类型预注册，命中率高
- **ITA/FTA 在非泛型帧中的开销**：仅占用 rsp+0/rsp+1 两个 ref 槽位（null），零运行时成本
- **ITA 自动加载策略**：选择在 CALL_VIRTUAL 解释器中自动从 `receiver.runtimeType_.typeArgs` 提取到 rsp+0，而非编译器在方法入口发射 bytecode。零 bytecode 膨胀
- **FTA 传递机制**：编译器在调用点发射 `INSTANTIATE_TYPE` + `CREATE_TYPE_ARGS` 组装 FTA，通过 pending arg MOVE 放入 callee rsp+1。复用已有的 arg move 机制，无需新指令
- **`_classToClassId` vs `_typeClassIdLookup` 分离**：避免 core type classIds 污染编译器的 EqualsCall dispatch 和 constructor resolution 等决策
- **TypeParameterType 解析**：`_currentClassTypeParams` (ITA) 和 `_currentFunctionTypeParams` (FTA) 必须同时传递给 `dartTypeToTemplate`，否则 `is T` 中的 T 会退化为 DynamicTemplate（is dynamic 始终为 true）
- **泛型类字段的 operator dispatch** ~~局限~~（已修复）：`_inferExprType` 对 InstanceGet 改用 `expr.resultType`（Kernel 已替换类型参数），对 InstanceInvocation fallback 改用 `expr.functionType.returnType`。同时 `_emitBinaryOp`/`_emitUnaryOp`/`_compileEqualsCall` 等消费端增加 ref-stack 操作数 unbox
- **SubtypeChecker 实现范围**：Phase 1 实现规则 1-3, 11-12（identical 快速路径、顶类型、底类型、SuperTypeMap + 类型参数递归），规则 4-10 留 Batch 4.3

## Batch 完成检查

- [x] 4.2.1 DarticType 数据结构 + 驻留表
- [x] 4.2.2 ITA/FTA 槽位 + PUSH_ITA/PUSH_FTA
- [x] 4.2.3 INSTANTIATE_TYPE + 类型参数传递
- [x] 4.2.4 INSTANCEOF / CAST 子类型检查
- [x] 4.2.5 泛型类编译
- [x] 4.2.6 泛型方法编译
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test` 全部通过
- [x] commit 已提交
- [x] overview.md 已更新
- [x] code review 已完成
