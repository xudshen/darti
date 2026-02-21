# Batch 6.2: 高级语言特性

## 概览

实现 Phase 6 所需的高级 Dart 语言特性。根据 Kernel AST 处理方式分为三类：(1) **CFE 已脱糖**（Extension methods、Extension types、Super parameters）——编译器无需特殊处理，验证现有管线能正确编译即可；(2) **需新增编译器 visitor**（Records、Constructor tearoffs、Instance tearoffs）——需要实现新的 Kernel AST 节点访问器和可能的新指令；(3) **需验证脱糖状态**（Pattern matching）——设计文档标注为"已脱糖"但需实际编译测试验证。

**设计参考：** `docs/design/05-compiler.md`（CFE 脱糖状态 line 476-504、Tearoff 编译 line 424-436、Record 编译 line 381-383、Generator 编译 line 456-474）

**依赖：** Phase 5 全部完成（可与 Batch 6.1 并行，建议 6.1 之后）

---

### Task 6.2.1: Extension methods + Extension types（验证）

**产出文件：**
- 可能 Modify: `lib/src/compiler/compiler_expressions.dart`（若发现未处理的 Kernel 节点）
- Test: `test/e2e/extension_methods_e2e_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5 line 486："extension method 已由 CFE 脱糖为 StaticInvocation"。Line 487："Extension types 由 CFE 擦除为底层表示类型"。这意味着编译器看到的 Kernel AST 中不应出现 ExtensionMemberInvocation 等节点——它们已被转换为普通的静态调用和类型操作
2. **写测试** — E2E 验证：
   - 基本 extension method 调用：`extension on int { int get doubled => this * 2; }` → `42.doubled`
   - extension method 带参数：`extension on String { String repeat(int n) => this * n; }`
   - extension type 基本使用：`extension type Meters(int value) { int get inCm => value * 100; }`
   - extension method 在泛型上下文中：`extension<T> on List<T> { T get secondOrFirst => length > 1 ? this[1] : first; }`
   - extension method tearoff
   - extension type 的 is/as 类型检查
3. **实现** —
   - 编译并运行 E2E 测试，预期大部分直接通过（CFE 已脱糖）
   - 若发现编译器报 "unsupported node type" 错误，检查具体 Kernel 节点类型，添加对应 visitor
   - 典型可能问题：extension type 的 representation field access、extension method 的 static dispatch 路由
   - 逐个修复直到 E2E 测试全部通过
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/extension_methods_e2e_test.dart`

---

### Task 6.2.2: Enhanced enums + Enum Bridge

