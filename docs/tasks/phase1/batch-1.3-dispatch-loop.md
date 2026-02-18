# Batch 1.3: 分发循环 (Ch3)

## 概览

实现 Ch3 定义的执行引擎核心：分发循环骨架、加载/存储指令组、整数算术与比较指令组、控制流指令组、以及 CALL/RETURN 帧管理。最终通过手工构造字节码的端到端测试验证。

**设计参考：** `docs/design/03-execution-engine.md`

**依赖：** Batch 1.1（opcodes、encoding、constant pool、module）, Batch 1.2（三栈、DarticFuncProto、DarticFrame、CallStack）

---

### Task 1.3.1: 核心分发循环骨架

**产出文件：**
- Create: `lib/src/runtime/interpreter.dart`
- Test: `test/runtime/interpreter_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch3"分发循环"节，理解外/内双层循环结构、fuel 计数、`_runQueue`、帧切换机制。Phase 1 只需同步单帧执行（无 async、无 `_runQueue` 调度），简化为单层 while 循环 + fuel 计数
2. **写测试** — 验证：能加载一个 DarticFuncProto 并启动执行；NOP 指令正确跳过（PC 递增）；HALT 指令停止执行；fuel 耗尽时暂停（Phase 1 直接完成，不做 Timer.run 调度）；非法操作码抛出错误
3. **实现骨架** — DarticInterpreter 类，持有三栈引用。`execute(DarticFuncProto)` 方法创建初始帧 → 进入 while 循环 → `switch(op)` 分发 → NOP/HALT 处理。所有未实现的 opcode 映射到 `throw DarticError('Unimplemented opcode: $op')`
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/interpreter_test.dart`

---

### Task 1.3.2: 加载/存储指令组 (0x00-0x0F)

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`
- Test: `test/runtime/load_store_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch1"加载/存储"节，逐条理解 0x00-0x0F 的 16 条指令语义
2. **写测试** — 为每条指令写至少一个测试用例：
   - `LOAD_CONST`：从 refs 常量池加载到 refStack
   - `LOAD_NULL`/`LOAD_TRUE`/`LOAD_FALSE`：refStack/valueStack 正确写入
   - `LOAD_INT`：sBx 有符号立即数加载到 valueStack（测试正数、负数、边界值）
   - `LOAD_CONST_INT`/`LOAD_CONST_DBL`：从 ints/doubles 常量池加载
   - `MOVE_REF`/`MOVE_VAL`：寄存器间复制
   - `BOX_INT`/`BOX_DOUBLE`：值栈→引用栈装箱
   - `UNBOX_INT`/`UNBOX_DOUBLE`：引用栈→值栈拆箱
   - 每个测试手工构造包含目标指令 + HALT 的 bytecode，执行后检查栈状态
3. **实现** — 在 interpreter.dart 的 switch 中添加 0x00-0x0F 的 case 分支，解码操作数后执行对应的栈操作
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/load_store_test.dart`

---

### Task 1.3.3: 整数算术 + 比较指令组 (0x10-0x1F, 0x30-0x3F)

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`
- Test: `test/runtime/arithmetic_test.dart`
- Test: `test/runtime/comparison_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch1"整数算术"节和"比较"节
2. **写算术测试** — 验证每条整数算术指令：
   - `ADD_INT`/`SUB_INT`/`MUL_INT`/`DIV_INT`/`MOD_INT`：基本运算 + 溢出/负数/零除
   - `NEG_INT`：取反
   - `BIT_AND`/`BIT_OR`/`BIT_XOR`/`BIT_NOT`/`SHL`/`SHR`/`USHR`：位运算
   - `ADD_INT_IMM`：C 为 8 位无符号立即数 [0, 255]
3. **写比较测试** — 验证比较指令：
   - `LT_INT`/`LE_INT`/`GT_INT`/`GE_INT`/`EQ_INT`：结果为 1（true）或 0（false）写入 valueStack
   - `EQ_REF`：引用相等性（identical）
   - 边界值：相等、大于、小于
4. **实现** — 在 switch 中添加 0x10-0x1F（跳过浮点 0x20-0x2F，Phase 2）和 0x30-0x3B 的 case 分支。解码 ABC 格式操作数，执行运算写入 valueStack[A]
5. **运行** — `fvm dart analyze && fvm dart test test/runtime/arithmetic_test.dart test/runtime/comparison_test.dart`

---

### Task 1.3.4: 控制流指令组 (0x40-0x4F)

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`
- Test: `test/runtime/control_flow_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch1"控制流"节，理解 AsBx 格式的 excess-K 有符号偏移跳转
2. **写测试** — 验证每条控制流指令：
   - `JUMP sBx`：无条件跳转（正向、负向偏移，注意 PC += sBx 是相对当前 PC 的偏移）
   - `JUMP_IF_TRUE A, sBx`：valueStack[A] != 0 时跳转
   - `JUMP_IF_FALSE A, sBx`：valueStack[A] == 0 时跳转
   - `JUMP_IF_NULL A, sBx`：refStack[A] == null 时跳转
   - `JUMP_IF_NNULL A, sBx`：refStack[A] != null 时跳转
   - `JUMP_AX sAx`：大范围跳转（24 位有符号偏移）
   - 构造简单循环（累加 1 到 10）验证向后跳转正确性
3. **实现** — 在 switch 中添加 0x40-0x45 的 case 分支。注意跳转偏移的 excess-K 解码。JUMP 使用 AsBx 格式（A 字段未使用），JUMP_AX 使用 sAx 格式
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/control_flow_test.dart`

