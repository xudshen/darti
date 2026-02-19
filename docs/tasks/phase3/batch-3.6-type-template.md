# Batch 3.6: 泛型编译预备（为 Phase 4 铺路）

## 概览

在 Phase 3 末尾为 Ch6 泛型做编译器基础设施准备：定义 TypeTemplate 数据结构（类型参数、bounds、SuperTypeMap 骨架），建立 Kernel DartType 遍历框架，实现类型参数 bounds 解析与编码。这些基础设施在 Phase 4 Batch 4.2 泛型核心中被实际使用。

**设计参考：** `docs/design/06-generics.md`（TypeTemplate 结构、DartType 遍历、类型参数传递、SuperTypeMap）

**依赖：** Batch 3.2（基础类信息——TypeTemplate 引用 classId）

---

### Task 3.6.1: TypeTemplate 数据结构定义

**产出文件：**
- Create: `lib/src/compiler/type_template.dart`
- Test: `test/compiler/type_template_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch6"TypeTemplate"结构（编译时类型编码，存储在常量池）。TypeTemplate 的变体：InterfaceTypeTemplate（classId + typeArgTemplates）、FunctionTypeTemplate（returnType + paramTypes）、TypeParameterTemplate（指向 ITA/FTA 的索引）、VoidTemplate、DynamicTemplate、NeverTemplate、NullableTemplate（包装内部 TypeTemplate + nullability）
2. **写测试** — 验证：
   - 创建各种 TypeTemplate 变体并验证结构正确
   - InterfaceTypeTemplate 持有 classId 和类型参数列表
   - TypeParameterTemplate 正确引用偏移索引
   - Nullable 包装正确
   - TypeTemplate 可序列化到常量池并反序列化
3. **实现** —
   - 定义 TypeTemplate 抽象基类和各变体子类（sealed class 或抽象类 + 子类）
   - 每个变体包含序列化/反序列化方法
   - 常量池 refs 分区中的存储格式
   - 为 Phase 4 的 `resolveType(ITA, FTA)` 方法预留接口（返回 DarticType）
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/type_template_test.dart`

---

### Task 3.6.2: Kernel DartType 遍历框架

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`（或独立辅助文件）
- Test: `test/compiler/dart_type_visitor_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch6"编译器类型遍历"。Ch5 中 `_inferExprType` 对 DartType 的使用。Kernel 的 DartType 层次结构：InterfaceType、FunctionType、TypeParameterType、VoidType、DynamicType、NeverType、NullType、FutureOrType 等
2. **写测试** — 验证：
   - 将 Kernel InterfaceType（如 `int`, `String`, `List<int>`）转换为 TypeTemplate
   - 将 Kernel FunctionType（如 `int Function(String)`）转换为 TypeTemplate
   - 将 Kernel TypeParameterType 转换为 TypeParameterTemplate
   - VoidType / DynamicType / NeverType 正确映射
   - 嵌套类型（如 `Map<String, List<int>>`）递归遍历正确
3. **实现** —
   - 在编译器中添加 `_dartTypeToTemplate(DartType)` 方法，递归遍历 Kernel DartType 树并构建对应 TypeTemplate
   - InterfaceType → InterfaceTypeTemplate（查找 classId + 递归处理 typeArguments）
   - FunctionType → FunctionTypeTemplate（递归处理 returnType + positionalParameters）
   - TypeParameterType → TypeParameterTemplate（查找类型参数在 ITA/FTA 中的索引）
   - 处理 nullability（Nullability.nullable → NullableTemplate 包装）
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/dart_type_visitor_test.dart`

---

### Task 3.6.3: 类型参数 bounds 解析与编码

**产出文件：**
- Modify: `lib/src/compiler/type_template.dart`
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/compiler/type_bounds_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch6"类型参数 bounds"（每个泛型类/方法的类型参数有上界约束，如 `T extends Comparable<T>`）。SuperTypeMap 骨架（映射 subClassId→superClassId 的类型参数对应关系，用于子类型检查时的类型参数传递）
2. **写测试** — 验证：
   - 提取 Kernel Class 的 typeParameters 和各自 bound
   - 将 bound 转换为 TypeTemplate
   - 默认 bound（无显式 extends）→ Object? TypeTemplate
   - 构建 SuperTypeMap 条目：子类 extends 父类时，子类的类型参数如何映射到父类的类型参数
3. **实现** —
   - 编译器 Pass 1 类遍历时，为每个有 typeParameters 的类提取类型参数信息
   - 将每个 TypeParameter.bound 通过 `_dartTypeToTemplate` 转换为 TypeTemplate
   - SuperTypeMap 骨架：对每个类的 supertype（Kernel Class.supertype.typeArguments），记录子类类型参数到父类类型参数的映射关系
   - 存储到 DarticClassInfo 或独立的类型信息表中（Phase 4 实际使用）
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/type_bounds_test.dart`

---

## Commit

```
feat(compiler): add TypeTemplate infrastructure for generics
```

**提交文件：** `lib/src/compiler/type_template.dart`（新）+ 修改的 compiler.dart + 全部新测试

## 核心发现

- `extractTypeParamBounds` 和 `buildSuperTypeEntries` 作为独立函数添加到 `type_converter.dart`，复用已有的 `dartTypeToTemplate` 进行 bound 和 supertype 类型参数转换。
- Kernel 默认 bound 为 `DynamicType`（非 `Object?`），实现中直接映射为 `DynamicTemplate`。
- `SuperTypeEntry` 数据类持有 subClassId、superClassId 和 typeArgMapping，为 Phase 4 的 isSubtypeOf 规则 11-12 提供编译期预计算数据。
- 平台类（如 Object）不在 classIdLookup 中，`buildSuperTypeEntries` 自动跳过未知超类，避免误生成无效映射条目。
- 自引用 bound（如 `T extends Comparable<T>`）正确编码为 `InterfaceTypeTemplate(classId, [TypeParameterTemplate(0, ITA)])`，因为 `dartTypeToTemplate` 已处理 enclosingClassTypeParams 查找。

## Batch 完成检查

- [x] 3.6.1 TypeTemplate 数据结构定义
- [x] 3.6.2 Kernel DartType 遍历框架
- [x] 3.6.3 类型参数 bounds 解析与编码
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test` 全部通过
- [ ] commit 已提交
- [ ] overview.md 已更新
- [ ] code review 已完成
