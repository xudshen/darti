# dartic 设计文档全面评审报告

> 评审日期：2026-02-17
> 评审范围：`docs/design/` 全部 8 个章节 + 业界对标研究
> 方法：9 个并行分析 agent 独立评审后汇总

---

## 一、总体结论

| 维度 | 评价 | 说明 |
|------|------|------|
| **技术可行性** | **可行** | 无根本性阻塞点，所有核心假设已有 POC 验证 |
| **行业对齐度** | **高度对齐** | 核心设计与 Lua 5.x、Hermes、WASM 解释器等成熟方案一致 |
| **性能目标** | **有挑战但可达** | 1/10 原生在业务逻辑场景可达，框架交互密集场景可能降至 1/20~1/50 |
| **iOS 合规性** | **完全合规** | 纯字节码解释，不生成原生代码，符合 App Store 政策 |

### 性能谱系定位

```
原生 AOT ─── Shorebird 补丁 ─── Hermes 字节码 ─── dartic 目标 ─── dart_eval ─── AST 遍历
  1.0x          ~0.98x            ~0.5-0.7x         ~0.1x          0.02-0.1x      0.01x
```

---

## 二、各章节评分与核心发现

| Chapter | 主题 | 评分 | 核心优势 | 最大风险 |
|---------|------|------|---------|---------|
| Ch0 总览 | 架构定位 | 9/10 | Kernel AST 输入，站在 CFE 肩膀上 | Bridge 覆盖面指数增长 |
| Ch1 ISA | 字节码指令集 | 8.5/10 | Lua 5.x 验证过的 32 位定宽编码 | WIDE 前缀规格不完整 |
| Ch2 运行时 | 分发循环/栈 | 9/10 | 双视图值栈（double 达原生 96%） | switch 分发无 computed goto |
| Ch3 互调 | Bridge/Proxy | 8/10 | 同 VM 零序列化，比 RN Bridge 快数量级 | 生成规模和版本维护 |
| Ch4 编译器 | Kernel→字节码 | 8.5/10 | Phase 分层务实，LSRA 正确推迟 | Kernel 版本耦合 |
| Ch5 泛型 | 实化泛型 | 7.5/10 | DarticType 驻留 + 延迟实例化 | TypeParameterType bound 解析缺失 |
| Ch6 异步 | async/await | 7.5/10 | 帧快照续体，业界标准做法 | 全局栈恢复冲突（P0） |
| Ch7 沙箱 | 安全模型 | 7/10 | 最小安全目标清晰，扩展点合理 | 热更新场景缺字节码签名 |

---

## 三、核心设计决策的行业验证

### 3.1 完全对齐行业最佳实践的决策

| 决策 | 对标项目 | 验证结论 |
|------|---------|---------|
| 寄存器式字节码 | Lua 5.x, Dalvik, wasmi v0.32 | wasmi 从栈式改为寄存器式获得 **5x 提升** |
| 32 位定宽指令 + `Uint32List` | Lua 5.x, wasm3 | 缓存友好，每缓存行 16 条指令 |
| 双视图值栈避免装箱 | Lua-CSharp 零分配策略 | POC 验证 double 性能达原生 **96%** |
| 离线编译+设备端执行 | Hermes (React Native) | Hermes 冷启动快 30-50%，dartic 同策略 |
| Kernel AST 作为输入 | **dartic 独创** | 复用 CFE 全部前端能力（25+ 语法特性脱糖） |
| GC 委托宿主 VM | MoonSharp, Jint | 自实现 GC 在托管 VM 内会与宿主 GC 冲突 |
| fuel 协作调度 | Lua `debug.sethook`, WASM fuel | 防止饿死宿主事件循环 |

### 3.2 dartic 的独特优势（vs 所有跨语言方案）

| 优势 | 原因 | 比较对象 |
|------|------|---------|
| **零序列化数据传递** | 同 VM 同堆，VM 对象直存引用栈 | RN Bridge 需 JSON 序列化 |
| **共享 GC** | 无需跨堆引用追踪 | JNI 需手动管理全局引用 |
| **共享类型系统** | Dart reified generics 可用于类型提取 | Java 类型擦除无法实现 |
| **同步互调** | 单线程同事件循环 | Platform Channels 至少一次 event loop 往返 |

---

## 四、需要优先解决的问题（按严重度排序）

### P0 — 正确性缺陷（必须修复）

