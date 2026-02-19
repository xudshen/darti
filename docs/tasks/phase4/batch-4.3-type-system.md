# Batch 4.3: 类型系统

## 概览

完善 Batch 4.2 中初步实现的子类型检查算法，补齐 isSubtypeOf 的全部 12 条规则（重点：可空性、FutureOr、函数类型），实现空安全相关的编译和运行时支持，以及 CFE 类型提升的正确编译。

**设计参考：** `docs/design/06-generics.md`（isSubtypeOf 规则 4-10、isFunctionSubtype 9 检查、FutureOr 规范化、extractType 宿主对象路径）

**依赖：** Batch 4.2（DarticType、TypeRegistry、SubtypeChecker 基础版、INSTANCEOF/CAST）

---

### Task 4.3.1: 子类型检查算法完善

**产出文件：**
- Modify: `lib/src/runtime/subtype_checker.dart`
- Modify: `lib/src/runtime/type_registry.dart`（FutureOr 规范化）
- Test: `test/runtime/subtype_complete_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch6"isSubtypeOf"规则 4-10：规则 4（可空性拒绝：sub nullable + sup nonNullable → false）、规则 5（Null 类型处理）、规则 6（可空超类型分解：剥离 nullable 后递归）、规则 7-8（FutureOr 作为超类型/子类型的分解规则）、规则 9（函数类型分发）、规则 10（Record 类型分发——Phase 4 暂 stub）。Ch6"isFunctionSubtype"9 条检查（类型参数数量/bounds 互等、返回类型协变、参数逆变、命名参数覆盖）。Ch6"FutureOr 规范化"（驻留时执行：`FutureOr<Never>` → `Future<Never>`, `FutureOr<Object?>` → `Object?` 等）
2. **写测试** — 验证：
   - **规则 4-6 可空性**：`int <: int?` → true；`int? <: int` → false；`Null <: int?` → true；`Null <: int` → false；`int? <: num?` → true（剥离后递归）
   - **规则 7-8 FutureOr**：`int <: FutureOr<int>` → true；`Future<int> <: FutureOr<int>` → true；`String <: FutureOr<int>` → false；`FutureOr<int> <: Object` → true（FutureOr 作为子类型分解：Future<int> <: Object && int <: Object）
   - **规则 9 函数类型**：`int Function(String) <: num Function(Object)` → true（返回类型协变、参数类型逆变）；`void Function(int, int) <: void Function(int)` → false（参数数量）；可选参数/命名参数的子类型关系
   - **FutureOr 规范化**：TypeRegistry 驻留 `FutureOr<Never>` 实际返回 `Future<Never>`；驻留 `FutureOr<Object?>` 返回 `Object?`
   - **边界情况**：`Never <: T` 对任意 T 为 true；`T <: dynamic` 为 true；`T <: void` 为 true
3. **实现** —
   - SubtypeChecker 补齐规则 4-10：按设计文档的规则序号逐条实现，使用 switch/if-else 链按优先级判定
   - isFunctionSubtype 独立方法：检查类型参数数量一致 → bounds 互等（双向 isSubtypeOf）→ 返回类型协变 → 参数数量和类型逆变 → 命名参数覆盖和 required 标志
   - TypeRegistry.intern 增加 FutureOr 规范化逻辑：在 intern 入口处检查是否为 FutureOr classId，按 Ch6 规范化表转换后再驻留
   - 规则 10 Record 类型：暂返回 false（Phase 6 Records 实现后补齐）
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/subtype_complete_test.dart`

---