**产出文件：**
- Modify: `lib/src/bridge/core_bindings.dart`（Enum 基类 Bridge）
- 可能 Modify: `lib/src/compiler/compiler_classes.dart`（enum 特殊处理）
- Test: `test/e2e/enhanced_enum_e2e_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5 line 494："enhanced enum 在 Kernel 中表示为 Class + Procedure，无需特殊枚举编译逻辑"。Dart 3 enhanced enum 特性：字段、方法、implements 接口、mixin、泛型。Enum 基类提供 index/name 属性和 values 静态列表。Kernel 中 enum class 的 `isEnum` 标志可用于识别
2. **写测试** — E2E 验证：
   - 基本 enum：`enum Color { red, green, blue }` → Color.red.index == 0、Color.red.name == 'red'
   - Enhanced enum with 字段和方法：`enum Planet { earth(5.97e24); final double mass; const Planet(this.mass); String get info => '$name: $mass kg'; }`
   - Enhanced enum implements 接口
   - Enhanced enum with mixin
   - Enum.values 列表、Enum.values.map
   - enum switch exhaustiveness
3. **实现** —
   - **Enum Bridge**：在 CoreBindings 中注册 Enum 基类绑定：
     - `dart:core::Enum::index#0` → 返回 enum 实例的 index 值
     - `dart:core::Enum::name#0` → 返回 enum 实例的 name 字符串
     - Enum.values 作为 static getter → 返回 List\<EnumType\>
   - **编译器检查**：enum class 在 Kernel 中是普通 Class，构造器和字段编译与普通类一致。需确认：
     - enum 构造器的 `const` 语义正确处理
     - static `values` 字段和 `valueOf` 方法正确编译
     - enum toString() 正确返回 'EnumType.valueName'
   - 如果 Kernel 的 enum 使用平台内部 API（如 `_Enum`），需要检查是否需要额外 Bridge
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/enhanced_enum_e2e_test.dart`

---

### Task 6.2.3: Records — CREATE_RECORD + field access

**产出文件：**
- Modify: `lib/src/bytecode/opcodes.dart`（CREATE_RECORD 操作码，若设计文档定义了新操作码）
- Modify: `lib/src/runtime/interpreter.dart`（CREATE_RECORD case）
- Modify: `lib/src/compiler/compiler_expressions.dart`（RecordLiteral / RecordIndexGet / RecordNameGet visitor）
- Modify: `lib/src/compiler/compiler_constants.dart`（RecordConstant，若未完全实现）
- Test: `test/e2e/records_e2e_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5 line 381-383："RecordLiteral — 编译各字段表达式到连续寄存器 → CREATE_RECORD"。"RecordIndexGet — 位置字段访问"。"RecordNameGet — 命名字段访问"。Ch5 line 163："RecordType TypeTemplate — 已实现（用于类型系统）"。Ch5 line 224："RecordConstant — 已在常量池中处理"。考虑 Dart 3 Record 语义：structural equality（所有字段 == 且形状相同）、immutable、hashCode 基于所有字段
2. **写测试** — E2E 验证：
   - Record 字面量：`var r = (1, 'hello'); r.$1 == 1; r.$2 == 'hello';`
   - Record 命名字段：`var r = (x: 1, y: 2); r.x == 1; r.y == 2;`
   - Record 混合位置和命名字段：`var r = (1, name: 'dart'); r.$1 == 1; r.name == 'dart';`
   - Record 相等性：`(1, 'a') == (1, 'a')` → true；`(1, 'a') == (1, 'b')` → false
   - Record 作为函数返回值：`(int, String) f() => (42, 'hello');`
   - Record 类型注解：`(int, {String name}) r = (1, name: 'dart');`
   - Record 常量：`const r = (1, 2, name: 'three');`
   - Record 嵌套：`var r = ((1, 2), (3, 4));`
3. **实现** —
   - **运行时策略**：使用 host Dart VM 的 Record 类型（pass-through），类似 List/Map/Set 的处理方式。CREATE_RECORD 指令在解释器中创建 host VM Record 对象。
   - **新操作码**（如果 Ch1 ISA 中有预留）或复用 CALL_HOST：
     - 方案 A（新操作码）：CREATE_RECORD A, Bx — A 为目标 ref 寄存器，Bx 为常量池索引（存储 field 数量和命名字段名列表）→ 从 ref 栈连续区域读取字段值 → 创建 Record → 写入 refStack[A]
     - 方案 B（CALL_HOST）：通过 host binding 创建 Record → 类似集合字面量处理
   - **编译器 visitor**：
     - `visitRecordLiteral`：编译各位置字段表达式 + 各命名字段表达式到连续 ref 寄存器 → 记录字段布局（位置数量 + 命名字段名列表）到常量池 → emit CREATE_RECORD
     - `visitRecordIndexGet`：编译 receiver → emit 位置字段访问指令（可通过 CALL_HOST 路由到 Record.$1 getter）
     - `visitRecordNameGet`：编译 receiver → emit 命名字段访问指令（通过 CALL_HOST 路由到 Record.fieldName getter）
   - **RecordConstant 完善**：检查 Phase 4 的 RecordConstant 实现是否完整，若有缺失则补全
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/records_e2e_test.dart`

---

### Task 6.2.4: Constructor tearoffs + Instance tearoffs

**产出文件：**
- Modify: `lib/src/compiler/compiler_expressions.dart`（ConstructorTearOff / RedirectingFactoryTearOff / TypedefTearOff / InstanceTearOff visitor）
- Modify: `lib/src/compiler/compiler_closures.dart`（thunk FuncProto 生成）
- Modify: `lib/src/compiler/compiler_constants.dart`（ConstructorTearOffConstant）
- Test: `test/e2e/tearoff_e2e_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5 line 424-436：
   - ConstructorTearOff（line 433）："生成 thunk DarticFuncProto，body = NEW_INSTANCE + 字段初始化 + return"。通过 CLOSURE A, Bx 指令创建闭包
   - RedirectingFactoryTearOff（line 434）："解析最终目标构造器，然后与 ConstructorTearOff 相同"
   - TypedefTearOff（line 434）："解析 typedef 引用的函数/构造器，然后生成 thunk"
   - InstanceTearOff（line 430）："捕获 receiver 为 upvalue，body = CALL_VIRTUAL target"
   - ConstructorTearOffConstant（line 230）："常量形式，存常量池"
   - 已有参考：StaticTearOff（line 2353-2354）和 FunctionTearOff（line 2470-2472）已实现