| # | 问题 | 章节 | 影响 | 建议修复 |
|---|------|------|------|---------|
| 1 | **全局栈恢复冲突** | Ch6 | 多个 async 帧并发挂起时，恢复帧可能覆盖活跃帧数据 | 恢复时在栈顶重新分配空间，不写回原位置 |
| 2 | **AWAIT 快速路径违反 microtask 语义** | Ch6 | `await null` 不让出，可观察行为差异 | 非 Future 值也应 `scheduleMicrotask` 恢复 |
| 3 | **TypeParameterType bound 解析缺失** | Ch5 | 泛型函数体内 `is` 检查可能产生错误结果 | 补充 `isSubtypeOf` 中类型参数引用的处理 |

### P1 — 重要设计缺口

| # | 问题 | 章节 | 影响 | 建议 |
|---|------|------|------|------|
| 4 | **热更新缺字节码签名** | Ch7 | 无签名 = 远程代码执行漏洞 | Phase 1 即实现 Ed25519 签名验证 |
| 5 | **跨边界 `List<dynamic>` 兜底** | Ch5 | VM 侧 `is List<int>` 检查失败 | 至少为高频泛型组合提供类型化创建路径 |
| 6 | **DarticCallbackProxy 泛型签名丢失** | Ch5 | 回调传递可能触发运行时类型错误 | Bridge 预生成库提供类型化回调包装 |
| 7 | **频繁 await-resume 绕过 fuel 机制** | Ch6 | 大量 `await Future.value()` 可能饿死事件循环 | `_resumeFrame` 中也计入 fuel 消耗 |
| 8 | **WIDE 前缀规格不完整** | Ch1 | 实现时可能出现歧义 | 明确定义扩展字格式 |
| 9 | **回调重入时 fuel 机制行为未定义** | Ch7 | 回调中无限循环的处理不清晰 | 文档明确回调中的 fuel 语义 |

### P2 — 改进建议

| # | 问题 | 章节 | 建议 |
|---|------|------|------|
| 10 | Record 类型子类型检查缺失 | Ch5 | 补充 Record 相关子类型规则 |
| 11 | Source map 标记为 optional | Ch4 | 升级为 Phase 1 核心特性 |
| 12 | Mixin 组合的 Bridge 支持 | Ch3 | 分析 Flutter 常见 mixin 模式 |
| 13 | `CALL_HOST` 参数 List 每次分配 | Ch1/Ch2 | 预分配固定大小参数缓冲区 |
| 14 | Bridge API 暴露面安全指南 | Ch7 | 文档列出不应注册的库（dart:io, dart:ffi） |

---

## 五、各章节详细分析

### Ch0 — 架构总览

**核心优势**：以 Kernel AST 为输入是最关键也最正确的决策。CFE 已完成解析、类型推断、脱糖等全部前端工作，25+ 语法特性在 Kernel 层已处理。这使 dartic 在语言特性覆盖度上天然超越 dart_eval（使用 analyzer）和 d4rt（自定义解析）。

**最大风险**：Bridge 生成的覆盖面。dart:core 范围内可控，进入 Flutter 框架后 Widget 树、RenderObject 树、手势系统等涉及大量可继承类。Flutter `StatefulWidget` 需要 Bridge，`State<T>` 也需要泛型 Bridge，`SingleTickerProviderStateMixin` 需要 mixin Bridge，组合爆炸是真实的技术挑战。

**性能评估**：
- 计算密集型代码：1/5 ~ 1/3 原生（已验证）
- 混合业务逻辑：1/10 ~ 1/20 原生（目标可达）
- UI 渲染/框架交互密集代码：1/20 ~ 1/50 原生（Bridge 开销主导）

对于热更新目标场景，Widget build 方法通常只做声明式 Widget 树构建（创建几十个轻量对象），解释器性能足够。

### Ch1 — 字节码 ISA

**编码设计成熟**：四种编码格式（ABC / ABx / AsBx / Ax）直接借鉴 Lua 5.x 经典设计。8 位 opcode 提供 256 个操作码空间，目前使用到 ~0xA7，预留约 85 个槽位用于 Superinstruction。

**类型特化正确**：ISA 为 int 和 double 分别设计了独立的算术和比较操作码（`ADD_INT` vs `ADD_DBL`），利用 Dart 的静态类型信息在编译期完成特化，零运行时类型检查开销。CPython 3.11+ 的 Adaptive Interpreter 在运行时做的事情，dartic 在编译期就完成了。

