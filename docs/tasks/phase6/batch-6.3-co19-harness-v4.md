# Batch 6.3: co19 Harness v4 — static_type_helper + 异步测试 + dart:async Bridge

## 概览

将 co19 测试运行器升级到 v4：(1) 构建 dart:async Bridge 为 LibTest/async 测试提供 Future/Stream/Completer/Timer 等标准库绑定；(2) 接入 `Utils/static_type_helper.dart`（需 extension method + 泛型，此时均已就绪）和 `Utils/async_utils.dart`（asyncStart/asyncEnd 计数器）；(3) 实现异步测试协议——stdout 标记检测（unittest-suite-wait-for-done / unittest-suite-success）和超时机制；(4) 完整的 expect.dart 升级（去掉简化版限制，使用完整的 vendor expect.dart）；(5) 跑 Phase 6 新增全部 co19 类别 + 全量回归。

> **为什么 dart:async Bridge 在 Batch 6.3 而非 6.1？** Batch 6.1 的运行时异步实现直接使用 Dart API（`Completer<T>()`、`scheduleMicrotask` 等），不经过 CALL_HOST。dart:async Bridge 是为**用户代码**（co19 测试中 `import 'dart:async'; var c = Completer<int>();`）提供的 CALL_HOST 绑定。

**设计参考：** `docs/plans/development-roadmap.md`（co19 harness v4 规格）、`tool/co19_runner.dart`（当前 harness v3）、`vendor/co19/Utils/async_utils.dart`、`vendor/co19/Utils/static_type_helper.dart`

**依赖：** Batch 6.1（async 运行时）+ Batch 6.2（extension methods, records 等）

---

### Task 6.3.1: dart:async Bridge

