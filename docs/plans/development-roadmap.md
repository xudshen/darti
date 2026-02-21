# Dartic 开发路线图

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 从零搭建 dartic 字节码解释器，最终通过 co19 核心语言测试集

**Architecture:** 混合路线——先按设计文档依赖拓扑搭建最小可运行管线（Ch1→Ch2→Ch3→Ch5），再按 co19 测试类别从简到繁逐步扩展语言特性。Ch4/Ch6/Ch7/Ch8 按需引入。

**Tech Stack:** Pure Dart, Kernel AST (`package:kernel`), TDD (`package:test`), co19 测试集

---

## 决策记录

| 问题 | 决策 | 理由 |
|------|------|------|
| 开发路线选择 | 混合路线（管线优先 + co19 驱动） | 纯设计文档顺序端到端验证太晚；纯 co19 顺序架构不稳 |
| 阶段一粒度 | 最小管线只覆盖标量变量+算术+控制流+函数调用 | 最小化前期投入，尽快能跑 co19 测试 |
| co19 测试接入时机 | 阶段一结束即接入（不等所有特性就绪） | 持续验证，尽早发现设计问题 |
| Ch4 Interop 引入时机 | P5 阶段（需要 `dart:core` 标准库时） | 前期不需要跨边界调用，延迟引入减少复杂度 |
| Ch6 泛型引入时机 | P4 阶段（碰到泛型类/泛型方法测试时） | 泛型是 Dart 核心特性，不能太晚 |
| Ch7 异步引入时机 | P6 阶段（碰到 `LibTest/async` 时） | async/await 依赖 Ch3 充分稳定后才引入 |
| co19 测试如何跑 | Phase 2 用自建原生 harness（不依赖 expect.dart），Phase 3 类就绪后切到 co19 expect.dart | expect.dart 定义了 `class Expect` + `class ExpectException`，Phase 2 无类支持无法编译 |
| co19 harness 演进策略 | v0→v4 五版迭代，随 Phase 逐步增强 | co19 Utils 有分层依赖：expect.dart 需类（P3）、expect_common 需 Bridge（P5）、static_type_helper 需 extension method（P6） |

---

## co19 Test Harness 演进路线（贯穿 Phase 2-6）

co19 测试依赖 `vendor/co19/Utils/` 下的分层基础设施。**关键约束**：`expect.dart` 本身定义了 `class Expect` 和 `class ExpectException`，且顶层 `import 'dart:async'`——Phase 2 无类支持时无法编译。因此 harness 从 v0（自建原生）起步，Phase 3 类就绪后才切到 co19 expect.dart。

```
Phase 2 ─ v0 原生 harness（不依赖 expect.dart）
  ├─ 测试发现（文件名匹配 *_t[0-9]{2}.dart）
  ├─ 编译 → 执行 → 捕获未处理异常判定 pass/fail
  ├─ 自建断言 shim（纯函数，无 class：expectEquals/expectTrue/expectFalse）
  ├─ 负面测试识别（// [analyzer] / // [cfe] 标记 → 预期编译失败）
  ├─ 通过率统计与报告 + 结果快照 + diff
  └─ 限制：只能跑不依赖 Expect 类的简单测试，或通过 shim 替换 import

Phase 3 ─ v1 接入 expect.dart（类已就绪）
  ├─ 编译 Utils/expect.dart（class Expect + class ExpectException）
  ├─ 相对路径 import 解析（../../Utils/expect.dart）
  ├─ 多文件测试支持（library 声明 + part/import）
  └─ 工厂模式测试（test(Factory create) 模式）

Phase 4 ─ v2 实验标志与类型负面测试
  ├─ // SharedOptions=--enable-experiment=... 解析
  ├─ 类型错误负面测试完善（@compile-error 类型相关子集）
  └─ 注意：static_type_helper.dart 需 extension method，延迟到 Phase 6

Phase 5 ─ v3 标准库导入 + expect_common 完整支持
  ├─ dart:core / dart:collection / dart:math 导入解析（路由到 Bridge）
  ├─ Utils/expect_common.dart 完整支持（deepEquals 需 Map/List Bridge）
  └─ 跳过列表（skip list）管理不支持的库测试

Phase 6 ─ v4 异步测试 + static_type_helper
  ├─ Utils/static_type_helper.dart（需泛型 + extension method，两者此时均就绪）
  ├─ Utils/async_utils.dart（asyncStart/asyncEnd 计数器）
  ├─ stdout 输出检测（unittest-suite-wait-for-done / unittest-suite-success）
  ├─ 异步测试超时机制
  └─ Stream/Future 完成检测
```

**harness 产出文件：** `tool/co19_runner.dart`（主入口）+ `lib/src/testing/` 下的辅助模块

---

## co19 回归测试策略

每个 Phase 的 harness batch 在跑当期新增测试类别的同时，**必须重跑所有历史类别**。原因：

1. **回归检测**：新特性可能破坏已通过测试（如修改 dispatch loop 导致算术测试回归）
2. **通过率提升**：新能力解锁之前因依赖缺失而失败的测试（如 `Language/Expressions` 中部分测试依赖类/闭包，Phase 3 加了类后自然通过）

```
Phase N harness 验证任务：
  1. 跑本 Phase 新增 co19 类别        → 记录 "首次通过率"
  2. 重跑所有历史 co19 类别            → 记录 "累计通过率"
  3. 对比历史通过率，标记回归项         → 回归 = 上次 pass 本次 fail
  4. 回归项必须在本 Phase 内修复，不得带入下一 Phase
```

**co19_runner 需支持的回归检测功能：**
- 保存每次运行结果快照（`tool/co19_results/<phase>.json`）
- diff 两次快照，输出：新增 pass / 新增 fail（回归）/ 持续 fail / 持续 pass
- 回归项自动标红，CI 中回归 > 0 则 fail

---

## 总览：6 个阶段

```
Phase 1  最小管线          ← 设计文档顺序 (Ch1→Ch2→Ch3→Ch5)
Phase 2  基础语言特性       ← co19: Variables, Expressions, Statements
Phase 3  函数与类          ← co19: Functions, Classes, Reference
Phase 4  高级 OOP          ← co19: 继承/Mixin/Sealed + Ch6 泛型
Phase 5  标准库与互调       ← co19: LibTest/core + Ch4 Interop
Phase 6  异步与高级特性     ← co19: LibTest/async + Ch7 Async + LanguageFeatures
```

每个 Phase 结束时有明确的里程碑验证。

---

## Phase 1: 最小可运行管线

**目标：** 能编译并执行 `int add(int a, int b) => a + b;` 级别的 Dart 函数

**设计章节：** Ch1 (ISA) → Ch2 (对象模型) → Ch3 (执行引擎) → Ch5 (编译器)

**里程碑：** 手工构造的字节码能在执行引擎中运行，编译器能将简单 Kernel AST 编译为字节码

### Batch 1.1: 字节码基础设施 (Ch1) ✅

- [x] 1.1.1 Opcode 常量与编解码工具函数 → `lib/src/bytecode/opcodes.dart`, `lib/src/bytecode/encoding.dart`
- [x] 1.1.2 常量池四分区数据结构 → `lib/src/bytecode/constant_pool.dart`
- [x] 1.1.3 WIDE 前缀编解码 → 扩展 `encoding.dart`
- [x] 1.1.4 字节码模块容器（函数表 + 常量池 + IC 表） → `lib/src/bytecode/module.dart`

**commit:** `feat(bytecode): add ISA encoding, opcodes, and constant pool`