**`Uint32List` 最优**：与 `List<int>` 相比，`Uint32List` 元素为原始 32 位值，读取后直接使用，避免 tagged integer 去标签操作，在内循环热路径上可带来 10-30% 性能差距。

**待改进**：
- WIDE 前缀扩展字格式不够精确，需在实现前明确
- 缺少 `NOT` 指令（逻辑非），需要用 `BIT_XOR A, B, #1` 间接实现
- `ADD_INT_IMM` 的 C 操作数应明确为无符号 0-255 还是有符号 -128~127

### Ch2 — 运行时

**双视图值栈是核心创新**：POC 基准数据有力证明——double 场景 AOT 性能达原生 96%，int 场景达 29%，混合场景 1.63x 优于装箱方案。这是达到 1/10 原生性能目标的基础。

**分发循环对齐行业**：
- 与 Lua lvm.c 高度相似（寄存器窗口 + 32 位定宽 + 内/外循环结构）
- 与 CPython ceval.c 对齐（switch 分发 + IC + quickening 路线）
- 与 JSC LLInt 对齐（IC 渐进策略：单态 → 多态 → 超态）

**IC 设计合理**：单态 IC 在典型面向对象代码中命中率约 85-95%。IC 命中为一次 int 比较 + 直接调用，vs 慢路径的 HashMap 查找，性能差异可达 10-50x。

**GC 委托正确**：在 Dart VM 内部实现独立 GC 不仅复杂（需处理与宿主 GC 的交互），且可能适得其反（双 GC 导致不可预测暂停）。值栈不含对象引用 → GC 不需扫描 → 隐含地减小了 GC 根集。

**固有限制**：
- 无 computed goto：每条指令必须回到 switch 入口再分发，约 20-30% 性能损失
- DarticObject 字段访问需三层间接（RefStack 索引 → 类型转换 → refFields 索引），vs 原生一层

### Ch3 — 互调/Bridge

**Bridge + Proxy 方案可行**：核心机制在 JNI、Lua C API、RN Bridge 中均有先例。dartic 的独特优势在于同 VM——零序列化、共享 GC、共享类型系统，比所有跨语言方案低 1-2 个数量级的互调开销。

**Expando 缓存精巧**：利用 Dart `Expando` 的 ephemeron 语义自动管理跨边界对象生命周期，完全消除了 JNI 式的引用泄漏风险。同一 `DarticObject` 多次跨边界传递，VM 侧始终得到同一个 proxy，保证 `identical()` 语义正确。

**CALL_HOST 开销分析**：总开销约 60-220ns，主要瓶颈是 `Function.apply` 的动态分发（50-200ns）。对于热点调用（如循环中的 `list.add`），特化 `HostClassWrapper` 绕过 `Function.apply` 是必要的优化。

**Bridge 生成规模**：Flutter 覆盖估计需要约 143 个 Bridge 类 + 303 个 Wrapper 类，总生成代码量约 50,000-100,000 行。对 build_runner 代码生成可接受，但版本同步是长期挑战。

**已知限制**：
- Dart 3.0 的 `sealed class` / `final class` 修饰符限制 Bridge 覆盖范围
- DarticProxy 无法通过 VM 侧 `is` 类型检查，需要 Bridge 覆盖所有需要 `is` 检查的类型
- Mixin 组合的 Bridge 支持未设计

### Ch4 — 编译器

**架构合理性评分：8.5/10**。Phase 1/2 分层策略正确——先用简单方案跑通全流程，用 profiling 数据驱动优化决策。

**Kernel AST 输入优势**：
- 回避 Dart 解析器全部复杂度
- 类型信息完整（CFE 已完成全量类型推断）
- 语义一致性有保障（所有脱糖由官方 CFE 完成）

**与 Lua 编译器同构**：32 位定宽指令 + 寄存器式架构 + 作用域级寄存器回收——与 Lua 5.x 的编译器一脉相承，经二十年验证的成熟方案。

**LSRA 优先级正确**：作用域级回收对典型 Dart 函数（<50 局部变量）已足够，LSRA 的主要收益场景（减少 async 帧快照大小）尚未成为瓶颈，推迟到 Phase 2+ 是务实的。

**.darb 格式亮点**：分区常量池（refs/ints/doubles/names）让 `LOAD_CONST_INT` 直接从 `Int64List` 读取，零装箱开销。绑定名称表的加载时解析实现了编译产物与 Bridge 库版本的解耦。