**产出文件：**
- Create: `lib/src/bridge/async_bindings.dart`（dart:async 绑定注册入口）
- Create: `lib/src/bridge/wrappers/future_wrapper.dart`（Future 方法桥接）
- Create: `lib/src/bridge/wrappers/stream_wrapper.dart`（Stream/StreamController 方法桥接）
- Create: `lib/src/bridge/wrappers/completer_wrapper.dart`（Completer 方法桥接）
- Create: `lib/src/bridge/wrappers/timer_wrapper.dart`（Timer 方法桥接）
- Modify: `lib/src/bridge/core_bindings.dart`（注册 AsyncBindings）
- Modify: `tool/co19_runner.dart`（dart:async 加入 _supportedDartLibraries）
- Test: `test/bridge/async_bindings_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch4 互调中 Bridge 绑定模式（Phase 5 已建立的 HostClassWrapper 模式）。dart:async 核心类型清单：Future（value, error, then, catchError, whenComplete, wait, any, delayed, microtask, doWhile, forEach, sync, timeout）、Stream（listen, first, last, length, isEmpty, toList, map, where, expand, take, skip, handleError, asyncMap, asyncExpand, transform, pipe, forEach, drain, every, any, contains）、Completer（constructor, complete, completeError, future getter, isCompleted getter）、StreamController（constructor, broadcast, add, addError, addStream, close, stream getter, sink getter, done getter, hasListener, isClosed, isPaused）、Timer（constructor, run, periodic, cancel, tick, isActive）、Zone（current, root, run, runGuarded, runUnary, runBinary, fork, bindCallback）
2. **写测试** — 验证各类型的核心方法通过 CALL_HOST 绑定可用：
   - Future.value(42) 创建已完成 Future
   - Future.delayed(Duration.zero, () => 42) 创建延迟 Future
   - Future.wait([f1, f2]) 等待多个 Future
   - Completer\<int\>() 构造 + complete(42) + future getter
   - StreamController\<int\>() 构造 + add + close + stream getter
   - Stream.fromIterable([1,2,3]).toList()
   - Timer.run(() { ... }) 零延迟回调
   - Timer(Duration(seconds: 1), callback) 延时回调
3. **实现** —
   - **AsyncBindings 类**：参照 CoreBindings 模式，提供 `registerAll(HostBindings)` 方法
   - **Future 绑定**：构造器（value/error/delayed/microtask/sync）、实例方法（then/catchError/whenComplete/timeout）、静态方法（wait/any/doWhile/forEach）。注意 then/catchError 的回调参数通过 DarticCallbackProxy 桥接
   - **Stream 绑定**：listen（返回 StreamSubscription）、collection 方法（toList/first/last 等）、转换方法（map/where/expand 等）。listen 的回调参数通过 DarticCallbackProxy
   - **Completer 绑定**：constructor/complete/completeError/future/isCompleted
   - **StreamController 绑定**：constructor/broadcast/add/addError/close/stream/sink/done/hasListener。onListen/onPause/onResume/onCancel setter 的回调通过 DarticCallbackProxy
   - **Timer 绑定**：constructor/run/periodic/cancel/tick/isActive
   - **Zone 绑定**：current/run/runGuarded（按需，仅在 co19 测试需要时）
   - co19_runner.dart：将 `'dart:async'` 加入 `_supportedDartLibraries`
4. **运行** — `fvm dart analyze && fvm dart test test/bridge/async_bindings_test.dart`

---

### Task 6.3.2: static_type_helper + async_utils + expect.dart 升级

**产出文件：**
- Modify: `tool/co19_runner.dart`（static_type_helper + async_utils 集成）
- 可能 Modify: vendor expect.dart 简化版（升级为完整版）
- Test: `test/tool/co19_utils_integration_test.dart`

**TDD 步骤：**

1. **读设计文档** —
   - `vendor/co19/Utils/static_type_helper.dart`：定义 `extension StaticType<T> on T`，提供 `expectStaticType<R extends Exactly<T>>()` 等编译时类型检查方法。依赖：extension method（6.2.1）+ 泛型（Phase 4）。约 91 行
   - `vendor/co19/Utils/async_utils.dart`：定义 `asyncStart([count])`/`asyncEnd()`（异步测试生命周期计数器）、`asyncTest()` wrapper、`AsyncExpect.value/error/data/events`、`Sync2<T>` 双值同步器。打印 `unittest-suite-wait-for-done`/`unittest-suite-success` 标记。约 235 行
   - `vendor/co19/Utils/expect.dart`：当前使用简化版（Phase 3 建立，去掉 dart:async + implements Exception + 泛型限制）。现在 dart:async 已桥接、类/泛型/implements 均支持，可尝试编译完整 vendor 版本
2. **写测试** — 验证 Utils 编译和运行：
   - 编译 `vendor/co19/Utils/static_type_helper.dart`（作为 library 被 import）不报错
   - 使用 static_type_helper 的简单测试：`42.expectStaticType<Exactly<int>>()`
   - 编译 `vendor/co19/Utils/async_utils.dart` 不报错
   - asyncStart/asyncEnd 计数器正确递增/递减
   - asyncTest wrapper 正确管理生命周期
   - 完整 vendor expect.dart 编译不报错（包含 dart:async import 和 part 'expect_common.dart'）
   - Expect.equals / Expect.isTrue / Expect.throws 通过完整 vendor expect.dart 工作
3. **实现** —
   - **static_type_helper 集成**：确保 co19_runner 编译测试时正确解析 `../../Utils/static_type_helper.dart` 的相对路径 import。如果 extension method 编译有问题（6.2.1 应已修复），在此补修
   - **async_utils 集成**：确保 asyncStart/asyncEnd 可编译执行。co19 async 测试使用这些函数标记异步测试的开始/结束
   - **expect.dart 升级**：
     - 尝试编译完整 vendor expect.dart（不再使用简化版）
     - 如果编译成功 → 切换 co19_runner 使用完整版
     - 如果有残余问题（如 dart:async 的特定 API 未桥接）→ 保留最小简化，记录具体缺失
   - **co19_runner 修改**：更新 import 解析逻辑，支持 static_type_helper.dart 和 async_utils.dart 的编译
4. **运行** — `fvm dart analyze && fvm dart test test/tool/co19_utils_integration_test.dart`

---

### Task 6.3.3: 异步测试协议 — stdout 检测 + 超时

**产出文件：**
- Modify: `tool/co19_runner.dart`（stdout 捕获 + 标记检测 + 超时机制）
- Test: `test/tool/co19_async_protocol_test.dart`

**TDD 步骤：**

1. **读设计文档** — co19 异步测试协议：
   - 测试调用 `asyncStart()` → 打印 "unittest-suite-wait-for-done"
   - 测试异步操作完成后调用 `asyncEnd()` → 计数器归零时打印 "unittest-suite-success"
   - 测试运行器需要：(a) 捕获 stdout 输出 (b) 检测 "unittest-suite-success" 标记 → pass (c) 检测超时且无 success 标记 → fail (d) 检测 "unittest-suite-wait-for-done" 但无 success → 等待异步完成
   - 非异步测试（无 "wait-for-done" 标记）按原有逻辑判断（无异常 = pass）
2. **写测试** — 验证异步测试协议：
   - 同步测试（无异步标记）按原有逻辑 pass/fail
   - 异步测试打印 wait-for-done + success → pass
   - 异步测试打印 wait-for-done 但超时无 success → fail（超时）
   - 异步测试抛出未捕获异常 → fail
   - 超时时间可配置（默认 30s，单测用短超时）
   - 嵌套 asyncStart/asyncEnd（count > 1）正确处理
3. **实现** —
   - **stdout 捕获**：解释器 print 回调（onPrint）已存在，收集输出到 StringBuffer
   - **标记检测**：执行后扫描输出：
     - 含 "unittest-suite-wait-for-done" → 标记为异步测试
     - 异步测试含 "unittest-suite-success" → pass
     - 异步测试无 "success" 且超时 → fail（timeout）
     - 非异步测试 → 按原有逻辑（无异常 = pass）
   - **超时机制**：
     - 异步测试使用 `Future.timeout()` 或 `Timer` 包装执行
     - 超时后终止解释器（清空 _runQueue，释放帧资源）
     - 可配置超时参数（CLI 参数或硬编码默认值）
   - **注意**：解释器的异步执行通过 microtask 调度，需要在 Dart event loop 中等待完成。co19_runner 的 runTest 需要支持真正的异步等待（可能已通过 DarticInterpreter 的 Future 返回值实现）
4. **运行** — `fvm dart analyze && fvm dart test test/tool/co19_async_protocol_test.dart`

---

### Task 6.3.4: dart:math + dart:collection Bridge（可选扩展）

**产出文件：**
- Create: `lib/src/bridge/math_bindings.dart`（dart:math 绑定）
- Create: `lib/src/bridge/collection_bindings.dart`（dart:collection 绑定）
- Modify: `tool/co19_runner.dart`（扩展 _supportedDartLibraries）
- Test: `test/bridge/math_bindings_test.dart`

**TDD 步骤：**

1. **读设计文档** — co19 测试中部分 Language/Expressions 和 LanguageFeatures 测试 import dart:math（min/max/sqrt/pow/sin/cos/Random 等）和 dart:collection（LinkedHashMap/LinkedHashSet/Queue/HashMap 等）。桥接这些库可以解锁更多历史测试
2. **写测试** — 验证核心方法：
   - dart:math：min, max, sqrt, pow, sin, cos, log, exp, pi, e, Random（nextInt, nextDouble, nextBool）
   - dart:collection：LinkedHashMap, LinkedHashSet, Queue, HashMap 的基础构造和方法
3. **实现** —
   - **MathBindings**：注册 dart:math 顶层函数和常量 + Random 类
   - **CollectionBindings**：注册 dart:collection 核心类的构造器和方法
   - **co19_runner**：将 dart:math 和 dart:collection 加入 _supportedDartLibraries
   - 按需实现——优先覆盖 co19 测试高频使用的方法
4. **运行** — `fvm dart analyze && fvm dart test test/bridge/math_bindings_test.dart`

> **注意**：此 Task 为可选扩展。如果时间不足可延迟到 Phase 7。主要收益是提升历史类别通过率。

---

### Task 6.3.5: 验证——跑 Phase 6 新增 co19 类别

**产出文件：**
- 产出: `tool/co19_results/phase6.json`（结果快照）

**TDD 步骤：**

1. **读设计文档** — Phase 6 新增 co19 类别和预估测试数：
   - LibTest/async：~557 测试（Future 96, Stream 207, Completer 21, StreamController 60, Timer 13, Zone 47, 其他 113）
   - LanguageFeatures/Extension-methods：~275
   - LanguageFeatures/Extension-types：~360
   - LanguageFeatures/Enhanced-Enum：~156
   - LanguageFeatures/Records：~172
   - LanguageFeatures/Patterns：~786
   - LanguageFeatures/Constructor-tear-offs：~378
   - LanguageFeatures/Super-parameters：~139
   - 合计：~2,823 测试。里程碑目标：LibTest/async > 30%，Patterns > 40%，Records > 50%
2. **执行验证** —
   - 配置 co19_runner 扫描全部 Phase 6 新增类别
   - 执行全量测试（~2,823 测试，并行度 8，超时 30s/test，异步测试超时 60s）
   - 收集各类别通过率
   - 识别主要失败原因（按错误类型分类：编译错误、运行时错误、超时、缺失绑定等）
   - 保存结果快照到 `tool/co19_results/phase6.json`
3. **结果分析** —
   - 对比里程碑目标
   - 各类别通过率细分
   - Top 10 失败原因
   - 识别因 Phase 7+ 特性（dart:io, deferred import 等）而失败的测试
   - 记录 CFE 脱糖验证结果（extension methods/patterns/super parameters 实际通过率是否符合预期）
4. **产出** —
   - 更新 `docs/plans/development-roadmap.md` Phase 6 实际通过率
   - 记录各类别通过率明细

---

### Task 6.3.6: 全量回归——重跑 Phase 2-5 全部类别

**产出文件：**
- 产出: `tool/co19_results/phase6-regression.json`（回归快照）

**TDD 步骤：**

1. **读设计文档** — Phase 2-5 历史类别清单（12 类 + LibTest/core）：
   - Phase 2-3（6 类，4,167 测试）：Variables, Expressions, Statements, Functions, Classes, Reference
   - Phase 4（5 类，3,426 测试）：Generics, Mixins, Interfaces, TypeSystem/subtyping, Class-modifiers
   - Phase 5（1 类，1,124 测试）：LibTest/core
   - 合计：~8,717 测试。Phase 5 基线：5,852 pass。预估 Phase 6 新增历史 pass：~200-500
2. **执行回归检测** —
   - 重跑全部历史类别（~8,717 测试）
   - 保存结果到 `tool/co19_results/phase6-regression.json`
   - diff phase5-regression.json + phase5.json vs phase6-regression.json
   - 输出分类：新增 pass / 回归 fail / 持续 pass / 持续 fail / 新增测试 / 移除测试
3. **回归修复** —
   - **回归项必须在本 Batch 内修复，不得带入 Phase 7**
   - 典型回归原因：async 编译改变了原有函数的编译路径、新 visitor 影响已有表达式编译、Record/Pattern 处理与已有 switch/conditional 冲突
   - 修复后重跑确认零回归
4. **结果分析** —
   - 记录历史提升量（预估 vs 实际）
   - 分析哪些新能力解锁了最多历史测试（async、extension methods、patterns 等）
   - 记录最终累计通过数和通过率
5. **产出** —
   - 更新 `docs/plans/development-roadmap.md` Phase 6 回归数据
   - 更新 `docs/tasks/overview.md` Phase 6 总结

---

## Commit

```
feat: co19 harness v4 — dart:async bridge, static_type_helper, async test protocol
```

**提交文件：** `lib/src/bridge/async_bindings.dart`（新文件）+ wrappers/（新文件）+ 修改的 co19_runner.dart + 结果快照文件 + 新测试

## 核心发现

_(执行时填写：dart:async Bridge 绑定数量、static_type_helper 的实际使用频率、asyncStart/asyncEnd 嵌套 edge case、完整 vendor expect.dart 编译是否成功、异步测试超时策略、各类别实际通过率 vs 预估、历史提升实际数量等)_

## Batch 完成检查

- [ ] 6.3.1 dart:async Bridge
- [ ] 6.3.2 static_type_helper + async_utils + expect.dart 升级
- [ ] 6.3.3 异步测试协议 — stdout 检测 + 超时
- [ ] 6.3.4 dart:math + dart:collection Bridge（可选扩展）
- [ ] 6.3.5 验证——跑 Phase 6 新增 co19 类别
- [ ] 6.3.6 全量回归——重跑 Phase 2-5 全部类别
- [ ] `fvm dart analyze` 零警告
- [ ] `fvm dart test` 全部通过
- [ ] 零回归（或回归已修复）
- [ ] commit 已提交
- [ ] overview.md 已更新
- [ ] development-roadmap.md Phase 6 里程碑已更新
- [ ] code review 已完成
