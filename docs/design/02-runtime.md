# Chapter 3: 执行引擎

## 模块定位

执行引擎驱动字节码的加载与执行，是 dartic 解释器的核心运行时组件。它使用 Ch2 定义的数据结构（三栈模型、DarticObject、DarticFrame）运行分发循环、通过内联缓存加速虚方法调用、并处理异常分发。在架构分层中位于 Ch2（内存模型）之上、Ch4（互调）之下，为上层的异步子系统（Ch7）和安全沙箱（Ch8）提供基础执行能力。

## 与其他模块的关系

| 方向 | 模块 | 接口 |
|------|------|------|
| 输入 | Ch2 内存模型 | 使用三栈模型、DarticObject、DarticFrame 等核心数据结构 |
| 输入 | Ch5 编译器 | 加载编译器产出的 `.darticb` 字节码模块，含字节码、常量池、符号表 |
| 输入 | Ch1 ISA | 分发循环解码并执行 Ch1 定义的 32 位定宽指令 |
| 输出 | Ch4 互调 | 暴露运行时 API（字段读写、方法调用、对象创建）供 Bridge/Proxy 回调解释器 |
| 扩展 | Ch7 异步 | 异步子系统复用分发循环的帧管理机制，扩展 DarticFrame 支持挂起/恢复 |
| 扩展 | Ch8 沙箱 | 沙箱层在模块加载时执行字节码验证，复用运行时的 fuel 计数和调用深度限制 |
| 依赖 | Ch6 泛型 | 栈帧中的 ITA/FTA 槽位为泛型系统提供类型参数传递通道 |

## 设计决策

| 决策项 | 选择 | 备选方案与拒绝理由 | 理由 |
|--------|------|-------------------|------|
| fuel 让出 | `Timer.run`（fuel 耗尽）+ `scheduleMicrotask`（await 恢复） | Isolate：创建/通信开销过高，不适合轻量级让出 | 协作调度不饿死 event queue，详见 Ch7 |
| GC | 完全依赖宿主 Dart VM GC | 自实现 GC：复杂度极高，且 VM 已有成熟 GC | 解释器对象即 VM 堆对象，零额外 GC 开销 |
| 内联缓存 | 单态 IC（每 CALL_VIRTUAL 一个缓存槽） | 无缓存：每次虚调用都查 HashMap，10-50x 性能劣化 | 典型 OO 代码单态命中率 85-95%，一次 int 比较 O(1) |
| IC miss 慢路径 | 小方法表排序数组 + 大方法表 HashMap | 统一 HashMap：小表（≤8 条目）的哈希/桶开销高于线性扫描 | 方法数 ≤ 8 用排序 `List<(int, DarticFuncProto)>` 二分查找，> 8 用 HashMap |
| 异常处理 | 处理器表 + 线性扫描 | 内联异常跳转（setjmp/longjmp 风格）：正常路径需 try 入口/出口指令开销，而 Dart 中异常是慢路径 | 正常路径零开销（无 try 入口/出口指令），异常路径线性扫描 O(n)，n 通常 ≤ 5 |
| Super 解析 | 编译期完全解析 | 运行时沿 superClassId 链查找：每次 super 调用多一次链遍历 | Kernel 的 interfaceTarget 已指向具体方法，编译器直接绑定 DarticFuncProto 索引 |
| 动态分发 IC | 不使用 IC | 复用 CALL_VIRTUAL 的单态 IC：dynamic 调用点类型不稳定，IC 命中率低于 50% | dynamic 调用走 DarticClassInfo 方法表/字段表查找，频率远低于虚调用 |

## 工作流程

### 模块加载

`loadModule` 将编译器产出的 `.darticb` 字节码模块注册到运行时，是执行前的必要步骤。

**加载流程**：

1. **字节码验证**（委托 Ch8 沙箱层）：操作码合法性、操作数范围、WIDE 规则、跳转目标有效性
2. **DarticClassInfo 注册**：遍历模块中的类定义，为每个类创建 DarticClassInfo（构建方法表、字段布局、supertypeIds 传递闭包）并注册到全局类表（DarticClassInfo 结构定义详见 Ch2）
3. **DarticFuncProto 注册**：将模块中的函数原型（含字节码、异常处理器表、IC 表、上值描述符）注册到全局 DarticFuncProto 表
4. **常量池挂载**：将模块的四分区常量池（refs/ints/doubles/names）关联到运行时
5. **全局变量注册**：为静态字段和顶层变量分配 DarticGlobalTable 槽位，初始值设为 `_uninitialized` 哨兵，初始化函数 ID 关联到对应槽位
6. **IC 缓存重置**：若新模块引入的 classId 与已有类冲突（热重载场景），全局重置所有 IC 缓存（`cachedClassId = -1`）