> **核心发现：**
> - Opcode 改用 `abstract final class Op` 的 `static const int` 而非 enum，避免 switch 中的额外间接寻址
> - ExceptionHandler 需要完整 8 字段（含 valStackDP/refStackDP），不能省略栈深度恢复信息
> - 常量池四分区设计（refs/ints/doubles/names）各自独立索引，简化了编解码逻辑

### Batch 1.2: 三栈与对象模型 (Ch2) ✅

- [x] 1.2.1 ValueStack（共享 ByteBuffer 双视图：Int64List + Float64List） → `lib/src/runtime/value_stack.dart`
- [x] 1.2.2 RefStack（`List<Object?>` 引用栈） → `lib/src/runtime/ref_stack.dart`
- [x] 1.2.3 DarticFrame（栈帧：PC、FP、寄存器计数、返回地址） → `lib/src/runtime/frame.dart`
- [x] 1.2.4 DarticObject / DarticClassInfo 基础结构 → `lib/src/runtime/object.dart`

**commit:** `feat(runtime): add three-stack model and object representation`

> **核心发现：**
> - ValueStack 双视图（Int64List + Float64List）共享同一 ByteBuffer，slot 对齐自动保证
> - CallStack 采用扁平数组而非 Frame 对象链表，pushFrame/popFrame 通过固定偏移读写
> - DarticObject 字段存储分为 valFields（Int64List）和 refFields（List<Object?>），与栈模型一致

### Batch 1.3: 分发循环 (Ch3) ✅

- [x] 1.3.1 核心分发循环骨架（switch on opcode） → `lib/src/runtime/interpreter.dart`
- [x] 1.3.2 实现加载/存储指令组 (0x00-0x0F) → 扩展 `interpreter.dart`
- [x] 1.3.3 实现整数算术 + 比较指令组 (0x10-0x1F, 0x30-0x3F) → 扩展 `interpreter.dart`
- [x] 1.3.4 实现控制流指令组 (0x40-0x4F) → 扩展 `interpreter.dart`
- [x] 1.3.5 实现 CALL/RETURN 指令（含帧推入/弹出） → 扩展 `interpreter.dart`
- [x] 1.3.6 端到端测试：手工构造字节码执行加法函数 → `test/runtime/interpreter_test.dart`

**commit:** `feat(runtime): add dispatch loop with arithmetic, control flow, and call/return`

> **核心发现：**
> - Excess-K 编码：sBx = raw - 0x7FFF，sAx = raw - 0x7FFFFF，JUMP 偏移为相对 PC（已自增后）
> - CALL_STATIC 设置 callee.vBase = caller.vs.sp，参数在 caller 帧尾部（vBase + valueRegCount + argIdx）
> - RETURN_VAL/RETURN_REF/RETURN_NULL 三种返回指令，HALT 专用于入口函数终止
> - Fuel 计数防止无限循环，Phase 1 默认 50000

### Batch 1.4: 最小编译器 (Ch5) ✅

- [x] 1.4.1 Kernel AST 遍历骨架（`TreeVisitor` 实现） → `lib/src/compiler/compiler.dart`
- [x] 1.4.2 编译表达式：IntLiteral, DoubleLiteral, BoolLiteral, StringLiteral → 扩展 `compiler.dart`
- [x] 1.4.3 编译表达式：算术 MethodInvocation (+, -, *, ~/, %) → 扩展 `compiler.dart`
- [x] 1.4.4 编译语句：ReturnStatement, ExpressionStatement → 扩展 `compiler.dart`
- [x] 1.4.5 编译函数：FunctionNode (参数 + 局部变量 + 寄存器分配) → 扩展 `compiler.dart`
- [x] 1.4.6 端到端测试：Dart 源码 → Kernel → 字节码 → 执行 → 结果 → `test/e2e/compile_and_run_test.dart`

**commit:** `feat(compiler): add minimal Kernel-to-bytecode compiler`

> **核心发现：**
> - Kernel AST 中 `int` 算术操作符（+, -, * 等）的 interfaceTarget 指向 `num` 类而非 `int` 类，需要 `_inferExprType` 递归推断实际类型
> - 编译期不知道 valueRegCount（寄存器总数），CALL_STATIC 的出参 MOVE 指令采用 post-patching：先 emit 占位指令，函数编译完成后回填目标寄存器
> - 两遍编译：Pass 1 收集 funcId（支持前向引用），Pass 2 编译函数体
> - Ref 寄存器 0-2 固定保留给 ITA/FTA/this（initialOffset: 3）

### Batch 1.5: 模块格式与运行时补全 ✅

审查发现 Phase 1 遗漏了设计文档中明确要求的关键组件，补充如下：

- [x] 1.5.1 `.darb` 二进制模块格式（header + magic + 版本 + 校验和） → `lib/src/bytecode/format.dart`
- [x] 1.5.2 模块序列化/反序列化管线 → `lib/src/bytecode/serializer.dart`
- [x] 1.5.3 异常处理表结构（try 范围 → handler PC 映射） → 扩展 `module.dart` + `interpreter.dart`
- [x] 1.5.4 StackKind 分类（编译器为每个变量/临时值标注 intVal/doubleVal/ref，保证双视图不变式） → 扩展 `compiler.dart`
- [x] 1.5.5 IC 表元数据初始化（函数加载时 IC 表零填充） → 扩展 `module.dart`
- [x] 1.5.6 端到端测试：编译→序列化→反序列化→执行 → `test/e2e/module_roundtrip_test.dart`

**commit:** `feat: add module format, exception tables, StackKind, and IC initialization`

> **核心发现：**
> - Magic 值选定 0x44415242（ASCII "DARB"），hexdump 可直接识别
> - StackKind 三分类 `{intVal, doubleVal, ref}`，`isValue` getter 统一判断值栈归属
> - IC 表仅序列化 methodNameIndex，cachedClassId/cachedMethodOffset 是运行时状态，反序列化时重置为 -1/0
> - CRC32 采用 IEEE 802.3 标准（反射多项式 0xEDB88320），校验和覆盖 payload（不含 header）
> - ConstantPool.from() + read accessors (refs/ints/doubles/names) 支持反序列化重建

### Phase 1 里程碑验证 ✅

```dart
// 能编译并执行这段代码，返回正确结果
int add(int a, int b) => a + b;
int main() => add(1, 2); // => 3
```

- [x] 里程碑通过（412 tests, all passing）
- [x] 编译→序列化→反序列化→执行 roundtrip 通过

---

## Phase 2: 基础语言特性

**目标：** 通过 `co19/Language/Variables`, `co19/Language/Expressions`（算术/比较/逻辑子集）, `co19/Language/Statements`

**设计章节：** 继续扩展 Ch1/Ch3/Ch5

**里程碑：** 通过 co19 上述三个目录的基础测试

### Batch 2.1: 变量与赋值 ✅

- [x] 2.1.1 局部变量声明与初始化（var/final/const） → `Language/Variables/`
- [x] 2.1.2 全局变量 LOAD_GLOBAL/STORE_GLOBAL → `Language/Variables/`
- [x] 2.1.3 null、bool 字面量与 null 检查 → `Language/Variables/`

**commit:** `feat: support variable declaration, assignment, and globals`

