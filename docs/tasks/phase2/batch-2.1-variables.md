# Batch 2.1: 变量与赋值

## 概览

扩展 Phase 1 的变量支持：处理 ConstantExpression（CFE 常量求值结果）与多种新表达式节点（Not、EqualsNull、EqualsCall、Let、BlockExpression），实现全局变量系统（DarticGlobalTable + LOAD_GLOBAL/STORE_GLOBAL），添加空安全基础（NULL_CHECK + 空值模式）。

**设计参考：** `docs/design/05-compiler.md`（作用域分析、静态字段与顶层变量、常量池类型映射、逻辑与空安全）、`docs/design/03-execution-engine.md`（全局变量惰性初始化）

**依赖：** Phase 1 全部

---

### Task 2.1.1: ConstantExpression 编译与表达式节点扩展

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/compiler/constant_expression_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"常量池类型映射"表和"字面量"表。理解 CFE 在 linked `.dill` 中将 `const` 值包装为 `ConstantExpression(IntConstant(42))` 等形式。Ch5"逻辑与空安全"节中 Not、EqualsNull 的编译策略。Ch5"其他表达式"中 Let 和 BlockExpression 的处理
2. **写测试** — 验证以下场景编译并执行正确：
   - `ConstantExpression` 包装各种 Constant 子类型（IntConstant、DoubleConstant、BoolConstant、StringConstant、NullConstant）→ 生成与对应字面量相同的指令
   - `Not` 表达式（`!condition`）→ 值取反，结果为 value 栈 0/1
   - `EqualsNull`（CFE 优化的 `x == null` / `x != null`）→ 使用 JUMP_IF_NULL/JUMP_IF_NNULL 而非 EQ_REF
   - `EqualsCall`（CFE 的 `a == b` 非 null 比较）→ Phase 2 对基础值类型生成 EQ_INT 或 EQ_REF
   - `Let`（CFE 内部临时绑定）→ 编译 variable 赋值 + 编译 body 表达式
   - `BlockExpression`（带语句的表达式块）→ 编译 body 语句 + 编译 value 表达式
   - const 局部变量声明 `const x = 42;` → 编译为 ConstantExpression 加载
   - 多种 Constant 类型混合使用的端到端场景
3. **实现** — 在 `_compileExpression` 中添加 `ConstantExpression`、`Not`、`EqualsNull`、`EqualsCall`、`Let`、`BlockExpression` 分支。ConstantExpression 根据内部 Constant 类型派发到对应的常量池分区加载指令。Not 编译为操作数 + BIT_XOR 翻转（或等效逻辑）。EqualsNull 使用 JUMP_IF_NULL/NNULL 模式。Let 编译 variable 声明 + body 表达式。扩展 `_inferExprType` 以覆盖新节点
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/constant_expression_test.dart`

---

### Task 2.1.2: 全局变量系统（LOAD_GLOBAL / STORE_GLOBAL）

**产出文件：**
- Create: `lib/src/runtime/global_table.dart`
- Modify: `lib/src/runtime/interpreter.dart`
- Modify: `lib/src/compiler/compiler.dart`
- Modify: `lib/src/bytecode/module.dart`（添加全局变量表元数据）
- Test: `test/runtime/global_table_test.dart`
- Test: `test/compiler/global_variable_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch3"全局变量惰性初始化"节（三态哨兵：`_uninitialized` → `_initializing` → initialized，附参考实现）。Ch5"静态字段与顶层变量"节（编译策略：每个顶层变量分配 globalIndex，初始化器编译为独立 DarticFuncProto）。Ch5"编译产物格式"中全局变量表段。Ch5"变量与静态访问"表中 StaticGet/StaticSet 编译策略
2. **写 DarticGlobalTable 测试** — 验证：
   - 基本 store + load 操作
   - 惰性初始化：首次 load 触发初始化函数执行，后续 load 直接返回缓存值
   - 循环依赖检测：初始化过程中再次 load 同一变量 → 抛 DarticError
   - 初始化失败回滚：初始化函数抛异常后，变量重置为 `_uninitialized`
   - 无初始化器的变量（`initializerFuncId = -1`）：load 未初始化值 → 抛 LateInitializationError
3. **写解释器测试** — 手工构造字节码验证 LOAD_GLOBAL（0xA0）/ STORE_GLOBAL（0xA1）的读写全局变量行为
4. **写编译器测试** — 编译含有顶层变量声明和引用的 Dart 代码并端到端执行：
   - `var x = 42; int main() => x;` → 应生成 LOAD_GLOBAL
   - `var x = 0; void set_x() { x = 1; } int main() { set_x(); return x; }` → STORE_GLOBAL + LOAD_GLOBAL
   - 惰性初始化：`int compute() => 42; var x = compute(); int main() => x;` → 首次 LOAD_GLOBAL 触发 compute()
   - 多个全局变量共存