---

### Task 1.3.5: CALL/RETURN 指令（含帧推入/弹出）

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`
- Test: `test/runtime/call_return_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch3"调用约定"节，理解压帧 7 步流程和返回值传递。Phase 1 只需 `CALL_STATIC` + `RETURN_REF`/`RETURN_VAL`/`RETURN_NULL`（不需要 CALL_VIRTUAL/CALL_SUPER/CALL_HOST/CALL，Phase 3 再实现）
2. **写测试** — 验证：
   - `CALL_STATIC A, Bx`：正确压帧（CallStack 6 字段写入）、sp 推进 valueRegCount/refRegCount、PC 切换到被调用者
   - `RETURN_REF A`：返回值写入调用者 refStack[resultReg]、弹帧恢复调用者状态
   - `RETURN_VAL A`：返回值写入调用者 valueStack[resultReg]
   - `RETURN_NULL`：调用者 refStack[resultReg] = null
   - 嵌套调用（A 调用 B 调用 C，各自返回正确值）
   - 栈溢出检查（valueRegCount 超过剩余容量时抛 DarticError）
   - 调用深度检查（超过 maxCallDepth=512 时抛 DarticError）
3. **实现** — CALL_STATIC 的 7 步压帧流程 + 三条 RETURN 指令的弹帧恢复逻辑。需要全局 DarticFuncProto 表（DarticModule.functions）供 CALL_STATIC 索引
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/call_return_test.dart`

---

### Task 1.3.6: 端到端测试 — 手工构造字节码执行加法函数

**产出文件：**
- Test: `test/e2e/basic_bytecode_test.dart`

**TDD 步骤：**

1. **设计测试场景** — 手工构造字节码实现 `add(a, b) => a + b`，然后用 `main() => add(1, 2)` 调用并验证返回值为 3
2. **写测试** — 手工构造两个 DarticFuncProto：
   - `add`：从 valueStack 读取参数 → `ADD_INT` → `RETURN_VAL`
   - `main`：`LOAD_INT 1` → `LOAD_INT 2` → 参数预布局 → `CALL_STATIC add` → 验证返回值 = 3 → `HALT`
   - 组装为 DarticModule → 用 DarticInterpreter 执行 → 断言结果为 3
3. **还需测试** — 多参数调用、嵌套调用（main→add→再调用一个函数）、返回值类型（int/ref/null）
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/basic_bytecode_test.dart`

> 注意：此测试验证 Batch 1.1-1.3 的全部产出协同工作。如果此测试通过，说明字节码基础设施 + 三栈 + 分发循环的集成是正确的。

---

## Commit

```
feat(runtime): add dispatch loop with arithmetic, control flow, and call/return
```

**提交文件：** `lib/src/runtime/interpreter.dart` + `test/runtime/` 和 `test/e2e/` 全部新测试文件

## 核心发现

- **HALT 不应清除 ref 栈**：设计文档中"引用栈弹出置 null"的 GC 安全机制适用于 RETURN（清除被调用者帧的引用槽位），而非 HALT。HALT 结束整个执行，清除会导致测试无法读取结果。
- **参数预布局约定**：编译器分配调用者的 `valueRegCount` 包含传出参数空间。调用者用超出本地寄存器的索引（如 `valueRegCount` + 偏移）写入参数位置，这些位置在 CALL_STATIC 推进 `vBase` 后恰好成为被调用者的 v0、v1 等。
- **RETURN 读取顺序**：必须在 `popFrame()` 之前读取当前帧的 savedVSP、savedRSP、returnPC、resultReg，因为 pop 后访问器指向调用者帧。pop 之后再用 `callStack.funcId` 获取调用者的 funcId 以查找字节码。
- **跳转偏移基准**：PC 在取指时已后增（`code[pc++]`），跳转偏移相对于已增后的 PC 值。`JUMP +2` 从索引 0 实际跳到索引 3（0→取指→PC=1→+2→3）。

## Batch 完成检查

- [x] 1.3.1 核心分发循环骨架
- [x] 1.3.2 加载/存储指令组
- [x] 1.3.3 整数算术 + 比较指令组
- [x] 1.3.4 控制流指令组
- [x] 1.3.5 CALL/RETURN 指令
- [x] 1.3.6 端到端测试
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test` 全部通过（273 tests）
- [x] commit 已提交
- [x] overview.md 已更新