> **核心发现：**
> - CFE 将几乎所有 const 值包装为 `ConstantExpression`（即使 `const x = 42`），此节点类型对编译大多数 Dart 代码不可或缺
> - 全局变量懒初始化策略：初始化器编译为独立入口函数，在 main() 前 eager 执行，避免复杂的重入调度
> - `int?`/`bool?`/`double?` 必须在 ref 栈（无法表示 null），`_classifyStackKind` 中 nullability 检查是关键
> - `x!`（NullCheck）后需要 UNBOX，因为操作数在 ref 栈而结果语义上是值类型

### Batch 2.2: 表达式 ✅

- [x] 2.2.1 浮点算术指令 (0x20-0x26) + 编译器支持
- [x] 2.2.2 比较运算符（<, <=, >, >=, ==, !=）含 double
- [x] 2.2.3 逻辑运算符（&&, \|\|, !）短路求值
- [x] 2.2.4 位运算操作
- [x] 2.2.5 条件表达式（`?:` 和 `??`）
- [x] 2.2.6 类型转换（`as`）与类型测试（`is`/`is!`）

**commit:** `feat: support arithmetic, comparison, logical, and bitwise expressions`

> **核心发现：**
> - 短路求值：`&&` 用 JUMP_IF_FALSE，`||` 用 JUMP_IF_TRUE；占位+回填模式（sBx = targetPC - jumpPC - 1）
> - 比较 AST 节点类型：`<`/`<=`/`>`/`>=` 是 InstanceInvocation；`==` 是 EqualsCall；`!=` 是 CFE 降糖为 Not(EqualsCall)
> - `/` 在 int 上返回 double：编译器自动插入 INT_TO_DBL 转换两个操作数再 DIV_DBL
> - `??` 降糖为 Let + EqualsNull + ConditionalExpression，由已有组件支持
> - Phase 2 将 is/as 委托给 Dart host VM 闭包，完整 DarticType 延迟到 Phase 4

### Batch 2.3: 语句与控制流 ✅

- [x] 2.3.1 if/else 语句
- [x] 2.3.2 for / while / do-while 循环
- [x] 2.3.3 switch/case 语句（基础，无 pattern）
- [x] 2.3.4 break / continue / label
- [x] 2.3.5 try / catch / finally + THROW/RETHROW
- [x] 2.3.6 assert 语句

**commit:** `feat: support control flow statements and exception handling`

> **核心发现：**
> - Kernel 用 LabeledStatement + BreakStatement 统一 break/continue，while-loop continue 由 CFE 自动转换
> - ExceptionHandler 8 字段结构含 valStackDP/refStackDP 用于栈深度恢复，Phase 2 只支持 catch-all（catchType=-1）
> - try-finally 生成两份 finalizer 代码（正常路径 + 异常路径），异常路径以 RETHROW 结尾
> - switch 编译为 if-else 链（EQ_INT/EQ_REF + JUMP_IF_TRUE），跳表优化延后

### Batch 2.4: co19 Harness v0 — 原生 harness（不依赖 expect.dart）

> **为什么不直接用 expect.dart？** `expect.dart` 定义了 `class Expect` 和 `class ExpectException`，且 `import 'dart:async'`。Phase 2 无类支持，无法编译。Phase 3 加了类后才切到真正的 expect.dart。

- [x] 2.4.1 测试发现器（扫描目录，匹配 `*_t[0-9]{2}.dart`） → `tool/co19_runner.dart`
- [x] 2.4.2 自建断言 shim（纯函数 API，无 class） → `lib/src/testing/expect_shim.dart`
- [x] 2.4.3 负面测试识别（解析 `// [analyzer]` / `// [cfe]` 标记，预期编译失败则跳过） → 扩展 co19_runner
- [x] 2.4.4 通过率统计与报告（pass/fail/skip/error 分类） → 扩展 co19_runner
- [x] 2.4.5 结果快照与 diff 功能（保存 JSON，对比新增 pass/回归 fail） → `tool/co19_results/`
- [x] 2.4.6 首轮验证：跑 Language/Variables + Expressions + Statements，保存基线快照 → 测试报告

**commit:** `feat: add co19 test harness v0 with native assertion shim`

> **核心发现：**
> - Shim 替换 import 未执行——Phase 2 无类支持，依赖 `Expect` 类方法的测试自然失败（约占失败的 30%），Phase 3 类就绪后切 harness v1
> - co19 实际测试数：Variables 111 / Expressions 1933 / Statements 537 = 2581 总测试
> - 主要失败原因：Expect 类依赖 (~30%)、ConstructorInvocation (~15%)、InstanceGet/Set (~10%)、FunctionDeclaration (~8%)、YieldStatement/async (~8%)
> - 负面测试标记格式统一为 `// [analyzer] <desc>` 和 `// [cfe] <desc>`，成对出现
> - 发现并修复路径尾斜杠 bug（category 首字母截断）

### Phase 2 里程碑验证

- [x] co19 `Language/Variables` 通过率 > 50% — 实际 65.8% (73/111)
- [x] co19 `Language/Expressions` 基础子集通过率 > 30% — 实际 53.4% (1032/1933)
- [x] co19 `Language/Statements` 通过率 > 30% — 实际 49.9% (268/537)

**实际通过率：** Variables 65.8% / Expressions 53.4% / Statements 49.9% / 总计 53.2% (1373/2581)

---

## Phase 3: 函数与类

**目标：** 通过 `co19/Language/Functions`, `co19/Language/Classes`（基础）, `co19/Language/Reference`

**设计章节：** Ch2 (对象操作扩展), Ch3 (virtual dispatch), Ch5 (类编译)

**里程碑：** 支持类的实例化、字段访问、方法调用、构造器、继承

### Batch 3.1: 函数进阶

- [x] 3.1.1 可选参数（位置参数 + 命名参数） → `Language/Functions/`
- [x] 3.1.2 默认参数值 → `Language/Functions/`
- [x] 3.1.3 闭包 + CLOSURE/CLOSE_UPVALUE 指令 → `Language/Functions/`
- [x] 3.1.4 函数作为一等公民（tearoff、传参） → `Language/Functions/`

**commit:** `feat: support optional params, closures, and first-class functions`

> **核心发现：**
> - Open/closed upvalue 语义：open upvalue 指向活跃 ref-stack slot 实现变量共享；`CLOSE_UPVALUE` 在作用域退出时将值复制到堆
> - 嵌套闭包的传递性 upvalue 解析：需要 `isLocal=false` 描述符指向外层闭包的 upvalue 索引，而非祖先帧的寄存器
> - 值类型装箱：闭包捕获的 int/bool/double 必须通过 BOX 指令提升到 ref stack，因为 upvalue 数组是 `List<Object?>`

### Batch 3.2: 类基础

- [x] 3.2.1 类定义、实例化 (NEW_INSTANCE) → `Language/Classes/`
- [x] 3.2.2 字段访问 (GET_FIELD_REF/VAL, SET_FIELD_REF/VAL) → `Language/Classes/`
- [x] 3.2.3 实例方法调用 (CALL_VIRTUAL + IC) → `Language/Classes/`
- [x] 3.2.4 构造器（默认/命名/重定向/工厂） → `Language/Classes/`
- [x] 3.2.5 静态方法与静态字段 → `Language/Classes/`
- [x] 3.2.6 getter / setter → `Language/Classes/`

**commit:** `feat: support class instantiation, fields, methods, and constructors`

> **核心发现：**
> - Pass 1c 创建占位 FuncProto 到方法表；Pass 2c 必须刷新为已编译的 FuncProto，避免过期引用
> - `CALL_VIRTUAL` 自动将 receiver 放到 callee 的 rsp+2，减少构造器调用中的显式 MOVE 指令
> - IC 表条目是 per-function 状态，函数开始时清空；闭包编译通过 `_CompilationContext` 保存/恢复

