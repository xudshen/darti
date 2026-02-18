# Batch 1.4: 最小编译器 (Ch5)

## 概览

实现 Ch5 编译器的最小子集：Kernel AST 遍历骨架、字面量和算术表达式编译、ReturnStatement/ExpressionStatement 编译、函数编译（参数 + 局部变量 + 寄存器分配）。最终通过 Dart 源码 → Kernel → 字节码 → 执行的端到端测试验证。

**设计参考：** `docs/design/05-compiler.md`

**依赖：** Batch 1.1, 1.2, 1.3

---

### Task 1.4.1: Kernel AST 遍历骨架

**产出文件：**
- Create: `lib/src/compiler/compiler.dart`
- Create: `lib/src/compiler/bytecode_emitter.dart`
- Test: `test/compiler/compiler_skeleton_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"编译管线总览"节和"Kernel 加载"节。了解输入为 linked-platform `.dill`，使用 `package:kernel` 的 `BinaryBuilder` 解析。编译器遍历 `Component` → `Library` → `Class` → `Procedure` → `FunctionNode`
2. **写测试** — 使用 `fvm dart compile kernel` 将简单 Dart 源码编译为 `.dill` → 用 `package:kernel` 的 `BinaryBuilder` 加载 → 验证能遍历到 `main` 函数的 `FunctionNode`；BytecodeEmitter 能发射指令到 `Uint32List` 并正确跟踪 PC
3. **实现** — DarticCompiler 类（接受 `Component`）+ `compile()` 方法遍历 Libraries/Procedures。BytecodeEmitter 类封装 `List<int>` 缓冲区 + `emit(int instruction)` + `currentPC` + `patchJump(int offset)` 回填接口
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/compiler_skeleton_test.dart`

> 注意：测试中编译 `.dill` 文件需要调用 `fvm dart compile kernel`，考虑使用 `Process.run` 在 `setUp` 中动态编译测试 Dart 文件，或在 `test/fixtures/` 预放置编译好的 `.dill`

---

### Task 1.4.2: 编译字面量表达式

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/compiler/literal_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"字面量"表格，了解 IntLiteral/DoubleLiteral/BoolLiteral/StringLiteral/NullLiteral 的编译策略
2. **写测试** — 将简单 Dart 函数编译为字节码并验证指令序列：
   - `int f() => 42;` → 应生成 `LOAD_INT A, 42` + `RETURN_VAL A`
   - `int f() => 100000;` → 大整数超出 sBx 范围，应生成 `LOAD_CONST_INT A, Bx` + `RETURN_VAL A`（常量池中有 100000）
   - `bool f() => true;` → 应生成 `LOAD_TRUE A` + `RETURN_VAL A`
   - `String f() => 'hello';` → 应生成 `LOAD_CONST A, Bx` + `RETURN_REF A`（refs 常量池中有 'hello'）
   - `Object? f() => null;` → 应生成 `LOAD_NULL A` + `RETURN_REF A`
3. **实现** — 在 compiler 中实现 `visitIntLiteral`/`visitBoolLiteral`/`visitStringLiteral`/`visitNullLiteral` 方法，根据 Ch5 规则选择指令和常量池分区
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/literal_test.dart`

---

### Task 1.4.3: 编译算术表达式

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/compiler/arithmetic_compile_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"调用表达式"节中的 `InstanceInvocation` 编译策略。在 Kernel AST 中，`a + b` 表示为 `InstanceInvocation(receiver=a, name='+', arguments=[b])`，对于 `int` 类型操作数，编译器应特化为 `ADD_INT` 等直接指令而非 `CALL_VIRTUAL`
2. **写测试** — 编译简单算术函数并验证：
   - `int f(int a, int b) => a + b;` → 应生成 `ADD_INT`（而非 CALL_VIRTUAL）
   - `int f(int a, int b) => a - b;` → `SUB_INT`
   - `int f(int a, int b) => a * b;` → `MUL_INT`
   - `int f(int a, int b) => a ~/ b;` → `DIV_INT`
   - `int f(int a, int b) => a % b;` → `MOD_INT`
   - `int f(int a) => -a;` → `NEG_INT`
   - 复合表达式 `int f(int a, int b, int c) => a + b * c;` → 临时寄存器分配正确
3. **实现** — 在 `visitInstanceInvocation` 中检查 receiver 的静态类型。若为 `int` 且 `name` 是算术运算符（+/-/*/~//% 等），生成特化指令（`ADD_INT` 等）。否则标记 TODO 留给 Phase 3 实现 `CALL_VIRTUAL`
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/arithmetic_compile_test.dart`

---

### Task 1.4.4: 编译语句（ReturnStatement, ExpressionStatement）

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/compiler/statement_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"语句编译补充"节中 ReturnStatement 和 ExpressionStatement 的编译策略，以及"逻辑与空安全"表格中的 `Throw` 处理
2. **写测试** — 验证：
   - `ReturnStatement` 根据返回类型选择正确的 RETURN 指令：int → `RETURN_VAL`，Object/String/其他引用 → `RETURN_REF`，void/无返回值 → `RETURN_NULL`
   - `ExpressionStatement` 编译表达式后释放临时寄存器
   - 多语句函数（`int f() { var x = 1; return x; }`）→ 变量声明 + 赋值 + 返回的指令序列正确