2. **写测试** — E2E 验证：
   - 默认构造器 tearoff：`class A { A(int x); } var f = A.new; f(42);`
   - 命名构造器 tearoff：`class A { A.named(int x); } var f = A.named; f(42);`
   - 工厂构造器 tearoff：`class A { factory A.create() => A._(); A._(); } var f = A.create; f();`
   - 泛型构造器 tearoff：`class Box<T> { Box(T v); } var f = Box<int>.new; f(42);`
   - 实例方法 tearoff：`class A { int add(int x) => x + 1; } var a = A(); var f = a.add; f(42) == 43;`
   - Tearoff 相等性：`var a = A(); a.add == a.add` → true（同 receiver 同方法）
   - 重定向工厂 tearoff
   - Typedef tearoff
   - Tearoff 作为回调传递：`[1,2,3].map(int.parse)`
3. **实现** —
   - **ConstructorTearOff**：
     - 在编译期生成 thunk FuncProto：参数列表与构造器匹配，body 为 NEW_INSTANCE + 传参 + RETURN_REF
     - emit CLOSURE A, Bx（Bx = thunk 的 funcId）将 thunk 包装为闭包
   - **RedirectingFactoryTearOff**：
     - 通过 Kernel `extractBody` 或手动跟踪 redirecting chain 找到最终构造器
     - 然后与 ConstructorTearOff 相同
   - **TypedefTearOff**：
     - 解析 typedef 引用的 target → 根据 target 类型（function/constructor）分发到已有 tearoff 逻辑
   - **InstanceTearOff**：
     - 编译 receiver 到 ref 寄存器
     - 生成 thunk FuncProto：receiver 作为 upvalue[0]，body 为 LOAD_UPVALUE receiver → CALL_VIRTUAL target → RETURN
     - emit CLOSURE A, Bx + 绑定 upvalue（receiver）
   - **ConstructorTearOffConstant**：
     - 编译期生成 thunk FuncProto → 存入常量池 refs 分区
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/tearoff_e2e_test.dart`

---

### Task 6.2.5: Pattern matching（验证 + 补全）

**产出文件：**
- 可能 Modify: `lib/src/compiler/compiler_statements.dart`（若发现未脱糖的 Pattern 节点）
- 可能 Modify: `lib/src/compiler/compiler_expressions.dart`（SwitchExpression visitor）
- Test: `test/e2e/pattern_matching_e2e_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5 line 505："CFE 在 Dart 3 中将 pattern matching 脱糖到 if-else 链。PatternSwitchStatement、IfCaseStatement、PatternVariableDeclaration、PatternAssignment、SwitchExpression 在链接平台 .dill 时已转换。" **但备注"需验证"**。验证方法：编译包含 pattern matching 的 Dart 文件，检查 Kernel AST 中是否出现未脱糖的 Pattern 节点
2. **写测试** — E2E 验证（逐步升级复杂度）：
   - switch expression 基本使用：`var x = switch (obj) { int i => 'int: $i', String s => 'str: $s', _ => 'other', };`
   - if-case 语句：`if (obj case int i) { print('int: $i'); }`
   - Record 模式解构：`var (a, b) = (1, 2);`
   - 对象模式：`if (shape case Circle(radius: var r)) { ... }`
   - Guard 模式：`case int i when i > 0`
   - 逻辑与模式：`case (int a, int b) when a > 0 && b > 0`
   - 类型测试模式：`case final int x`
   - Wildcard 模式：`case (_, var second)`
   - 嵌套模式解构