**常量池物化策略**：

- 原始常量（int/double/string）：直接存入对应分区的 typed list，零额外处理
- 复合常量（`InstanceConstant`、`ListConstant` 等）：编译器在常量池 refs 分区序列化为描述符，`LOAD_CONST` 首次加载时按描述符物化为宿主对象并原地替换（后续加载直接取缓存）

**不变式**：`loadModule` 完成后，模块中所有 DarticFuncProto 通过索引可达，所有 DarticClassInfo 通过 classId 可达，但全局变量和复合常量仍处于惰性未初始化状态。

### 全局变量惰性初始化

DarticGlobalTable 存储静态字段和顶层变量。每个槽位初始为 `_uninitialized` 哨兵，附带一个初始化函数 ID（由编译器从 Kernel `Field.initializer` 生成）。

**惰性初始化流程**（`LOAD_GLOBAL` 首次访问时触发）：

1. 读取 `slots[index]`
2. 若值为 `_initializing` 哨兵 → 抛出循环依赖错误
3. 若值为 `_uninitialized` 哨兵：
   a. 标记为 `_initializing`（防循环）
   b. 执行初始化函数（`initializerFuncIds[index]`）
   c. 存储结果，返回
   d. 若初始化失败，重置为 `_uninitialized`
4. 否则直接返回已缓存的值

**Late 变量**：Late 局部变量使用相同的哨兵值机制。编译器为 `late` 变量的读取插入检查——值为哨兵时抛出 `LateInitializationError`。有初始化器的 `late` 变量（`late int x = compute()`）首次读取时执行初始化器并缓存结果。

### 分发循环

运行时公开 API 包括：`loadModule`（详见"模块加载"节）、`execute`（执行模块入口函数）、字段读写与方法调用（供 Bridge/Proxy 使用，详见 Ch4）。

`_runQueue` 是 `Queue<DarticFrame>` 类型的就绪队列，存储当前可执行的帧（DarticFrame 结构详见 Ch2，三栈结构定义详见 Ch2）。帧的进出规则：

- **入队**：`execute()` 启动模块时入队；async 帧 Future 完成后通过 `scheduleMicrotask` 重新入队
- **保留**：同步 CALL/RETURN 不操作 `_runQueue`（嵌套帧通过 CallStack 管理）；fuel 耗尽时帧保留在队列中（浅保存）
- **出队**：AWAIT 挂起时移出（深保存，快照栈数据）；ASYNC_RETURN / HALT 完成时移出

分发循环采用外/内双层循环结构，fuel 计数控制单回合执行量：

