# Batch 3.1: 函数进阶

## 概览

扩展 Phase 2 的函数支持：实现可选位置参数与命名参数的编译与调用约定，添加默认参数值求值，实现闭包系统（DarticClosure + 上值捕获 + CLOSURE/CALL 指令），支持函数作为一等公民（FunctionDeclaration、FunctionExpression、tearoff）。

**设计参考：** `docs/design/05-compiler.md`（参数编译、闭包编译、上值分析、tearoff 编译策略）、`docs/design/03-execution-engine.md`（CALL 指令语义、CLOSURE 操作码、LOAD_UPVALUE/STORE_UPVALUE、CLOSE_UPVALUE）

**依赖：** Phase 2 全部

---

### Task 3.1.1: 可选位置参数与命名参数

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/compiler/optional_params_test.dart`
- Test: `test/e2e/optional_params_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5 参数编译节。理解 Kernel FunctionNode 的参数结构：`positionalParameters`（List\<VariableDeclaration\>）、`namedParameters`（List\<VariableDeclaration\>）、`requiredParameterCount`（前 N 个位置参数为必需）。理解 Kernel Arguments 中 `positional`（List\<Expression\>）和 `named`（List\<NamedExpression\>）的排列方式——CFE 已将命名参数按名称字母序排列
2. **写测试** — 验证以下场景编译并执行正确：
   - 可选位置参数：`int f(int a, [int b = 0])` 分别用 1 个和 2 个参数调用
   - 多个可选位置参数：`int f(int a, [int b = 0, int c = 0])` 各种参数组合
   - 命名参数：`int f(int a, {int b = 0})` 使用和不使用命名参数调用
   - 多命名参数：`int f({int a = 0, int b = 0, int c = 0})` 仅传部分命名参数
   - required 命名参数：`int f({required int a})` 必须传入
   - 端到端：含可选/命名参数的函数调用结果正确
3. **实现** — 扩展编译器的参数处理逻辑。在函数调用点（StaticInvocation），根据 Arguments 中的实际参数列表和目标函数的形参列表，为缺失的可选位置参数生成默认值加载指令。命名参数需在调用点按目标函数形参的规范顺序排列（Kernel 的 namedParameters 已按名字排序），将 NamedExpression 映射到对应形参槽位。callee 端不需要特殊处理——所有参数在 caller 端已准备好
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/optional_params_test.dart test/e2e/optional_params_test.dart`

---

### Task 3.1.2: 默认参数值

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/e2e/default_params_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5 参数编译节中默认值处理策略。Kernel 中可选参数的 VariableDeclaration.initializer 存储默认值表达式（通常为 ConstantExpression 或字面量）
2. **写测试** — 验证：
   - 整数默认值：`int f([int x = 42]) => x;` 无参调用返回 42
   - 字符串默认值：`String f([String s = 'hello']) => s;`
   - null 默认值：`int? f([int? x]) => x;` 无参调用返回 null
   - bool 默认值：`bool f([bool b = true]) => b;`
   - 多参数混合默认值
   - 命名参数默认值：`int f({int x = 10, int y = 20}) => x + y;`
   - 表达式默认值（CFE 常量折叠后为 ConstantExpression）
3. **实现** — 在调用点为缺失参数编译其默认值表达式。从目标函数的 Kernel FunctionNode 获取对应 VariableDeclaration 的 initializer，编译该表达式并 MOVE 到参数槽位。无 initializer 的可选参数默认为 null（LOAD_NULL）
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/default_params_test.dart`

---

### Task 3.1.3: 闭包（CLOSURE / LOAD_UPVALUE / STORE_UPVALUE / CALL）