3. **实现** —
   - **验证策略**：先编译简单的 pattern matching 测试文件，观察编译器输出
     - 如果编译通过且执行正确 → CFE 已脱糖，无需额外工作
     - 如果编译器报 "unsupported node type: PatternSwitchStatement" 等错误 → 需要实现对应 visitor
   - **可能需要的 visitor**（按优先级）：
     - `visitSwitchExpression` → 类似 ConditionalExpression，编译各 case 的 when 条件 + body 表达式
     - `visitPatternSwitchStatement` → 类似现有 switch 编译，但 case 条件更复杂
     - `visitIfCaseStatement` → 类似 if，条件为 pattern 匹配
     - `visitPatternVariableDeclaration` → 解构赋值，编译为多个变量声明
   - **注意**：Dart 3.0 的 pattern 在 CFE 中的脱糖程度可能因 SDK 版本不同而异。dartic 使用 dart-sdk 3.10.7 的 Kernel，应该是完全脱糖的
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/pattern_matching_e2e_test.dart`

---

### Task 6.2.6: Super parameters + 剩余特性扫尾

**产出文件：**
- 可能 Modify: `lib/src/compiler/compiler_classes.dart`（若有未处理的 super parameter 节点）
- Test: `test/e2e/super_params_e2e_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5 line 489："super parameters（`super.paramName`）已由 CFE 脱糖为隐式的 super(x: x) 参数转发"。构造器参数编译（line 402-414）已处理 SuperInitializer
2. **写测试** — E2E 验证：
   - 基本 super parameter：`class B extends A { B(super.x); }`
   - 命名 super parameter：`class B extends A { B({required super.name}); }`
   - Super parameter with 额外字段：`class B extends A { final int extra; B(super.x, this.extra); }`
   - Super parameter 类型推断：`class B extends A { B(super.x); }` — x 的类型从 A 的构造器推断
   - Abstract external fields（若 co19 有相关测试）
   - Named arguments anywhere（CFE 脱糖为正常参数顺序）
3. **实现** —
   - 编译 E2E 测试，预期大部分直接通过（CFE 已脱糖）
   - 若发现问题，检查 Kernel AST 中 SuperInitializingFormalParameter 的处理路径
   - 检查是否有 Kernel 3.10.7 版本特有的节点类型需要处理
   - 对 `LanguageFeatures/Abstract-external-fields`（~76 测试）做快速冒烟测试
   - 对 `LanguageFeatures/Named-arguments-anywhere`（若存在）做快速冒烟测试
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/super_params_e2e_test.dart`

---

## Commit

```
feat: support records, constructor tearoffs, extension methods, patterns, and enhanced enums
```

**提交文件：** 修改的 compiler_expressions.dart + compiler_closures.dart + compiler_statements.dart + compiler_classes.dart + compiler_constants.dart + opcodes.dart + interpreter.dart + core_bindings.dart + 全部新测试

## 核心发现

_(执行时填写：extension method 在 Kernel 中是否确认已脱糖、Pattern 的 Kernel 表示是否完全脱糖、Record 的运行时创建策略选择、ConstructorTearOff thunk 生成的复杂度、InstanceTearOff 的 receiver upvalue 绑定、Enhanced enum 的 _Enum 平台内部类处理等)_

## Batch 完成检查

- [ ] 6.2.1 Extension methods + Extension types（验证）
- [ ] 6.2.2 Enhanced enums + Enum Bridge
- [ ] 6.2.3 Records — CREATE_RECORD + field access
- [ ] 6.2.4 Constructor tearoffs + Instance tearoffs
- [ ] 6.2.5 Pattern matching（验证 + 补全）
- [ ] 6.2.6 Super parameters + 剩余特性扫尾
- [ ] `fvm dart analyze` 零警告
- [ ] `fvm dart test` 全部通过
- [ ] commit 已提交
- [ ] overview.md 已更新
- [ ] code review 已完成