```
┌─ _driveInterpreter() ─────────────────────────────────────────┐
│                                                                │
│  fuel = _fuelBudget                                            │
│                                                                │
│  ┌─ 外层循环: while fuel > 0 && _runQueue 非空 ──────────────┐ │
│  │                                                            │ │
│  │  frame = _runQueue.first                                   │ │
│  │                                                            │ │
│  │  ┌─ 内层循环: while fuel-- > 0 ─────────────────────────┐ │ │
│  │  │                                                       │ │ │
│  │  │  取指: instr = code[pc++]                             │ │ │
│  │  │  解码: op = instr & 0xFF                              │ │ │
│  │  │  执行: switch(op)                                     │ │ │
│  │  │    ├─ 算术/逻辑指令 → 值栈操作，继续内循环            │ │ │
│  │  │    ├─ CALL → 保存 PC，push 新帧，break 内循环         │ │ │
│  │  │    ├─ RETURN → pop 帧（或遇哨兵帧退出drive），break  │ │ │
│  │  │    ├─ THROW → 异常分发（查handler/栈展开），break     │ │ │
│  │  │    ├─ AWAIT → 保存帧，移出队列，break 内循环(详见Ch7) │ │ │
│  │  │    ├─ ASYNC_RETURN → 完成Completer，移出队列(详见Ch7) │ │ │
│  │  │    └─ HALT → pop 帧，break 内循环                     │ │ │
│  │  │                                                       │ │ │
│  │  └───────────────────────────────────────────────────────┘ │ │
│  │                                                            │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                │
│  _runQueue 非空? → Timer.run(_driveInterpreter)  // 下一回合   │
│  _runQueue 空?   → _driving = false              // 停止       │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

**帧切换**：`CALL` 保存当前 PC 后 `break` 内循环，外层循环从 `_runQueue.first` 取新帧继续。`RETURN` 弹出当前帧，恢复调用者的栈指针和返回值寄存器后 `break` 内循环。若 `RETURN` 检测到 CallStack 栈顶为 HOST_BOUNDARY 哨兵帧（详见 Ch2），则不恢复调用者——而是退出 `drive()`，将控制权和返回值交还给 `invokeClosure` 的调用方（详见 Ch4）。

**返回值传递**：`resultReg` 记录调用者期望接收返回值的寄存器编号。返回值写入值栈还是引用栈由返回指令类型决定——`RETURN_VAL` 写调用者值栈的 `resultReg` 位置，`RETURN_REF` 写调用者引用栈的 `resultReg` 位置。两条指令共用同一个 `resultReg` 字段，因为同一次调用只会执行一条返回指令。

**fuel 计量范围**：fuel 只计量解释器字节码指令，不计量 `CALL_HOST` 调用的宿主函数执行时间。整条 `CALL_HOST`（含宿主函数执行）消耗 1 fuel。耗时较长的宿主操作（如 IO）可能导致某回合超过 10ms 目标，但宿主函数是受信任代码，此限制可接受。

**fuel 共享不变式**：当 VM 通过 DarticCallbackProxy 回调解释器时（详见 Ch4），`invokeClosure` 内部调用 `drive()` 与外层分发循环**共享同一回合的 fuel 预算**，不分配独立预算。这保证了回调中的无限循环同样受 fuel 保护，不会饿死宿主事件循环。

**优化要点**：(1) opcode 解码内联——`instr & 0xFF`、`(instr >> 8) & 0xFF` 等位运算在 switch case 内直接展开，Dart AOT 编译为单条机器指令；(2) switch 密度——所有 256 个 case 值填满，确保 AOT 生成跳转表而非二分查找；(3) 内循环零分配——值栈操作全部是 typed list 索引赋值，零 GC 压力；(4) 帧切换最小化——通过 break innerLoop + 外层重取帧实现，无需额外函数调用。

### 异常分发

每个 DarticFuncProto 关联一个异常处理器表（编译期由 Ch5 生成）。当 `THROW` / `RETHROW` 指令执行时，运行时负责处理器查找、栈展开和控制转移。

**异常处理器表**

每个 DarticFuncProto 的 `exceptionTable` 为 `List<ExceptionHandler>`，按 `(startPC, endPC)` 范围从小到大排序（内层 try 优先）：

| 字段 | 类型 | 说明 |
|------|------|------|
| startPC | int | try 块起始 PC（含） |
| endPC | int | try 块结束 PC（不含） |
| handlerPC | int | catch/finally 处理器入口 PC |
| catchType | int | 常量池中的类型索引（-1 = catch-all / finally） |
| valStackDP | int | 进入 try 时的值栈深度（异常时回退目标） |
| refStackDP | int | 进入 try 时的引用栈深度（异常时回退目标） |
| exceptionReg | int | catch 子句中 exception 变量的引用栈寄存器 |
| stackTraceReg | int | catch 子句中 stackTrace 变量的引用栈寄存器（-1 = 无 stackTrace 绑定） |

**THROW / RETHROW 分发流程**：

1. `THROW A`：取 `exception = refStack[A]`，创建当前 stackTrace
2. `RETHROW A, B`：取 `exception = refStack[A]`，`stackTrace = refStack[B]`（保留原始调用栈）
3. 进入处理器匹配算法

**处理器匹配算法**（从当前帧开始，逐帧向外搜索）：

```
for each frame in call stack (current → bottom):
  for each handler in frame.funcProto.exceptionTable:
    if handler.startPC <= currentPC < handler.endPC:
      if handler.catchType == -1:
        → 匹配（catch-all / finally）
      if exception is handler.catchType:
        → 匹配
  // 当前帧无匹配 → 弹出帧，继续搜索调用者帧