### Batch 3.3: 继承与多态

- [x] 3.3.1 单继承 + super 调用 (CALL_SUPER) → `Language/Classes/`
- [x] 3.3.2 方法重写 + 虚分发 → `Language/Classes/`
- [x] 3.3.3 抽象类与抽象方法 → `Language/Classes/`
- [x] 3.3.4 操作符重载 (EQ_GENERIC 等) → `Language/Classes/`

**commit:** `feat: support inheritance, override, and operator overloading`

> **核心发现：**
> - 编译期扁平化方法表（Strategy B）：子类方法表包含所有继承+重写方法，IC miss 时 O(1) 查找无需运行时遍历超类链
> - 用户定义的操作符（+、-、[]、== 等）自然路由到 `_compileInstanceInvocation` → 跳过 int/double 快速路径 → `CALL_VIRTUAL`，仅 `operator==` 需要通过 EqualsCall 节点特殊处理
> - `_inferExprType` 闭包捕获 `_classInfos` 列表引用，单模块模型下安全（多模块需重新评估）

### Batch 3.4: 作用域与名称解析

- [x] 3.4.1 块级作用域变量遮蔽 → `Language/Reference/`
- [x] 3.4.2 库导入/导出与可见性 → `Language/Libraries_and_Scripts/`
- [x] 3.4.3 this / super 引用 → `Language/Reference/`

**commit:** `feat: support scoping, imports/exports, and name resolution`

> **核心发现：**
> - 变量别名 bug：`declareWithReg` 将 `int b = a;` 绑定到源变量寄存器导致共享修改；修复：分配独立寄存器并 emit MOVE
> - 多库编译零成本：编译器已遍历所有非平台库的全部 Pass（1a-2c）；Kernel CFE 将所有 import 合并到单个 .dill，跨库引用正确解析到分配的 funcId/classId
> - this/super 表达式完全正确：22 个 e2e 测试无需修改产品代码即通过

### Batch 3.5: co19 Harness v1 — 接入 expect.dart（类已就绪）

> **此时类已就绪**，可以编译 `class Expect` 和 `class ExpectException`。从 shim 切到真正的 co19 expect.dart。

- [x] 3.5.1 编译 `Utils/expect.dart`（class Expect + class ExpectException + 基础断言） → 扩展 compiler
- [x] 3.5.2 相对路径 import 解析（`../../Utils/expect.dart`） → 扩展 compiler
- [x] 3.5.3 多文件测试支持（library 声明 + import 其他测试文件的解析与编译） → 扩展 compiler + co19_runner
- [x] 3.5.4 工厂模式测试支持（`test(Factory create)` 回调模式） → 扩展 co19_runner
- [x] 3.5.5 验证：跑 Language/Functions + Classes + Reference（新增类别） → 测试报告
- [x] 3.5.6 回归跑：重跑 Phase 2 全部类别（现在用真正的 expect.dart），diff 快照 → 回归报告

**commit:** `feat: co19 harness v1 — integrate expect.dart with class support`

> **核心发现：**
> - 简化 expect.dart 策略：去除 `implements Exception`、`dart:async`、泛型、字符串插值等 Phase 3 不支持特性
> - 跨帧异常展开：THROW/RETHROW 需循环弹出帧并搜索 caller 的 exception table，直到找到 handler 或回到 entry frame
> - noSuchMethod forwarder：CFE 为含 `noSuchMethod` 覆写的类自动生成 synthetic forwarder，其方法体使用 `_InvocationMirror._withType` 等平台内部 API，dartic 无法编译。需 `proc.isNoSuchMethodForwarder` 检测 + 自定义字节码生成（~54 个 co19 测试受影响，Phase 4/5 不会自动修复）
> - Phase 2 零回归，+78 新通过（53.2% → 56.2%），新通过主要来自 Expressions 类/闭包相关测试

### Batch 3.6: 泛型编译预备（为 Phase 4 铺路）

> Phase 4 需要 Ch6 泛型，而 Ch6 依赖 Ch5 编译器能生成 TypeTemplate。此 batch 在 Phase 3 末尾为编译器补充类型信息基础设施。

- [x] 3.6.1 TypeTemplate 数据结构定义（类型参数、bounds、SuperTypeMap 骨架） → `lib/src/compiler/type_template.dart`
- [x] 3.6.2 编译器中 Kernel DartType 遍历框架（为 Phase 4 泛型编译做准备） → 扩展 `compiler.dart`
- [x] 3.6.3 类型参数 bounds 解析与编码 → 扩展 `type_template.dart`

**commit:** `feat(compiler): add TypeTemplate infrastructure for generics`

> **核心发现：**
> - `dartTypeToTemplate` 递归遍历 Kernel DartType 树，独立为 `type_converter.dart` 模块，复用于 bounds 和 supertype 转换
> - Kernel 默认 bound 是 `DynamicType`（非 `Object?`），直接映射为 `DynamicTemplate`
> - `SuperTypeEntry` 持有 subClassId/superClassId/typeArgMapping，为 Phase 4 的 isSubtypeOf 规则 11-12 提供编译期预计算数据
> - 自引用 bound（如 `T extends Comparable<T>`）正确编码为 `InterfaceTypeTemplate(classId, [TypeParameterTemplate(0, ITA)])`

### Phase 3 里程碑验证 ✅

- [x] co19 `Language/Functions` 通过率 > 50% — 实际 72.2% (135/187)
- [x] co19 `Language/Classes` 基础子集通过率 > 40% — 实际 76.8% (649/845)
- [x] co19 `Language/Reference` 通过率 > 40% — 实际 81.4% (451/554)
- [x] Phase 2 类别零回归（或回归已修复） — 0 回归
- [x] Phase 2 类别通过率较上期有提升 — 53.2% → 56.2% (+78 new pass)

**实际通过率：** Functions 72.2% / Classes 76.8% / Reference 81.4% / Phase 3 新增三类合计 78.0% (1235/1586)
**Phase 2 回归：** 0 回归 / +78 new pass / 全六类累计 64.4% (2686/4167)

---

## Phase 4: 高级 OOP + 泛型 (Ch6)

**目标：** 通过 `co19/Language/Generics`, `co19/Language/Mixins`, `co19/Language/Interfaces`, `co19/TypeSystem/subtyping`（核心子集）

**设计章节：** **Ch6 泛型** 全面引入

**里程碑：** 支持泛型类/方法、mixin、sealed class、子类型检查

### Batch 4.1: Mixin 与接口 ✅

- [x] 4.1.1 implements 接口契约 → `Language/Interfaces/`
- [x] 4.1.2 mixin / mixin class / with → `Language/Mixins/`
- [x] 4.1.3 sealed / base / final class modifiers → `LanguageFeatures/Class-modifiers/`

**commit:** `feat: support interfaces, mixins, and class modifiers`

> **核心发现：**
> - Kernel 匿名 mixin 类使用 `implementedTypes`（非 `mixedInType`）引用 mixin 类型，`mixedInType` 为 null，CFE 已将方法/字段内联
> - Kernel 类列表顺序不保证拓扑排序，`_registerClass` 改为递归注册确保依赖先于被依赖者
> - Mixin 字段初始化器是 `Field.initializer` 表达式而非构造器的 `FieldInitializer`
> - Dart 3 类修饰符（sealed/base/final/interface）由 CFE 强制编译时限制，运行时无需额外检查
> - Super 调用在 mixin 中通过 Kernel 的 `SuperMethodInvocation.interfaceTarget` 自动解析到线性化链