**产出文件：**
- Create: `lib/src/runtime/closure.dart`
- Modify: `lib/src/compiler/compiler.dart`
- Modify: `lib/src/runtime/interpreter.dart`
- Test: `test/runtime/closure_test.dart`
- Test: `test/e2e/closure_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch3"CALL 指令"节（DarticClosure 从 refStack[B] 取出，upvalues 注入新帧）。Ch3"CLOSURE"操作码语义（从 funcProto 和当前帧上值创建 DarticClosure）。Ch5"闭包编译"节（上值分析：区分 local capture 和 transitive capture，UpvalueDescriptor 生成）。Ch2"DarticClosure"结构定义
2. **写 DarticClosure 测试** — 验证：
   - DarticClosure 持有 funcProto 引用和 upvalues 数组
   - upvalues 的读写正确（通过数组索引访问）
3. **写解释器测试** — 手工构造字节码验证：
   - CLOSURE（0x70）：从 funcProto 表创建闭包对象，捕获指定上值到 upvalues 数组
   - CALL（0x50）：从 refStack 取出 DarticClosure，建立新帧，将 upvalues 注入帧
   - LOAD_UPVALUE（0x0A）：从当前帧 upvalues[index] 读取值
   - STORE_UPVALUE（0x0B）：写入当前帧 upvalues[index]
4. **写编译器测试** — 端到端验证：
   - 简单闭包：`int f() { int x = 10; int g() => x; return g(); }` → 结果 10
   - 修改捕获变量：`int f() { int x = 0; void inc() { x = x + 1; } inc(); inc(); return x; }` → 结果 2
   - 多层嵌套闭包：外层函数捕获 → 内层函数传递捕获（transitive upvalue）
   - 闭包返回后仍能访问捕获变量（堆逃逸）
5. **实现** —
   - 创建 DarticClosure 类：持有 DarticFuncProto + `List<Object?>` upvalues
   - 编译器添加上值分析：遍历函数体识别对外层作用域变量的引用，标记为 upvalue。区分 isLocal（直接捕获父帧变量）和 !isLocal（传递捕获祖先帧的上值）。生成 UpvalueDescriptor 列表
   - 编译器为 FunctionDeclaration/FunctionExpression 的内部函数生成独立 DarticFuncProto + CLOSURE 指令
   - 编译内部函数体时，对捕获变量使用 LOAD_UPVALUE/STORE_UPVALUE 而非 MOVE_REF/MOVE_VAL
   - 解释器实现 CLOSURE（创建 DarticClosure 对象，从当前帧收集 upvalues）、CALL（取出 DarticClosure，推帧，注入 upvalues）、LOAD_UPVALUE/STORE_UPVALUE（读写 frame.upvalues[index]）
   - **被捕获的值类型变量需要 boxing**：int/double/bool 被闭包捕获时必须提升到 ref stack（BOX_INT/BOX_DOUBLE），因为 upvalue 数组是 `List<Object?>`
6. **运行** — `fvm dart analyze && fvm dart test test/runtime/closure_test.dart test/e2e/closure_test.dart`

> **关键风险**：闭包是 Phase 3 最复杂的子系统之一。被捕获变量的 boxing/unboxing 与 StackKind 分类的交互需要仔细处理。建议优先实现最简场景（只捕获 ref 类型变量），再扩展到值类型变量的 boxing。

---

### Task 3.1.4: 函数作为一等公民（tearoff、传参、返回）

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/e2e/function_value_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"tearoff 编译"节（StaticTearOff、InstanceTearOff、ConstructorTearOff 三种 tearoff 的编译策略）。Ch5"FunctionDeclaration"和"FunctionExpression"编译策略
2. **写测试** — 验证：
   - FunctionDeclaration（局部命名函数）：`int f() { int g(int x) => x * 2; return g(5); }` → 结果 10
   - FunctionExpression（匿名函数/lambda）：`int f() { var g = (int x) => x + 1; return g(3); }` → 结果 4
   - 函数作为参数传递：`int apply(int Function(int) fn, int x) => fn(x); int f() => apply((x) => x * 3, 7);` → 结果 21
   - 函数作为返回值：`int Function(int) maker() { return (int x) => x + 10; } int main() { var g = maker(); return g(5); }` → 结果 15
   - StaticTearOff：`int add(int a, int b) => a + b; int main() { var f = add; return f(1, 2); }` → 结果 3（Kernel 中 StaticTearOff 节点引用目标函数）
   - 高阶函数组合
3. **实现** —
   - FunctionDeclaration：编译为独立 DarticFuncProto，发射 CLOSURE 指令创建闭包对象，绑定到局部变量的 ref 寄存器
   - FunctionExpression：与 FunctionDeclaration 相同，但不绑定名称，结果直接作为表达式值（ref 寄存器）
   - StaticTearOff：生成一个包装 DarticFuncProto（body 内含 CALL_STATIC 到目标函数），发射 CLOSURE 创建闭包对象。无 upvalue 时可优化为全局单例
   - 函数调用：当调用目标为 ref 寄存器中的 DarticClosure 时，生成 CALL 而非 CALL_STATIC
   - Kernel 中区分：StaticInvocation（目标已知，CALL_STATIC）vs LocalFunctionInvocation（局部函数调用，可能为 CALL）
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/function_value_test.dart`

---

## Commit

```
feat: support optional params, closures, and first-class functions
```

**提交文件：** `lib/src/runtime/closure.dart`（新）+ 修改的 compiler.dart + interpreter.dart + 全部新测试

## 核心发现

1. **Open/closed upvalue semantics** — open upvalues 指向 ref stack 的活跃槽位实现变量共享突变；`CLOSE_UPVALUE` 将值拷贝到堆上实现作用域逃逸
2. **Transitive upvalue resolution** — 嵌套闭包（h 在 g 内, g 在 f 内）需要 `isLocal=false` 描述符指向外层闭包的 upvalue 索引，而非祖父帧的寄存器
3. **值类型 boxing** — int/bool/double 被闭包捕获时必须通过 BOX 指令提升到 ref stack，因为 upvalue 数组是 `List<Object?>`
4. **StaticTearOff 优化** — 直接复用目标函数的 funcProto，无需生成 thunk 包装器；前提是 CALL 与 CALL_STATIC 的帧建立语义相同
5. **CLOSE_UPVALUE 在返回前必须执行** — 否则 RETURN 的 `rs.clearRange()` 会将 open upvalue 指向的栈槽清空，导致返回的闭包调用时崩溃
6. **CFE 双重表示** — StaticTearOff 有时为 `StaticTearOff` AST 节点，有时为 `ConstantExpression(StaticTearOffConstant)`，两条路径都需处理
7. **已知限制** — CLOSE_UPVALUE 目前只在函数返回前发射，尚未在块作用域退出时发射（TODO phase3）；闭包的可选命名参数默认值暂不支持（使用 null 代替声明的默认值）

## Batch 完成检查

- [x] 3.1.1 可选位置参数与命名参数
- [x] 3.1.2 默认参数值
- [x] 3.1.3 闭包
- [x] 3.1.4 函数作为一等公民
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test` 全部通过（924 tests）
- [x] commit 已提交（7de5e1a）
- [x] overview.md 已更新
- [x] code review 已完成