3. **实现** — `visitReturnStatement`（根据 StackKind 选择 RETURN_VAL/RETURN_REF/RETURN_NULL）、`visitExpressionStatement`、`visitVariableDeclaration`（分配寄存器 + 编译初始化器）、`visitVariableGet`/`visitVariableSet`（读写寄存器）
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/statement_test.dart`

---

### Task 1.4.5: 编译函数（参数 + 局部变量 + 寄存器分配）

**产出文件：**
- Create: `lib/src/compiler/register_allocator.dart`
- Create: `lib/src/compiler/scope.dart`
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/compiler/function_compile_test.dart`
- Test: `test/compiler/register_allocator_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"寄存器分配"节（作用域级回收策略）和 Ch2"栈帧布局"节（引用栈前三槽约定：ITA/FTA/this）
2. **写 RegisterAllocator 测试** — 验证：递增分配 + 空闲池回收；释放后的寄存器可被再次分配；`maxUsed` 跟踪最高水位线（= valueRegCount/refRegCount）
3. **写函数编译测试** — 验证：
   - 无参函数 `int f() => 42;` → refRegCount=3（ITA+FTA+this 预留）、valueRegCount 至少 1（返回值寄存器）
   - 有参函数 `int add(int a, int b) => a + b;` → 参数在值栈/引用栈的正确槽位，根据类型分配到 valueStack（int）或 refStack（String/Object 等）
   - 参数 StackKind 决策正确：int/double/bool → valueStack，其他 → refStack
4. **实现** — RegisterAllocator（Ch5 附录参考实现）、Scope 类（管理变量绑定：名称→寄存器+StackKind+isMutable）、函数编译主流程（`visitProcedure` → 分析参数/局部变量 → 分配寄存器 → 编译函数体 → 输出 DarticFuncProto）
5. **运行** — `fvm dart analyze && fvm dart test test/compiler/`

---

### Task 1.4.6: 端到端测试 — Dart 源码 → Kernel → 字节码 → 执行

**产出文件：**
- Create: `test/e2e/compile_and_run_test.dart`
- Create: `test/fixtures/` 目录（存放测试用 Dart 源文件）

**TDD 步骤：**

1. **设计测试场景** — 编写简单 Dart 源码文件，走完整管线
2. **写测试** — 完整管线验证：
   - 测试 1：`int add(int a, int b) => a + b; int main() => add(1, 2);` → 执行结果为 3
   - 测试 2：`int square(int x) => x * x; int main() => square(5);` → 执行结果为 25
   - 测试 3：`int complex(int a, int b, int c) => a * b + c; int main() => complex(2, 3, 4);` → 执行结果为 10
   - 每个测试步骤：源码文件 → `fvm dart compile kernel` → BinaryBuilder 加载 .dill → DarticCompiler 编译 → DarticInterpreter 执行 → 断言结果
3. **还需处理** — 测试辅助函数封装（编译 .dill 的 setUp、加载和编译的 helper），错误消息清晰（编译失败时显示 Kernel AST 信息）
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/compile_and_run_test.dart`

> 注意：此测试是 Phase 1 的里程碑验证之一。如果此测试通过，说明"Dart 源码 → Kernel → 字节码 → 执行"管线完整工作。

---

## Commit

```
feat(compiler): add minimal Kernel-to-bytecode compiler
```

**提交文件：** `lib/src/compiler/` 全部新文件 + `test/compiler/` 和 `test/e2e/` 全部新测试文件 + `test/fixtures/`

## 核心发现

- **Kernel AST 中算术运算节点类型**：`a + b` 表示为 `InstanceInvocation(receiver=a, name='+', arguments=[b])`，且 `int` 继承 `num`，所以 `interfaceTarget.enclosingClass` 是 `num` 而非 `int`。需要同时检查 `numClass` 和 `intClass`，并通过 `_inferExprType` 推断 receiver 实际类型来决定是否特化为 int 指令。
- **调用约定与寄存器分配冲突**：VM 的 `CALL_STATIC` 设置 `callee.vBase = caller.vBase + caller.valueRegCount`，即 outgoing args 必须放在 `valueRegCount` 之后。但 `valueRegCount` 在函数编译完成前未知。checkpoint/restore 方案对嵌套调用（如 `add(square(2), square(3))`）失败。**解决方案：post-patching** — 编译 arg 表达式到 frame 内的临时寄存器，emit 占位 MOVE 指令，函数编译完成后用已知的 `valueRegCount` 回填目标寄存器。
- **CFE 输出结构**：`int f() => 42;` 在 Kernel 中表示为 `ReturnStatement(IntLiteral(42))`，而非裸 expression。`void` 函数的 body 是 `Block` 包含 `ExpressionStatement` + `ReturnStatement(null)`。

## Batch 完成检查

- [x] 1.4.1 Kernel AST 遍历骨架
- [x] 1.4.2 编译字面量表达式
- [x] 1.4.3 编译算术表达式
- [x] 1.4.4 编译语句
- [x] 1.4.5 编译函数（寄存器分配）
- [x] 1.4.6 端到端测试
- [x] `fvm dart analyze` 零警告（仅剩 pubspec path dependency 预存警告）
- [x] `fvm dart test` 全部通过（350 tests）
- [ ] commit 已提交
- [ ] overview.md 已更新