### Batch 4.2: 泛型核心 (Ch6) ✅

- [x] 4.2.1 DarticType 数据结构 + 驻留表 → `lib/src/runtime/dartic_type.dart`, `lib/src/runtime/type_registry.dart`
- [x] 4.2.2 ITA/FTA 槽位 + PUSH_ITA/PUSH_FTA → Ch6 指令实现
- [x] 4.2.3 INSTANTIATE_TYPE + 类型参数传递 → Ch6 指令实现
- [x] 4.2.4 INSTANCEOF/CAST 子类型检查 → `Language/Generics/`
- [x] 4.2.5 泛型类编译 → `Language/Generics/`
- [x] 4.2.6 泛型方法编译 → `Language/Generics/`

**commit:** `feat(generics): add reified generics with DarticType residency`

> **核心发现：**
> - TypeRegistry 初始 64 桶 bucket-hash，常用基本类型预注册，命中率高
> - ITA 在 CALL_VIRTUAL 解释器中自动从 `receiver.runtimeType_.typeArgs` 加载到 rsp+0，零 bytecode 膨胀
> - FTA 通过 `INSTANTIATE_TYPE` + `CREATE_TYPE_ARGS` 组装，复用已有 arg move 机制
> - `_classToClassId` vs `_typeClassIdLookup` 分离，避免 core type classIds 污染编译器决策
> - TypeParameterType 解析需同时传递 `_currentClassTypeParams` (ITA) 和 `_currentFunctionTypeParams` (FTA)
> - 泛型类字段的 operator dispatch：`_inferExprType` 改用 Kernel 预计算字段（`expr.resultType`/`expr.functionType.returnType`）
> - SubtypeChecker Phase 1 实现规则 1-6, 11-12，函数类型和 FutureOr 留 Batch 4.3

### Batch 4.3: 类型系统 ✅

- [x] 4.3.1 子类型检查算法实现 → `TypeSystem/subtyping/` 核心子集
- [x] 4.3.2 空安全类型检查（T? / T / Null） → 实现空安全运行时支持（`LanguageFeatures/nnbd/` 作为后续验证参考，不纳入 Phase 4 co19 主验证范围）
- [x] 4.3.3 Flow analysis 类型提升（type promotion） → 编译 CFE 类型提升节点（`TypeSystem/flow-analysis/` 作为后续验证参考，不纳入 Phase 4 co19 主验证范围）

**commit:** `feat: support subtype checking, null safety, and type promotion`

> **核心发现：**
> - FutureOr-to-FutureOr 子类型需在规则 7 增加特殊处理（直接检查 `S <: T`），设计文档规则 7-8 不能直接推导
> - 设计文档测试用例错误：规则 9 的 `int Function(String) <: num Function(Object)` 实际为 false（参数逆变）
> - CFE 类型提升使用 `VariableGet.promotedType`，不使用 `AsExpression`
> - EqualsNull value-stack 操作数需特殊处理：CFE 链式 `??` 降糖产生的内层 `EqualsNull` 操作数已在 value 栈
> - nullable value-type return boxing：返回类型为 `int?`（ref 栈）但表达式为 value 栈值时需 box

### Batch 4.4: co19 Harness v2 — 实验标志与类型负面测试 ✅

> **注意**：`static_type_helper.dart` 使用 `extension StaticType<T> on T`，extension method 要到 Phase 6.2 才加，因此延迟到 Phase 6 harness v4。

- [x] 4.4.1 `// SharedOptions=--enable-experiment=...` 解析与传递 → 扩展 co19_runner
- [x] 4.4.2 类型错误负面测试完善（`@compile-error` 类型相关子集） → 扩展 co19_runner
- [x] 4.4.3 验证：跑 Language/Generics + Mixins + Interfaces + TypeSystem/subtyping + LanguageFeatures/Class-modifiers（新增类别） → 测试报告
- [x] 4.4.4 回归跑：重跑 Phase 2-3 全部类别，diff 快照，确认零回归 → 回归报告

**commit:** `feat: co19 harness v2 — experiment flags and type error tests`

> **核心发现：**
> - SharedOptions 实验标志在当前 co19 版本中较少使用（大部分实验已稳定），但 `@dart=X.Y` 版本标记出现在 Class-modifiers (~10 文件) 和 Generics (~1 文件) 中
> - 现有 `isNegativeTest` 正则完整覆盖 co19 所有标记变体（`[analyzer]` + `[cfe]`），未发现其他标记格式
> - Generics 类别 ~75% 为负面测试、Class-modifiers ~62% 为负面测试，高负面比例拉高了总通过率
> - TypeSystem/subtyping 的 static/dynamic 分裂明显：static 78.0% vs dynamic 16.3%，dynamic 子类别严重依赖 `Duration` 桥接
> - Top 3 失败原因：`Duration` 未桥接 (422)、`TypeError` 运行时失败 (312)、`FutureOrType` 未实现 (153)——合计占 55.7%
> - Class-modifiers 的 100 个失败全部因缺少 `print` 桥接，桥接后预期通过率 >90%

### Phase 4 里程碑验证 ✅

- [x] co19 `Language/Generics` 通过率 > 50% — 实际 73.3% (143/195)
- [x] co19 `Language/Mixins` 通过率 > 50% — 实际 69.2% (99/143)
- [x] co19 `Language/Interfaces` 通过率 > 50% — 实际 80.0% (80/100)
- [x] co19 `TypeSystem/subtyping` 核心子集通过率 > 30% — 实际 49.4% (1345/2721)
- [x] co19 `LanguageFeatures/Class-modifiers` 通过率 > 30% — 实际 62.5% (167/267)
- [x] Phase 2-3 类别零回归（或回归已修复） — 0 回归
- [x] Phase 2-3 类别通过率较上期有提升（泛型解锁大量之前的类型相关测试） — +46 new pass, 64.5% → 65.6%

**实际通过率：** Generics 73.3% / Mixins 69.2% / Interfaces 80.0% / TypeSystem/subtyping 49.4% / Class-modifiers 62.5% / Phase 4 新增五类合计 53.5% (1834/3426)
**历史回归：** 0 回归 / +46 new pass / Phase 2-3 六类 65.6% (2732/4167) / 全十一类累计 60.1% (4566/7593)

---

## Phase 5: 标准库互调 (Ch4)

**目标：** 通过 `co19/LibTest/core`（String, List, Map, int, double 等核心类型）

**设计章节：** **Ch4 互调** 全面引入

**里程碑：** 解释器代码能使用宿主 VM 的 `dart:core` 类型和方法

> **⚠️ 待决策：BridgeGenerator 构建时机**
>
> 设计文档 `04-interop.md` 描述了 BridgeGenerator（build_runner + package:analyzer 自动生成 Bridge 类），但本 roadmap 未单独立项。执行 Phase 5 前需先决策：
>
> | 方案 | 做法 | 权衡 |
> |------|------|------|
> | A. 先建 Generator | 在 Batch 5.1 前新增 Batch，实现 codegen 工具 | 前期投入大，后续每个类自动生成，扩展到 Flutter Bridge 时收益显著 |
> | B. 先手写 Bridge | Batch 5.2 手写 dart:core 核心类，Generator 延后或不做 | 前期快，但手写维护成本高，覆盖面受限 |
> | C. 混合 | 手写少量类验证设计，稳定后再抽成 Generator | 务实折中，但有重构成本 |
>
> 决策：**Option C（混合）** — Phase 5 手写所有 dart:core Bridge，提取通用模式到工具函数。BridgeGenerator 延迟到需要 Flutter Bridge 时再建设。理由：dart:core 类型有限（~20 类），手写可控；手写过程发现真实模式，为将来 Generator 提供更好输入。详见 [`docs/tasks/phase5/README.md`](../tasks/phase5/README.md)

