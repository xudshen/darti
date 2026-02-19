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

- **FutureOr-to-FutureOr 子类型**: 设计文档规则 7-8 不能直接推导 `FutureOr<S> <: FutureOr<T>`（当 `S <: T`），需要在规则 7 增加特殊处理（直接检查 `S <: T`），否则 `FutureOr<int> <: FutureOr<num>` 会错误返回 false
- **设计文档测试用例错误**: 规则 9 测试用例 `int Function(String) <: num Function(Object)` 实际应为 false（参数逆变：需要 `Object <: String`），正确的测试应为 `int Function(Object) <: num Function(String)`
- **CFE 类型提升机制**: CFE 的 flow-analysis 类型提升使用 `VariableGet.promotedType`，不使用 `AsExpression`。`AsExpression.isUnchecked=true` 主要用于 extension type 表示类型访问
- **EqualsNull value-stack 操作数**: CFE 链式 `??` 降糖会产生内层 `EqualsNull` 节点操作数已在 value 栈上（类型被窄化为非空），需特殊处理（直接返回 false，因为 value 栈值不可能为 null）
- **nullable value-type return boxing**: 函数返回类型为 `int?`（ref 栈）但 return 表达式为 value 栈值时，需要 box 后 RETURN_REF

## Batch 完成检查

- [x] 4.3.1 子类型检查算法完善
- [x] 4.3.2 空安全类型检查
- [x] 4.3.3 Flow analysis 类型提升
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test` 全部通过（1512 tests）
- [x] commit 已提交
- [x] overview.md 已更新
- [x] code review 已完成
- [x] code review 修复已提交

## Code Review 修复

Code review 发现 5 个设计限制（L1-L5），其中 L1/L2/L3 已修复，L5 推迟。

### L1: Block/For 作用域退出发射 CLOSE_UPVALUE — ✅ 已修复

**问题**：闭包捕获的 block-local 变量在 block 退出后寄存器被复用，闭包读到脏数据。

**修复**：
- `scope.dart` 新增 `localDeclarations` getter，暴露当前 scope 直接声明的变量
- `compiler_statements.dart` 新增 `_emitCloseUpvaluesForScope()` 方法，扫描被捕获变量的最小 ref 寄存器编号
- 在 `_compileBlock()` 和 `_compileForStatement()` 的 `_scope.release()` 前调用
- 新增 2 个 e2e 测试（block-scoped 闭包逃逸后读取正确值）

### L2: 值类型 receiver 调用非特化方法时 boxing — ✅ 已修复

**问题**：`_compileVirtualCall`/`_compileInstanceGetterCall`/`_compileInstanceSetterCall` 丢弃 receiver 的 `ResultLoc`，若 receiver 为值类型则未 boxing。

**修复**：
- 三处将 `final (receiverReg, _)` 改为 `var (receiverReg, receiverLoc)` 并加入 boxing 检查
- 当 `receiverLoc == ResultLoc.value` 时调用 `_emitBoxToRef()` 将值提升到引用栈

### L3: Typed catch 支持 — ✅ 已修复

**问题**：`catchType` 始终为 -1（catch-all），不支持 `on SomeType catch (e)` 语法。

**修复**：
- `module.dart` 更新 `catchType` 文档语义（-1 = catch-all，>= 0 = 常量池 TypeTemplate 索引）
- `compiler_statements.dart` `_compileTryCatch()` 编译 guard 类型为 TypeTemplate 写入常量池
- `interpreter.dart` `_findHandler()` 扩展为接受异常对象参数，通过 `resolveType` + `isSubtypeOf` 做类型匹配
- 注意：Dart 3 sound null safety 中 plain `catch(e)` 的 guard 是 `Object`（非 `DynamicType`），需同时视为 catch-all
- 新增 5 个 e2e 测试（typed catch 匹配、非匹配 fallthrough、多 catch 子句顺序、子类匹配、catch-all 回归）
- 新增 1 个 compiler-level 测试（catchType 字段值验证）

### L5: TryFinally 字节码重复 — 推迟

**理由**：当前实现功能正确，仅字节码体积冗余。修复需引入新的控制流机制（subroutine call 或条件 rethrow flag），收益不足以 justify 复杂度。Phase 4+ 有更高优先级功能待实现。

### 发现的前置 bug

- **for-loop 变量闭包捕获**：for-loop 条件字节码在变量 promotion（值栈 → 引用栈）之前发射，导致条件始终读取 stale 值寄存器。此问题存在于 L1 修复之前，需单独修复（涉及 for-loop 编译流程重构）。