5. **实现** —
   - DarticGlobalTable 类：slots 数组 + initializerFuncIds + 三态哨兵 + load/store 方法
   - 解释器添加 LOAD_GLOBAL（0xA0，ABx 格式，Bx=globalIndex）和 STORE_GLOBAL（0xA1，ABx 格式）case 分支
   - DarticModule 扩展：添加 globalCount + globalInitializerIds 字段
   - 编译器 Pass 1 收集顶层变量/字段分配 globalIndex。编译初始化器为独立 DarticFuncProto。处理 Kernel StaticGet → LOAD_GLOBAL、StaticSet → STORE_GLOBAL
6. **运行** — `fvm dart analyze && fvm dart test test/runtime/global_table_test.dart test/compiler/global_variable_test.dart`

---

### Task 2.1.3: 空安全基础（NULL_CHECK + 空值模式）

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/runtime/null_check_test.dart`
- Test: `test/compiler/null_safety_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"逻辑与空安全"节中 NullCheck 的编译策略（编译操作数 → NULL_CHECK A）。Ch1 中 NULL_CHECK（0xA7）操作码语义（refStack[A] == null → 抛 TypeError）
2. **写解释器测试** — 手工构造字节码验证 NULL_CHECK：
   - refStack[A] 非 null → 正常 fall-through
   - refStack[A] 为 null → 抛 DarticError（Null check operator used on a null value）
3. **写编译器测试** — 验证：
   - `!` 断言操作符（Kernel NullCheck 节点）→ 应生成 NULL_CHECK 指令
   - null 值触发 null check error，非 null 值正常通过
   - 与其他空安全表达式的组合（`x == null` 和 `x != null` 已在 2.1.1 通过 EqualsNull 覆盖）
   - 端到端执行正确
4. **实现** — 解释器添加 NULL_CHECK（0xA7）case：若 refStack[A] 为 null 则抛出 DarticError。编译器添加 NullCheck 节点编译：编译操作数到引用栈 → 发射 NULL_CHECK
5. **运行** — `fvm dart analyze && fvm dart test test/runtime/null_check_test.dart test/compiler/null_safety_test.dart`

---

## Commit

```
feat: support const evaluation, global variables, and null safety basics
```

**提交文件：** `lib/src/runtime/global_table.dart`（新）+ 修改的 compiler.dart / interpreter.dart / module.dart + 全部新测试

## 核心发现

- **ConstantExpression 高频出现**：CFE 在 linked `.dill` 中广泛使用 `ConstantExpression` 包装 const 值，即使是简单的 `const x = 42` 也会被包装为 `ConstantExpression(IntConstant(42))`。必须支持此节点才能正确编译大多数 Dart 代码。
- **EqualsNull 无 isNot 标志**：SDK 3.10.7 中 `EqualsNull` 只表示 `x == null`，`x != null` 由 CFE 表示为 `Not(EqualsNull(x))`。无需处理 `isNot` 字段。
- **全局变量惰性初始化策略**：初始化器编译为独立 entry 函数（compute → BOX → STORE_GLOBAL → HALT），在 main() 前 eagerly 执行。避免了复杂的 re-entrant dispatch 机制。
- **可空值类型必须走 ref stack**：`int?`、`bool?`、`double?` 不能放 value stack（无法表示 null）。`_classifyStackKind` 必须检查 nullability。
- **ITA/FTA/this 偏移量 bug**：ref stack 的 `initialOffset: 3` 导致 ref 参数传递错位（caller 放 r0 但 callee 读 r3）。Phase 2 移除偏移量修复了调用约定。Phase 3 添加 `this` 时需重新设计参数布局。
- **NullCheck 后需条件 unbox**：`int? x` 经 `x!` 后语义类型为 `int`（value stack），但操作数在 ref stack。编译器需在 NULL_CHECK 后插入 UNBOX_INT/UNBOX_DOUBLE。

## Batch 完成检查

- [x] 2.1.1 ConstantExpression 编译与表达式节点扩展
- [x] 2.1.2 全局变量系统
- [x] 2.1.3 空安全基础
- [x] `fvm dart analyze` 零新警告（仅 pubspec path 依赖警告）
- [x] `fvm dart test` 全部通过（472 tests）
- [x] commit 已提交
- [x] overview.md 已更新
- [x] code review 已完成（0 critical, 3 important → all addressed）