### Task 4.3.2: 空安全类型检查

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`（NullCheck、nullable 类型编译）
- Modify: `lib/src/runtime/interpreter.dart`（NULL_CHECK 语义完善）
- Test: `test/e2e/null_safety_test.dart`

**TDD 步骤：**

1. **读设计文档** — Kernel 的 NullCheck 节点（`x!` 语法）。nullable 类型在 Kernel 中的表示（InterfaceType.nullability = Nullability.nullable）。编译器现有的 NULL_CHECK opcode (0xA4) 语义。late 变量的 Kernel 表示（LateLowering 由 CFE 完成，生成 sentinel 检查代码）
2. **写测试** — 验证：
   - `x!` 非空断言：非 null 值通过，null 值抛 TypeError
   - nullable 变量赋值：`int? x = null; x = 42;` → 正确存储和读取
   - nullable 参数传递：`void f(int? x) { ... }` → null 和非 null 均可传入
   - `?.` 条件访问：`x?.method()` → null 时跳过调用返回 null
   - `??` 空合并运算符：`x ?? defaultValue` → 已在 Phase 2 实现，验证与泛型类型的交互
   - late 变量：`late int x; x = 42;` → 正确延迟初始化；未初始化访问抛 LateInitializationError
   - required 命名参数：`void f({required int x})` → 缺少参数时编译错误
3. **实现** —
   - NullCheck 编译完善：编译 NullCheck 表达式 → 编译 operand → 发射 NULL_CHECK（0xA4）→ 如果 operand 为 null 抛 TypeError（带类型信息）
   - nullable 类型追踪：编译器 _inferExprType 正确传播 nullability（条件表达式、null 合并等结果可能为 nullable）
   - late 变量：CFE 的 LateLowering 将 `late int x` 转换为带 sentinel 检查的代码。编译器正确编译这些生成的 Kernel 节点（通常是 if-null 检查 + 赋值）
   - `?.` 操作符：已在 Phase 2 部分实现（NullAwareMethodInvocation），确保与泛型类型系统正确交互（结果类型为 T?）
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/null_safety_test.dart`

---

### Task 4.3.3: Flow analysis 类型提升

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`（AsExpression 编译策略优化）
- Test: `test/e2e/type_promotion_test.dart`

**TDD 步骤：**

1. **读设计文档** — Kernel CFE 类型提升机制：`if (x is String)` 后 x 的类型在 then 分支提升为 String，CFE 在 Kernel AST 中插入 AsExpression 标注提升。`if (x != null)` 后 x 提升为 non-nullable 类型。Kernel AsExpression 有 `isTypeError` 和 `isUnchecked` 标志区分显式 `as` 和隐式提升
2. **写测试** — 验证：
   - is-check 后类型提升：`Object x = 'hello'; if (x is String) { return x.length; }` → 成功调用 String.length
   - null-check 后类型提升：`int? x = 42; if (x != null) { return x + 1; }` → 提升为 int
   - 嵌套提升：`if (x is List && x.isNotEmpty) { return x.first; }`
   - 提升失效：`if (x is String) { x = obj; /* 赋值失效提升 */ x.length; /* 报错 */ }`
   - 显式 as-cast：`(obj as String).length` → 成功或抛 TypeError
   - 隐式提升不生成运行时检查：CFE 标记 `isUnchecked=true` 的 AsExpression 编译为 no-op
3. **实现** —
   - AsExpression 编译策略区分三种情况：
     1. `isUnchecked=true`（CFE 类型提升插入的隐式 cast）→ 编译为 no-op（不发射 CAST 指令，仅编译 operand）
     2. `isTypeError=true`（隐式向下转型，如赋值兼容性检查）→ 发射 CAST（失败抛 TypeError）
     3. 显式 `as` 表达式 → 发射 INSTANTIATE_TYPE + CAST
   - 类型提升后的方法调用：CFE 已在 InstanceInvocation 的 interfaceTarget 中使用提升后的类型，编译器无需额外处理（正常编译 CALL_VIRTUAL/GET_FIELD）
   - 值类型的类型提升：`if (x is int)` 后 CFE 可能插入 AsExpression 将 ref 提升为 val，编译器需处理 ref→val 的 UNBOX（如果对象确实在 ref stack）
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/type_promotion_test.dart`

---

## Commit

```
feat: support subtype checking, null safety, and type promotion
```

**提交文件：** 修改的 subtype_checker.dart + type_registry.dart + compiler.dart + interpreter.dart + 全部新测试

## 核心发现

_(执行时填写：isSubtypeOf 规则命中频率分布、FutureOr 规范化在 co19 中的实际触发率、函数类型子类型的逆变验证复杂度、AsExpression isUnchecked 的实际比例等)_

## Batch 完成检查

- [ ] 4.3.1 子类型检查算法完善
- [ ] 4.3.2 空安全类型检查
- [ ] 4.3.3 Flow analysis 类型提升
- [ ] `fvm dart analyze` 零警告
- [ ] `fvm dart test` 全部通过
- [ ] commit 已提交
- [ ] overview.md 已更新
- [ ] code review 已完成