```

**栈展开（匹配成功后）**：

1. 弹出 CallStack 中从当前帧到目标帧之间的所有中间帧
2. 将引用栈中 `[handler.refStackDP, currentRSP)` 范围内的槽位逐一置 null（GC 安全，防止过期引用延长对象生命周期）
3. 将 ValueStack.sp 回退到 `handler.valStackDP`
4. 将 RefStack.sp 回退到 `handler.refStackDP`
5. 将 exception 存入 `refStack[handler.exceptionReg]`；若 `handler.stackTraceReg != -1`，将 stackTrace 存入 `refStack[handler.stackTraceReg]`
6. 设置 PC = `handler.handlerPC`，`break innerLoop` 恢复分发循环

**finally 块处理**：编译器为 finally 块在正常路径和异常路径各生成一份代码（Ch5）。异常路径的 finally 表现为 `catchType = -1` 的处理器，handler 代码末尾执行 `RETHROW` 继续传播异常（除非 finally 块内部有 return 覆盖）。

**边界情况**：

| 情况 | 行为 |
|------|------|
| 同步调用链耗尽（无匹配 handler） | 异常传播到 `drive()` 顶层 try-catch，按"错误恢复"节的 DarticError 路径处理 |
| HOST_BOUNDARY 哨兵帧 | 停止搜索，退出当前 `drive()` 调用，将异常作为 Dart 异常抛出给触发回调的 VM 代码（HOST_BOUNDARY 定义详见 Ch2） |
| async 帧 | 未捕获的异常路由到 `completer.completeError(exception, stackTrace)`，帧从 `_runQueue` 移除（详见 Ch7） |
| 嵌套 try | 处理器表按范围排序保证内层优先匹配；内层 catch 未匹配时继续搜索外层 |

**不变式**：栈展开过程中引用栈的逐槽置 null 不可省略——省略会导致被跳过的临时对象无法被 GC 回收，造成内存泄漏。

### 内联缓存 (IC) 分发

每个 `CALL_VIRTUAL` 指令关联一个 IC 槽，存储最近一次成功匹配的 classId 和方法偏移。

**IC 分发流程**：

1. 从 `CALL_VIRTUAL` 指令的 C 操作数取 IC 槽索引
2. **单态命中**：`ic.cachedClassId == receiver.classId` → 直接调用缓存的方法偏移（一次 int 比较，O(1)）
3. **未命中**（慢路径）：查虚方法表（classId → DarticClassInfo → MethodTable 查找）→ 更新 IC 缓存 → 调用

命中率：典型面向对象代码约 85-95%。命中 vs 未命中性能差约 10-50x。

**IC 失效**：`loadModule` 加载新模块时，若出现 classId 冲突（同名类的新版本），需全局重置所有 IC 缓存（`cachedClassId = -1`）。`loadModule` 是低频操作，全局重置的开销可接受。正常运行中（无新模块加载）IC 无需失效——新 classId 的首次调用只是不命中，走慢路径后自动更新缓存。

> 多态 IC 演进方向详见"已知局限与演进路径"。

### 类型检查（is / as）

`INSTANCEOF` 和 `CAST` 指令的运行时行为按接收者类型分两条路径：

**解释器对象路径**（接收者为 DarticObject）：

1. 取 `receiver.classId`，查找对应的 DarticClassInfo（DarticClassInfo 结构定义详见 Ch2）
2. 检查目标类型的 classId 是否在 `DarticClassInfo.supertypeIds` 集合中（O(1) 哈希查找）
3. 若目标类型包含泛型参数（如 `List<int>`），委托 Ch6 的子类型检查算法做参数化类型匹配

**宿主对象路径**（接收者为宿主 VM 原生对象或 Bridge 实例）：

直接委托 Dart VM 的 `is` 运算符。Bridge 实例继承自宿主类，VM 的类型检查天然正确。基本类型（`int`、`double`、`bool`、`String`）使用 VM 原生的 `is`。

**CAST 指令**：复用 INSTANCEOF 的检查逻辑，检查失败时抛出 `TypeError`，进入异常分发流程。

**supertypeIds 构建**：`loadModule` 注册 DarticClassInfo 时，从当前类出发，沿 `superClassId` 链和接口实现列表递归收集所有超类型 classId，存入 `supertypeIds` 集合。此集合在加载时一次性构建，运行时只读。

### 动态分发

`GET_FIELD_DYN` / `SET_FIELD_DYN` / `INVOKE_DYN` 处理编译期无法确定接收者类型的属性访问（`dynamic` 类型变量）：

**分发流程**：

1. 检查接收者类型：
   - DarticObject → 通过 `classId` 查找 DarticClassInfo，在 `fields` 或 `methods` 中按名称索引查找
   - 宿主对象 → 委托给 HostClassWrapper 路由（详见 Ch4）
2. 查找失败时 → 查找接收者类的 `noSuchMethod` 方法并调用，传入 `Invocation` 描述对象

动态分发不使用 IC 缓存——`dynamic` 调用点类型不稳定，单态 IC 的命中率低，缓存维护开销大于收益。

### Super 方法解析

`CALL_SUPER A, Bx` 的方法目标在编译期完全解析。Bx 直接索引 DarticFuncProto 表中的具体方法——编译器在编译 `SuperMethodInvocation` / `SuperPropertyGet` / `SuperPropertySet` 时，已通过 Kernel 的 `interfaceTarget` 确定目标方法并分配 DarticFuncProto 索引。运行时执行 `CALL_SUPER` 时无需遍历 `superClassId` 链查找，直接按 Bx 调用目标函数。

### GC 集成

解释器不实现自己的 GC。所有对象（DarticObject、Bridge 实例、闭包）都是宿主 Dart VM 堆对象，由 VM GC 管理。关键的 GC 协作点：

- **引用栈弹出置 null**：确保弹出的对象可被 GC 回收
- **上值关闭**：`CLOSE_UPVALUE` 将值从栈复制到上值对象内部后，栈槽置 null（Upvalue 结构详见 Ch2）
- **帧销毁**：帧从 `_runQueue` 移除后，帧对象及其引用可被 GC 回收（除非被挂起的 async 帧持有，详见 Ch7）
- **异常处理栈清理**：栈展开回退到 `(valStackDP, refStackDP)` 时，引用栈中被跳过的槽位 `[refStackDP, currentRSP)` 必须逐一置 null，防止过期引用延长对象生命周期

### 错误恢复

用户代码的 `try`-`catch` 由"异常分发"机制在分发循环内部处理。当异常穿透所有用户代码 handler 后，`drive()` 的顶层 try-catch 作为最终防线，区分两类错误并采取不同恢复策略：

**DarticError**（预期错误：栈溢出、类型检查失败、未捕获的用户异常等）：
1. 清理当前帧的栈空间（弹出值栈/引用栈至帧入口基址，弹出 CallStack 帧）
2. 从 `_runQueue` 移除当前帧
3. 若帧关联 Completer（async 函数），调用 `completer.completeError(error)`
4. 继续执行 `_runQueue` 中的其他帧——运行时实例仍可用

**非 DarticError**（内部错误：Dart RangeError、StateError 等意外异常）：
1. 清空 `_runQueue`，重置所有栈指针至初始状态
2. 将运行时标记为 `_faulted = true`
3. 后续调用 `execute()` 立即抛出 `DarticInternalError('Runtime is in faulted state')`

**不变式**：`DarticError` 后运行时可继续使用；`DarticInternalError` 后运行时实例应被丢弃并重新创建。

## 关键约束与边界条件

| 约束项 | 值 | 来源 |
|--------|-----|------|
| fuel 预算 | 50,000 指令/回合 | ~200us `Timer.run` 调度开销 + ~10ms 目标回合时间（保持 UI 60fps 流畅）。注意：实测可能仅需 1-3ms（平均 ~30ns/指令），可根据 profiling 上调至 100,000-200,000 |
| 最大调用深度 | 512 帧 | 满足正常递归深度（Dart 常规代码极少超过 100 层），同时防止栈溢出消耗过多内存。HOST_BOUNDARY 哨兵帧计入此限制，交替调用（解释器↔VM）每层消耗约 3-5 个 VM 帧，512 层约占 ~512KB VM 栈空间（默认 1MB） |
| ExceptionHandler 条目大小 | 8 个 int | startPC + endPC + handlerPC + catchType + valStackDP + refStackDP + exceptionReg + stackTraceReg |
| 异常处理器表大小 | 每函数无硬上限 | 按 (startPC, endPC) 排序保证内层优先匹配；实际嵌套深度通常 ≤ 5 |

## 已知局限与演进路径

> **Phase 2**：运行时 Quickening。触发条件：profiling 显示编译器静态类型特化覆盖不足（当前编译器已根据 CFE 静态类型信息生成特化指令如 `ADD_INT`、`ADD_DBL`）。

> **Phase 2**：多态 IC（2-4 条目）和超态回退（megamorphic 全局查找）。触发条件：profiling 显示 IC miss 路径时间占比 > 15%。Flutter Widget tree 的多态调用点（多种 Widget 子类）可能较早触发此需求。

> **Phase 2**：同步 CALL 快速路径。当前所有 CALL 均通过 `break innerLoop` + 外层重取帧实现。可为同步调用提供就地切换帧状态的快速路径（直接更新 `code`/`pc`/`sp` 局部变量，`continue innerLoop`），仅 RETURN/AWAIT/fuel 耗尽时 break。触发条件：benchmark 显示函数调用密集代码的帧切换开销 > 3%。

> **Phase 2**：fuel 预算自适应调整。首次运行时测量平均指令执行时间，动态计算 fuel 预算以稳定命中 10ms 目标回合时间。

## 附录：参考实现

<details>
<summary>异常分发实现</summary>

```dart
void _dispatchException(Object exception, StackTrace stackTrace) {
  while (_callStack.fp > 0) {
    final funcProto = _currentDarticFuncProto;
    final pc = _currentPC;

    for (final handler in funcProto.exceptionTable) {
      if (pc >= handler.startPC && pc < handler.endPC) {
        if (handler.catchType == -1 ||
            _isInstanceOf(exception, handler.catchType)) {
          // 栈展开：引用栈置 null
          for (var i = handler.refStackDP; i < _refStack.sp; i++) {
            _refStack.slots[i] = null;
          }
          _valueStack.sp = handler.valStackDP;
          _refStack.sp = handler.refStackDP;

          // 绑定 catch 变量
          _refStack.slots[handler.exceptionReg] = exception;
          if (handler.stackTraceReg != -1) {
            _refStack.slots[handler.stackTraceReg] = stackTrace;
          }

          _currentPC = handler.handlerPC;
          return; // 回到分发循环继续执行
        }
      }
    }

    // 当前帧无匹配 handler
    if (_isHostBoundary()) {
      _popFrame();
      throw exception; // 抛给 VM 调用方
    }
    _popFrame();
  }

  // 所有帧耗尽，异常未被捕获
  throw exception;
}
```

</details>

<details>
<summary>闭包构建实现</summary>

```dart
DarticClosure _buildClosure(DarticFuncProto proto) {
  final descriptors = proto.upvalueDescriptors;
  final upvalues = List<Upvalue>.generate(descriptors.length, (i) {
    final desc = descriptors[i];
    if (desc.isLocal) {
      // 从当前帧的引用栈槽位创建或复用 Upvalue
      final stackIndex = _refStack.baseForCurrentFrame + desc.index;
      return _openUpvalues.putIfAbsent(
        stackIndex,
        () => Upvalue(stackIndex: stackIndex),
      );
    } else {
      // 从当前闭包的上值表传递
      return _currentUpvalues[desc.index];
    }
  });
  return DarticClosure(funcProto: proto, upvalues: upvalues);
}
```

</details>

<details>
<summary>DarticGlobalTable 惰性初始化实现</summary>

```dart
Object? load(int index, DarticRuntime runtime) {
  final value = slots[index];
  if (identical(value, _initializing)) {
    throw DarticError('Circular dependency: global variable $index');
  }
  if (identical(value, _uninitialized)) {
    final initId = initializerFuncIds[index];
    if (initId == -1) throw LateInitializationError('Global $index');
    slots[index] = _initializing;
    try {
      final result = runtime._executeInitializer(initId);
      slots[index] = result;
      return result;
    } catch (e) {
      slots[index] = _uninitialized;
      rethrow;
    }
  }
  return value;
}
```

</details>