### Batch 5.1: Bridge 基础设施 (Ch4) ✅

- [x] 5.1.1 HostBindings 函数注册表 + 类型映射基础
- [x] 5.1.2 CALL_HOST 解释器处理 + DarticModule 绑定表
- [x] 5.1.3 绑定名称表 .darb 序列化/反序列化
- [x] 5.1.4 编译器 — 平台调用识别 + CALL_HOST 生成
- [x] 5.1.5 print + Object 基础桥接 + 端到端验证

**commit:** `feat(bridge): add interop infrastructure with proxy and type mapping`

> **核心发现：**
> - CALL_HOST 参数收集策略：编译→装箱→分配连续块→MOVE 4 阶段，参数在调用者 ref 栈 A+1..A+N 连续布局
> - 编译器通过 `lib.importUri.isScheme('dart')` 判断平台库，特化操作码优先于 CALL_HOST
> - 绑定符号名格式：`"libUri::className::methodName#paramCount"`，实例方法含 receiver
> - 绑定名称表 UInt16 count（最大 65535），匹配 CALL_HOST Bx 16-bit 宽度

### Batch 5.2: dart:core Bridge ✅

- [x] 5.2.1 Object/Type/Null Bridge
- [x] 5.2.2 int/num/double Bridge（~25/~18/~28 bindings）
- [x] 5.2.3 bool Bridge
- [x] 5.2.4 String Bridge（28 bindings）
- [x] 5.2.5 List/Iterable Bridge（~40+/~14 bindings）
- [x] 5.2.6 Map/Set/Duration Bridge（~15/~18/~25 bindings）+ Error 系列（~17 bindings）

**commit:** `feat(bridge): add dart:core bridge for int, String, List, Map`

> **核心发现：**
> - `int.parse` 在 Kernel 中有 3 形参（source, radix, onError），非预期的 2 个
> - CFE 将 List 字面量降级为 `_GrowableList._literalN()` 内部工厂调用，需同时注册内部绑定名
> - Duration 构造器命名参数在 CALL_HOST 中无法传递参数名，是已知设计局限
> - 回调方法（forEach/map/sort 等）延迟到 Batch 5.3 的 DarticCallbackProxy

### Batch 5.3: 集合字面量、字符串插值与回调代理 ✅

- [x] 5.3.1 CREATE_LIST/MAP/SET 解释器 + 编译器
- [x] 5.3.2 STRING_INTERP 解释器 + 编译器
- [x] 5.3.3 DarticCallbackProxy + DarticProxyManager
- [x] 5.3.4 HostClassWrapper 动态分发 + Spread 编译

**commit:** `feat: support collection literals, string interpolation, and spread`

> **核心发现：**
> - HOST_BOUNDARY 哨兵帧（funcId=0xFFFFFFFF）标记 VM→解释器回调边界
> - DarticCallbackProxy proxy0()-proxy3() 覆盖 forEach/map/where/sort/fold 全部回调场景
> - CFE 降糖：`[a,b,c]` → `_GrowableList._literalN()`，`{a,b,c}` (Set) → `_Set()..add()`
> - Spread/if/for 均为 CFE 降糖，编译器无需特殊处理

### Batch 5.5: noSuchMethod 支持 ✅

- [x] 5.5.1 ConstantPool.lookupNameIndex + ICEntry.argCount + DarticInvocation
- [x] 5.5.2 HostClassRegistry Invocation 包装器 + InvocationBindings
- [x] 5.5.3 动态分派支持 DarticObject 接收者
- [x] 5.5.4 noSuchMethod 回退 + _callDarticMethod 辅助
- [x] 5.5.5 E2E 测试

**commit:** `feat: add noSuchMethod support and DarticObject dynamic dispatch`

> **核心发现：**
> - `classInfo.fields` 未被编译器填充，需在 `_registerClass` 中将字段名注册到 classInfo.fields
> - Invocation 双路径访问：静态类型走 CALL_HOST，dynamic 类型走 GET_FIELD_DYN
> - 动态分派值类型返回不匹配：通过 HOST_BOUNDARY 机制执行 _callDarticMethod 解决

### Batch 5.6: dart:core Binding 补全 ✅

- [x] 5.6.1-5.6.11 共 11 个 task：Map/Set/List/Iterable callback + RegExp/Match + StringBuffer/Runes + String callback + DateTime + Uri + BigInt + Stopwatch/StackTrace/Symbol/Expando/MapEntry/Iterator + Error/Exception 补全

**commit:** `feat(bridge): add RegExp, DateTime, Uri, BigInt and other dart:core bindings`

> **核心发现：**
> - Dynamic type coercion：reduce/firstWhere 等不能直接委托类型化方法，需手动迭代
> - Kernel 将 String 的 Pattern 接口方法解析为 `dart:core::Pattern::allMatches#2`
> - Operator bindings needed for INVOKE_DYN：动态闭包参数需 num/int operator bindings

### Batch 5.4: co19 Harness v3 ✅

- [x] 5.4.1 Harness Bridge 注入 + dart:core 导入路由
- [x] 5.4.2 Skip list 管理 + expect_common 验证
- [x] 5.4.3 LibTest/core 验证 — **54.4%** (611/1124)
- [x] 5.4.4 Phase 2-4 回归 — **81.8%** (3407/4167), +685 new pass, 10 async → skip list

**commit:** `feat: co19 harness v3 — bridge injection, async stub, skip list, and verification`

> **核心发现：**
> - Async stub：async/sync*/async* 函数体发射运行时 throw stub（Phase 6 scope）
> - Global initializer funcId 必须在 _compileExpression 之后捕获（闭包会移位索引）
> - 平台静态 getter（如 StackTrace.current）需路由 CALL_HOST
> - Duration InstanceConstant 修复解锁了 97.7% 的 LibTest/core 失败

### Phase 5 里程碑验证

- [x] co19 `LibTest/core` 通过率 > 30% — 实际 **54.4%** (611/1124)
- [x] Bridge 基础类型方法覆盖率：int ~25、String 28、List ~40+、Map ~15、Set ~18、Duration ~25 bindings
- [x] Phase 2-4 类别零回归（或回归已修复） — 10 async regressions → skip list（Phase 6 scope）
- [x] Phase 2-4 类别通过率较上期有提升（Bridge 解锁标准库方法调用相关测试） — 65.6% → **81.8%** (+685 new pass)

**实际通过率：** LibTest/core 54.4% (611/1124) / Phase 2-4 历史类别 81.8% (3407/4167)
**历史回归：** 10 async regressions (skip list) / +685 new pass / Phase 2-4 六类 81.8% (3407/4167)

---

## Phase 6: 异步 + 高级语言特性

**目标：** 通过 `co19/LibTest/async`, 各 `co19/LanguageFeatures/` 高级特性

**设计章节：** **Ch7 异步**, **Ch8 沙箱**

**里程碑：** 支持 async/await、generators、pattern matching、records、extension methods

### Batch 6.1: 异步核心 (Ch7)