**关键风险**：`package:kernel` 是 Dart SDK 内部包，API 和二进制格式不受稳定性承诺保护。每次 SDK 大版本升级可能需要适配。

### Ch5 — 泛型

**延迟按需实化方案正确**：DarticType 驻留 + ITA/FTA 栈帧传递与 .NET CLR 的 reified generics 同源。驻留保证等价性判定退化为 `identical()`，O(1) 比较。

**内存开销可控**：中等 Flutter 应用的泛型实例化组合通常在 200-2000 个，TypeRegistry 总内存约 20-200 KB。

**正确性缺口**：
- **TypeParameterType bound 解析缺失（P0）**：`isSubtypeOf` 未处理类型参数引用，泛型函数体内 `is` 检查可能错误
- **Record 类型子类型检查未实现**：Dart 3 Records 的 `is` 检查不正确
- **CHECK_COVARIANT 指令语义未展开**：协变安全检查细节不足

**跨边界泛型是最大挑战**：
- 解释器 → VM：`List<dynamic>.from()` 兜底破坏类型安全
- Bridge 泛型实例化：Dart 无法在运行时动态决定泛型参数，需编译器静态分析所有组合
- DarticCallbackProxy 使用 `Object? Function(Object?)` 通用签名，可能触发类型不匹配

### Ch6 — 异步

**帧快照续体是正确路线**：充分利用"解释器帧天然在堆上"的结构优势，与 CPython、LuaJIT 等项目中的成功先例一致。

**快照成本极低**：典型帧 10-50 个槽位，80-400 字节 memcpy <1us，远低于 Future.then 回调注册的 5-10us。

**P0 正确性问题**：
1. **全局栈恢复冲突**：多个 async 帧并发挂起时，恢复帧可能覆盖活跃帧数据。修复方案：恢复时在栈顶重新分配空间（方案 A），或挂起时不释放栈区间（方案 B）。
2. **AWAIT 快速路径违反 microtask 语义**：`await null` 应让出一次 microtask，但快速路径跳过了，导致可观察行为差异。

**调度设计合理**：fuel 耗尽 → `Timer.run`（低优先级），await 恢复 → `scheduleMicrotask`（高优先级）。但频繁 await-resume 可能绕过 fuel 机制，需要在 `_resumeFrame` 中也计入 fuel 消耗。

**Zone 传播**：基本机制正确（`frame.capturedZone.scheduleMicrotask`），但 Zone.fork 在解释器中的处理（如 `runZoned`）需要通过 CALL_HOST 委托宿主 VM。

### Ch7 — 安全沙箱

**"最小安全"目标清晰**：明确划分了目标内（防崩溃、防卡死、防栈溢出）和目标外（不防恶意代码、不做 OS 级隔离）。对于热更新和可信插件场景，这是合理的定位。

**验证器覆盖良好**：操作码合法性、跳转目标边界、寄存器索引边界、常量池索引、WIDE 前缀合法性、函数引用、异常处理器范围、CRC32 校验均已覆盖。

**关键缺失**：
- **字节码签名**：CRC32 仅防意外损坏，不防篡改。热更新场景下无签名 = 远程代码执行漏洞。建议 Phase 1 即实现 Ed25519 签名。
- **回调重入 fuel 行为**：CALL_HOST 触发回调时，回调中的无限循环如何处理不明确。
- **资源耗尽**：fuel 只限指令数，不限堆内存、文件句柄等。

**VM 宿主优势**：Dart VM 已提供内存安全和类型安全保证，dartic 额外只需关注 CPU 资源保护、栈深度保护和 API 暴露面控制。

---

## 六、业界对标研究

### 6.1 "托管 VM 内解释器" 性能基准

| 项目 | 类型 | 宿主 | 相对原生性能 | 关键瓶颈 |
|------|------|------|-------------|---------|
| MoonSharp | Lua in C# | .NET VM | 纯计算 ~1/10；互调可反超 | GC 分配压力 |
| Jint | JS in C# | .NET VM | ~1/20 vs V8 | 解释器分发开销 |
| Rhino（解释模式） | JS in Java | JVM | ~1/4 vs Nashorn | 字节码分发开销 |
| wasm3 | WASM 解释器 | 原生（C） | 1/3 ~ 1/30 | 分支预测失败 |
| wasmi v0.32 | WASM 解释器 | 原生（Rust） | 旧版栈式快 5x | 平台差异大 |
| dart_eval | Dart in Dart | Dart VM | 1/10 ~ 1/50 | 栈式分发 + 对象分配 |