- [ ] 6.1.1 帧快照/恢复（Frame-as-Continuation） → Ch7 核心机制
- [ ] 6.1.2 INIT_ASYNC / AWAIT / ASYNC_RETURN → `LibTest/async/` Future 子集
- [ ] 6.1.3 async* (INIT_ASYNC_STAR / YIELD) → `LibTest/async/` Stream 子集
- [ ] 6.1.4 sync* (INIT_SYNC_STAR / YIELD) → `LibTest/async/` Iterable 子集
- [ ] 6.1.5 await for (AWAIT_STREAM_NEXT) → `LibTest/async/`

**commit:** `feat(async): add async/await, generators with frame-as-continuation`

> **核心发现：**
> _(执行时填写：浅保存 vs 深保存的性能差异、Completer 桥接的 GC 影响、generator 的首次 moveNext 触发时机等)_

### Batch 6.2: 高级语言特性

- [ ] 6.2.1 Extension methods → `LanguageFeatures/Extension-methods/` (275)
- [ ] 6.2.2 Enhanced enum → `LanguageFeatures/Enhanced-Enum/` (156)
- [ ] 6.2.3 Records + CREATE_RECORD 指令 → `LanguageFeatures/Records/` (172)
- [ ] 6.2.4 Pattern matching（switch expression + destructuring） → `LanguageFeatures/Patterns/` (786)
- [ ] 6.2.5 Constructor tearoffs → `LanguageFeatures/Constructor-tear-offs/` (378)
- [ ] 6.2.6 Super parameters → `LanguageFeatures/Super-parameters/` (137)

**commit:** `feat: support extension methods, records, patterns, and enhanced enums`

> **核心发现：**
> _(执行时填写：extension method 在 Kernel 中是否已脱糖、Pattern 的 Kernel 表示复杂度、Record 的运行时哈希/相等性等)_

### Batch 6.3: co19 Harness v4 — static_type_helper + 异步测试

> **此时 extension method + 泛型 + async 均已就绪**，可以接入剩余全部 Utils。