### 6.2 关键洞察

1. **MoonSharp 经验最具参考价值**：纯计算慢 10x，但互调密集场景可反超原生封装方案 20x。dartic 的 Bridge 设计正是为此优化。

2. **dart_eval 作者明确指出**："most Flutter apps spend the vast majority of their performance budget in the Flutter framework itself, so the speed impact of dart_eval is usually negligible." dartic 在此基础上通过寄存器式字节码+紧凑存储可进一步缩小差距。

3. **iOS 合规性**：Apple 禁止 JIT，字节码解释器是合规的唯一选择。Hermes、Shorebird 均采用此路线。

4. **元循环解释器教训**：PyPy 和 Squeak 表明纯解释的元循环方案极慢，但 dartic 不存在"双层解释"——Dart VM AOT 已将分发循环编译为原生代码。

### 6.3 技术路线对齐度

| 设计决策 | 行业最佳实践 | 对齐度 |
|---------|------------|--------|
| 寄存器式字节码 | wasmi v0.32 证明带来 5x 提升 | 完全对齐 |
| 紧凑指令存储 | Lua/wasm3 均使用紧凑编码 | 完全对齐 |
| 双视图栈避免装箱 | Lua-CSharp 零分配策略 | 完全对齐 |
| 编译期寄存器分配 | 所有高性能解释器标配 | 完全对齐 |
| Bridge 互调设计 | MoonSharp：互调决定整体性能 | 完全对齐 |
| CFE/Kernel 输入 | dartic 独创 | 创新性优势 |
| 预编译字节码下发 | Hermes 模式 | 完全对齐 |

---

## 七、性能预测

### 场景化预测

| 场景 | 预估性能 | 关键瓶颈 | 是否满足需求 |
|------|---------|---------|------------|
| 纯算术/控制流 | 原生 1/3~1/5 | switch 分发 | 远超目标 |
| 混合业务逻辑 | 原生 1/10~1/20 | 方法分发 + 对象操作 | 达标 |
| Flutter Widget build | 原生 1/10~1/30 | Bridge 调用 + 对象创建 | 可接受 |
| 框架交互密集 | 原生 1/20~1/50 | `Function.apply` + Proxy 包装 | 需优化 |

### 性能天花板

| 限制 | 来源 | 可否突破 |
|------|------|---------|
| 无 computed goto | Dart 语言不支持 | **不可突破**，约损失 20-30% |
| switch 分发开销 | 每条指令 ~10-15 条原生指令 | 部分缓解（Superinstruction） |
| typed_data bounds check | Dart AOT 可能无法消除 | 部分缓解 |
| `Function.apply` 慢路径 | Dart AOT 反射式调用 | 可突破（特化 HostClassWrapper） |

---

## 八、与竞品对比

| 维度 | dartic | dart_eval | Shorebird | Hermes (RN) |
|------|--------|-----------|-----------|-------------|
| 语言覆盖 | 完整 Dart（CFE 保障） | 部分 Dart | 完整 Dart | 完整 JS |
| 性能 | ~1/10 原生 | 1/10~1/50 | ~0.98x 原生 | ~0.5-0.7x |
| 互调开销 | 零序列化（同 VM） | 零序列化（同 VM） | 原生 | JSON/JSI |
| iOS 合规 | 合规 | 合规 | 合规 | 合规 |
| 侵入性 | 纯 Dart 包 | 纯 Dart 包 | 修改引擎 | 自定义引擎 |
| 成熟度 | 开发中 | 可用 | 商业化 | 生产级 |

---

## 九、总结

dartic 的设计展现出极高的工程成熟度和技术深度。三大核心优势：

1. **Kernel AST 输入** — 站在 Dart CFE 肩膀上，自动获得完整的类型信息和语法脱糖
2. **双视图值栈** — POC 证明 double 性能达原生 96%，在 Dart 生态中独创
3. **同 VM 零序列化互调** — 比所有跨语言/跨进程方案低 1-2 个数量级

最大不确定性不在解释器本身，而在 Bridge 生成的工程规模。这是工程挑战而非设计缺陷。

**最终判断：方案可行、路线正确、业界通用、性能目标有合理支撑。**