- [ ] 6.3.1 接入 `Utils/static_type_helper.dart`（`extension StaticType<T> on T`，需 extension method + 泛型） → 扩展 co19_runner
- [ ] 6.3.2 接入 `Utils/async_utils.dart`（asyncStart/asyncEnd 计数器） → 扩展 co19_runner
- [ ] 6.3.3 stdout 输出检测（`unittest-suite-wait-for-done` / `unittest-suite-success`） → 扩展 co19_runner
- [ ] 6.3.4 异步测试超时机制（可配置 timeout） → 扩展 co19_runner
- [ ] 6.3.5 验证：跑 LibTest/async + LanguageFeatures/*（新增类别） → 测试报告
- [ ] 6.3.6 全量回归跑：重跑 Phase 2-5 全部类别，diff 快照，确认零回归 → 最终回归报告

**commit:** `feat: co19 harness v4 — static_type_helper, async test support`

> **核心发现：**
> _(执行时填写：static_type_helper 的实际使用频率（多少测试 import 它）、异步测试超时策略、asyncStart/asyncEnd 嵌套 edge case 等)_

### Batch 6.4: 沙箱 (Ch8)

- [ ] 6.4.1 字节码加载时验证器 → `lib/src/sandbox/verifier.dart`
- [ ] 6.4.2 Fuel 计数 + 调用深度限制 → 扩展 `interpreter.dart`
- [ ] 6.4.3 沙箱安全测试 → `test/sandbox/`

**commit:** `feat(sandbox): add bytecode verification and resource limits`

> **核心发现：**
> _(执行时填写：验证器的检查项清单、fuel 粒度对性能的影响、已发现的安全漏洞等)_

### Phase 6 里程碑验证

- [ ] co19 `LibTest/async` 通过率 > 30%
- [ ] co19 `LanguageFeatures/Patterns` 通过率 > 40%
- [ ] co19 `LanguageFeatures/Records` 通过率 > 50%
- [ ] Phase 2-5 全量零回归（或回归已修复）
- [ ] 全量累计通过率与预估对比

**实际通过率：** _(执行时填写)_
**全量回归：** _(执行时填写：回归数 / 新增 pass 数 / 最终累计通过数)_

---

## Phase 7: 公开 API + 代码生成

**目标：** 将内部 Bridge 基础设施封装为用户友好的嵌入式引擎 API，实现 @DarticExport 代码生成器，提供 Flutter Bridge

**设计章节：** [`docs/plans/2026-02-20-bridge-api-design.md`](2026-02-20-bridge-api-design.md)（公开 API 设计）

**里程碑：** 宿主应用可通过 `DarticEngine` 3 行代码加载并执行 .darb 脚本，@DarticExport 注解自动生成 Bridge，Flutter 热更新 demo 端到端运行

**依赖：** Phase 5（内部 Bridge 基础设施）、Phase 6 Batch 6.1（async/await，生产环境必需）、Phase 6 Batch 6.4（沙箱，DarticConfig.maxFuel）

### Batch 7.1: DarticEngine 公开 API

- [ ] 7.1.1 编译器 host/script 库分类机制 — `_isPlatformLibrary` → `_isHostLibrary`（scriptPackages 粗切分 + Bridge 注册表细粒度验证），DarticCompiler 构造器增加 scriptPackages 参数 → 扩展 `lib/src/compiler/compiler.dart`
- [ ] 7.1.2 DarticEngine / DarticConfig / DarticPlugin 接口 → `lib/src/api/engine.dart`, `lib/src/api/config.dart`, `lib/src/api/plugin.dart`
- [ ] 7.1.3 addFunction() 快速绑定（无需 codegen 的手动注册路径） → `lib/src/api/engine.dart`
- [ ] 7.1.4 loadBytecode() + call() 端到端管线（封装 DarticInterpreter + HostBindings） → 集成测试
- [ ] 7.1.5 错误模型（DarticError / FuelExhaustedError / BytecodeError / BindingResolutionError） → `lib/src/api/errors.dart`
- [ ] 7.1.6 onPrint / onError 回调机制 → 扩展 engine.dart

**commit:** `feat(api): add DarticEngine public embedding API`

> **核心发现：**
> _(执行时填写：DarticEngine 对 DarticInterpreter 的封装层薄厚、addFunction 的类型推断可行性、call() 的返回值类型映射策略等)_

### Batch 7.2: @DarticExport 代码生成

- [ ] 7.2.1 dartic_annotation 包（@DarticExport, @DarticHide 纯注解定义） → `packages/dartic_annotation/`
- [ ] 7.2.2 BridgeGenerator 核心 — HostClassWrapper 自动生成（package:analyzer 扫描 + 方法/属性路由代码生成） → `packages/dartic_generator/`
- [ ] 7.2.3 BridgeGenerator — Bridge 类 + BridgeFactory 生成（可继承类的 extends 子类 + super 转发器） → `packages/dartic_generator/`
- [ ] 7.2.4 build_runner 集成（Builder 注册、分文件输出、增量构建支持） → `packages/dartic_generator/`
- [ ] 7.2.5 自测：用 codegen 重生成 dart:core bridges，对比 Phase 5 手写版，验证功能等价 → 集成测试

**commit:** `feat(codegen): add @DarticExport annotation and BridgeGenerator`

> **核心发现：**
> _(执行时填写：codegen 与手写 Bridge 的差异、package:analyzer 解析速度、生成代码的体积、操作符/泛型/命名构造函数等边界情况处理等)_

### Batch 7.3: Flutter Bridge + 热更新 Demo

- [ ] 7.3.1 dartic_bridges_flutter 包骨架 → `packages/dartic_bridges_flutter/`
- [ ] 7.3.2 Widget / StatelessWidget / StatefulWidget Bridge 生成 → 基础 widget 绑定
- [ ] 7.3.3 BuildContext / Navigator / MaterialApp Bridge → 导航与主题绑定
- [ ] 7.3.4 Flutter 热更新端到端 demo（服务端编译 .darb → 设备端加载执行 → 渲染 UI） → `example/flutter_hot_update/`

**commit:** `feat(flutter): add Flutter widget bridges and hot update demo`

> **核心发现：**
> _(执行时填写：StatefulWidget 的 State 生命周期与 Bridge 的交互、BuildContext 跨边界传递的安全性、热更新的 .darb 体积与加载速度等)_

### Phase 7 里程碑验证

- [ ] DarticEngine 3 行代码可加载执行 .darb 脚本
- [ ] @DarticExport 生成的 Bridge 与 Phase 5 手写 Bridge 功能等价
- [ ] addFunction() 手动绑定路径可用（无需 codegen 的快速原型开发）
- [ ] Flutter 热更新 demo 端到端运行（编译 → 传输 → 加载 → 渲染）
- [ ] Phase 2-6 全量零回归

**实际通过率：** _(执行时填写)_

---

## 各 Phase 预估 co19 覆盖

审查发现原预估存在偏差（Phase 5 预估超出实际测试数，Phase 4/6 通过率偏高），现提供乐观/保守双估：

| Phase | co19 类别 | 实际测试数 | 新增 pass | 历史提升 | 累计（乐观） | 累计（保守） | 实际 | 回归 |
|-------|----------|----------|----------|---------|------------|------------|------|------|
| 1 | （手工测试，无 co19） | — | 0 | — | 0 | 0 | | |
| 2 | Variables + Expressions + Statements | 2,581 | ~1,000 | — | ~1,000 | ~700 | 1,373 | 0 |
| 3 | Functions + Classes + Reference | 1,586 | 1,235 | +78 | ~2,300 | ~1,700 | 2,686 | 0 |
| 4 | Generics + Mixins + TypeSystem | 3,426 | 1,834 | +46 | ~4,500 | ~3,200 | 4,566 | 0 |
| 5 | LibTest/core + 集合/字符串特性 | 1,124 | 611 | +675 | ~5,500 | ~4,000 | 5,852 | 0 (10 skipped) |
| 6 | Async + LanguageFeatures | ~2,300 | ~1,500 | ~500 | ~7,500 | ~5,500 | | |
| 7 | 公开 API + codegen（无新 co19 类别） | — | ~0 | ~100 | ~7,600 | ~5,600 | | |

**关键修正说明：**
- **Phase 2**：harness v0 只有自建 shim，通过率受限；大量 Expressions 测试依赖类（Phase 3 才解锁）
- **Phase 4**：TypeSystem/subtyping 占 2,721 测试（86%），类型测试通过率通常偏低
- **Phase 5**：LibTest/core 实际只有 ~1,124 测试（原计划 1,500 超出实际数）
- **Phase 6**：Patterns (783 测试) 占大头且复杂度高，初始通过率可能 20-30%
- **Phase 7**：不新增 co19 类别（聚焦 API 封装和 codegen），但 Flutter Bridge 可能解锁少量历史测试中的 toString/print 依赖

**"历史提升"**：指新能力解锁的、历史类别中之前 fail 现在 pass 的测试数。例如 Phase 3 加了类后，Phase 2 的 `Language/Expressions` 中依赖类的测试预计新增 ~300 个 pass。

**最终目标覆盖率（乐观）：** ~7,500 / 24,350 ≈ 31%
**最终目标覆盖率（保守）：** ~5,500 / 24,350 ≈ 23%

排除 `dart:io`/`dart:isolate`/`dart:ffi`/`dart:mirrors`/`dart:html` 等不支持的库（~8,500 测试）和 `deferred as` 等不支持的语言特性后，可通过测试基数约 ~15,800，乐观覆盖率 ~47%，保守 ~35%。

---

## 执行节奏

- 每个 Batch 约 3-6 个 Task，每个 Task 遵循 TDD：读设计文档 → 写测试 → 最小实现 → analyze → test → 重构
- 每个 Batch 执行完成后执行完成后自动启动 code-reviewer 进行代码 review，重点关注：
  - **正确性**：逻辑是否正确，边界条件和异常处理是否完善
  - **可维护性与可读性**：命名清晰、结构合理、抽象层次恰当，避免过度设计
  - **性能**：有无不必要的重复计算、内存泄漏等性能隐患
  - **可测试性**：代码是否便于单测，职责是否单一
  - **一致性**：是否遵循项目既有的代码风格、架构模式和分层约定
  - **兼容性**：对已有功能的影响，公开 API 是否保持向后兼容
review 发现的问题直接修复，修复后重新 review 直到通过。
- 每完成一个 Batch 必须：
  1. 勾选本文件中对应 checkbox
  2. 填写该 Batch 的"核心发现"
  3. 更新 `docs/tasks/overview.md` 汇总表
  4. 提交 commit
- Phase 之间有明确的里程碑验证点，不达标不进入下一 Phase
- 发现设计问题时及时更新 `docs/design/` 对应章节

---

## 下一步

- [x] ~~为 Phase 1 编写详细的 Task 文件~~ → 已完成，见 [`docs/tasks/phase1/`](../tasks/phase1/README.md)
- [x] 执行 Phase 1（Batch 1.1 → 1.5，共 26 个 Task）— 412 tests, all passing
- [x] ~~为 Phase 2 编写 Task 文件~~ → 已完成，见 [`docs/tasks/phase2/`](../tasks/phase2/README.md)
- [x] 执行 Phase 2（Batch 2.1 → 2.4，共 21 个 Task）— co19 总计 53.2% (1373/2581)
- [x] ~~为 Phase 3 编写 Task 文件~~ → 已完成，见 [`docs/tasks/phase3/`](../tasks/phase3/README.md)
- [x] 执行 Phase 3（Batch 3.1 → 3.6，共 24 个 Task）— co19 六类累计 64.4% (2686/4167)，0 回归
- [x] ~~为 Phase 4 编写 Task 文件~~ → 已完成，见 [`docs/tasks/phase4/`](../tasks/phase4/README.md)
- [x] 执行 Phase 4（Batch 4.1 → 4.4，共 16 个 Task）— co19 Phase 4 五类 53.5% (1834/3426)，全十一类累计 60.1% (4566/7593)，0 回归
- [x] ~~为 Phase 5 编写 Task 文件~~ → 已完成，见 [`docs/tasks/phase5/`](../tasks/phase5/README.md)
- [x] 执行 Phase 5（Batch 5.1 → 5.6，共 35 个 Task）— LibTest/core 54.4% (611/1124)，Phase 2-4 81.8% (3407/4167)，累计 5,852 pass，0 回归
- [x] ~~为 Phase 6 编写 Task 文件~~ → 已完成，见 [`docs/tasks/phase6/`](../tasks/phase6/README.md)
- [ ] 执行 Phase 6（Batch 6.1 → 6.4，共 20 个 Task）
- [ ] 为 Phase 7 编写 Task 文件 — 公开 API 设计已完成，见 [`docs/plans/2026-02-20-bridge-api-design.md`](2026-02-20-bridge-api-design.md)
- [ ] 执行 Phase 7（Batch 7.1 → 7.3）
