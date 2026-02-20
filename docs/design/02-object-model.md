# Chapter 2: 内存模型与对象表示

## 模块定位

本章定义 dartic 解释器的所有核心数据结构——三栈内存模型（ValueStack/RefStack/CallStack）、统一对象表示（DarticObject）、类元数据（DarticClassInfo）、函数原型（DarticFuncProto）、闭包与上值、以及执行帧（DarticFrame）。这是一个纯"静态"视角：描述这些结构在内存中长什么样、包含哪些字段，不涉及它们如何被驱动执行。Ch3-Ch8 均引用本章定义的数据结构作为运行基础。

## 与其他模块的关系

| 方向 | 模块 | 接口 |
|------|------|------|
| 被消费 | Ch3 执行引擎 | 使用三栈模型、DarticObject、DarticFuncProto、DarticFrame 驱动分发循环和帧管理 |
| 被消费 | Ch4 互调 | 使用 DarticObject 作为 Bridge/Proxy 的内部表示 |
| 被消费 | Ch5 编译器 | 编译器以本章数据结构为目标生成字节码（栈帧布局、字段偏移等） |
| 被消费 | Ch6 泛型 | DarticType 存储在 DarticObject.runtimeType 中，承载具体化的泛型类型参数 |
| 被消费 | Ch7 异步 | DarticFrame 的挂起/恢复字段支持异步帧快照与恢复 |
| 输入 | Ch1 字节码 ISA | 指令编码格式决定栈帧布局（操作数宽度、寄存器编号方式） |

## 设计决策

| 决策项 | 选择 | 备选方案与拒绝理由 | 理由 |
|--------|------|-------------------|------|
| 值栈 | 共享 ByteBuffer 双视图（Int64List + Float64List） | 独立 int/double 栈：两套栈指针管理复杂，帧快照/恢复需处理双倍数据 | int 保留 64 位精度 + double 零装箱，单缓冲区对缓存友好 |
| 引用栈 | 独立 `List<Object?>` | 混入值栈：typed list 无法持有 Object 引用，VM GC 无法追踪 | 参与宿主 GC 追踪，弹出置 null 确保及时回收 |
| 对象模型 | 统一 DarticObject | 按类型生成不同宿主类：类数量爆炸，无法支持动态加载 | 单一表示简化实现；extends 宿主类时走 Bridge 路径（详见 Ch4） |
| valueFields | 非空 `Int64List` + 空单例共享 | 可空 `Int64List?`：每次访问多一次空检查；热路径累积可测量开销 | 无值字段时共享全局 `Int64List(0)` 空单例，消除空检查，额外内存仅一个对象 |
| 闭包表示 | 独立 DarticClosure | 复用 DarticObject：需分配 classId、方法表等冗余结构，闭包无字段/继承语义 | 轻量结构（仅 DarticFuncProto + upvalues），闭包不是对象，不参与虚调用 |

## 核心概念

### StackKind 分类

编译器为每个变量和临时值分配一个 StackKind 标记，决定该值存放在值栈还是引用栈：

| StackKind | index | 存放位置 | 对应 Dart 类型 |
|-----------|-------|---------|---------------|
| `ref` | 0 | RefStack | String、对象实例、闭包、null、dynamic、num 等引用类型（默认/fallback） |
| `boolVal` | 1 | ValueStack（intView） | bool（编码为 0/1） |
| `intVal` | 2 | ValueStack（intView） | int |
| `doubleVal` | 3 | ValueStack（doubleView） | double |

**关键规则**：`dynamic` 和 `num` 类型的变量始终走引用栈（装箱路径），因为编译器无法在编译期确定其具体类型。被上值捕获的原始类型（int/double/bool）也强制标记为 `ref`，因为上值的间接访问机制仅支持引用栈（详见"上值对象"节）。

StackKind 贯穿多个数据结构：ValueStack 的双视图不变式依赖它保证同一槽位只通过一种视图访问；FieldLayout 的 `kind` 字段使用它区分值字段和引用字段。

### 三栈内存模型

运行时使用三个独立的栈结构管理执行状态。Ch1 字节码 ISA 定义了值栈和引用栈的操作指令（双栈操作数模型），本章在此基础上增加 CallStack 构成完整的三栈模型：

**ValueStack**（双视图值栈）

底层为一块 `Uint8List` 缓冲区，上面叠加两个视图共享同一内存：

| 属性 | 类型 | 说明 |
|------|------|------|
| intView | Int64List | 整数视图，每槽 8 字节 |
| doubleView | Float64List | 浮点视图，与 intView 共享同一缓冲区 |
| sp | int | 栈顶指针（槽位单位） |

**不变式**：同一槽位在其活跃区间内只通过一种视图访问。编译器的 StackKind 分类保证此约束（详见上节"StackKind 分类"）。

**RefStack**（引用栈）

| 属性 | 类型 | 说明 |
|------|------|------|
| slots | List\<Object?\> | 引用类型存储，参与宿主 VM GC 追踪 |
| sp | int | 栈顶指针（槽位单位） |

**不变式**：弹出时必须将槽位置 null（`slots[sp] = null`），防止 GC 过期引用导致内存泄漏。

**CallStack**（调用栈）

| 属性 | 类型 | 说明 |
|------|------|------|
| data | Uint32List | 帧元数据存储，每帧 6 个 uint32 槽位 |
| fp | int | 帧指针（指向当前帧基址） |

CallStack 存储同步调用链的帧元数据。每帧的 6 个字段含义见下方"栈帧布局"节。

**不变式**：`savedVSP`/`savedRSP` 用于同步调用链的帧切换（保存调用者的值栈/引用栈指针）。异步挂起时栈指针额外保存到 DarticFrame 堆对象（详见"执行帧 -- DarticFrame"节及 Ch7），因为挂起帧脱离了 CallStack 的线性调用链。

**HOST_BOUNDARY 哨兵帧**：当 VM 通过 DarticCallbackProxy 或 BridgeMixin 回调解释器时（详见 Ch4），`invokeClosure` 在 CallStack 上压入一个哨兵帧（`funcId = SENTINEL_HOST_BOUNDARY`），标记回调的入口边界。RETURN 指令检测到哨兵帧时不再弹栈回退到调用者，而是退出当前 `drive()` 调用，将控制权交还给触发回调的 VM 代码。这保证了：(1) 回调的 RETURN 不会意外弹到外层解释器帧；(2) 回调结束后三栈的栈指针恢复到回调入口前的状态；(3) 外层帧的栈数据不受回调影响。

**栈预分配与溢出保护**

三栈均在运行时初始化时预分配固定容量：

| 栈 | 预分配大小 | 估算依据 |
|----|-----------|---------|
| ValueStack | 10,240 槽（80 KB） | maxCallDepth(512) x 平均 20 值栈槽/帧 |
| RefStack | 5,120 槽（~40 KB） | maxCallDepth(512) x 平均 10 引用栈槽/帧 |
| CallStack | 3,072 uint32（12 KB） | maxCallDepth(512) x 6 uint32/帧 |

**溢出检测**：`CALL` 指令在压入新帧前检查三栈剩余容量（`vs.sp + funcProto.valueRegCount > vs.capacity`），不足时抛出 `DarticError('Stack overflow')`。不依赖 Dart typed list 的 `RangeError`——`RangeError` 不属于 `DarticError` 体系，宿主应用若只 catch `DarticError` 会遗漏栈溢出。此处 `funcProto.valueRegCount` 和 `funcProto.refRegCount` 是 DarticFuncProto 中编译器预计算的帧空间需求（详见下方"函数原型"节）。

### 对象模型

**DarticObject**（统一内部表示）

所有解释器定义的类实例统一使用 DarticObject：

| 属性 | 类型 | 说明 |
|------|------|------|
| classId | int | 类标识，用于虚方法表查找和 IC 命中检查 |
| runtimeType | DarticType | 含具体化的泛型类型参数（详见 Ch6） |
| refFields | List\<Object?\> | 引用类型字段存储（无引用字段时共享全局空 List 单例） |
| valueFields | Int64List | int/double/bool 字段存储（无值字段时共享全局 `Int64List(0)` 空单例） |

字段访问通过编译期确定的偏移索引，`GET_FIELD_REF r, obj, 2` 读取 `obj.refFields[2]`，O(1)。

**构造函数执行**：`NEW_INSTANCE classId` 分配 DarticObject（根据 DarticClassInfo 的 `refFieldCount`/`valueFieldCount` 初始化字段存储），结果入引用栈。随后编译器生成的 `CALL` 指令调用构造函数体，与普通方法调用共用相同的帧管理机制。

编译器在编译阶段将 Dart 的初始化器链（字段初始化器 -> super 构造函数 -> 构造函数体）展平为单一函数体（DarticFuncProto）。运行时无需感知初始化器的分步语义——构造函数在运行时就是一次普通的 `CALL`，由编译器产出的字节码序列保证执行顺序。重定向构造函数（`this(...)`）编译为对目标构造函数的 `CALL`。

**基本类型与集合的运行时表示**：`int`/`double`/`bool`/`String` 直接使用宿主 Dart VM 原生类型，不包装为 DarticObject。`CREATE_LIST`/`CREATE_MAP`/`CREATE_SET` 指令创建的也是宿主 VM 原生集合对象（`List`/`Map`/`Set`），直接存入引用栈。集合元素访问（索引、迭代等）通过 `CALL_HOST` 路由到 HostClassWrapper（详见 Ch4）。

**Bridge 实例**：解释器类继承或实现宿主 VM 类型时（如 `extends StatelessWidget`），必须使用 Bridge 实例。Bridge 内部持有 DarticObject 的引用，委托方法调用给解释器运行时。详见 Ch4。

**跨边界传递**：非 Bridge 的 DarticObject 跨越解释器-VM 边界时，通过 Expando 缓存按需包装为 DarticProxy。详见 Ch4。

### 类元数据

每个解释器类通过 DarticClassInfo 维护方法表和字段布局：

**DarticClassInfo**

| 属性 | 类型 | 说明 |
|------|------|------|
| classId | int | 类唯一标识 |
| name | String | 类名 |
| superClassId | int | 父类 ID |
| refFieldCount | int | 引用类型字段数量 |
| valueFieldCount | int | 值类型字段数量 |
| typeParamCount | int | 类型参数数量（如 `List<T>` -> 1, `Map<K,V>` -> 2, 非泛型 -> 0） |
| methods | MethodTable | 方法名索引 -> DarticFuncProto 的映射（详见下方"MethodTable"） |
| fields | Map\<int, FieldLayout\> | 字段名索引 -> 字段布局 |
| supertypeIds | Set\<int\> | 所有超类型 classId（父类链 + 接口实现的传递闭包），用于 `INSTANCEOF` O(1) 检查 |

**MethodTable**

MethodTable 根据方法数量采用两种内部实现（阈值策略，详见 Ch3 设计决策"IC miss 慢路径"）：

| 方法数 | 内部结构 | 查找复杂度 |
|--------|---------|-----------|
| <= 8 | 排序 `List<(int, DarticFuncProto)>`（按方法名索引排序） | 二分查找 O(log n) |
| > 8 | `Map<int, DarticFuncProto>` | 哈希查找 O(1) |

`CALL_VIRTUAL` 通过 `classId` 查找 DarticClassInfo，再通过 MethodTable 的方法名索引查找 DarticFuncProto。IC 缓存将这个两步查找优化为 O(1)（IC 分发流程详见 Ch3）。

**FieldLayout**

| 属性 | 类型 | 说明 |
|------|------|------|
| offset | int | 字段在 refFields 或 valueFields 中的偏移 |
| kind | StackKind | `boolVal`/`intVal`/`doubleVal`（值栈类型）或 `ref`（引用栈类型） |

### 函数原型

DarticFuncProto 是编译器的核心产出，封装一个函数的全部编译期元数据。多个执行帧（DarticFrame）或闭包（DarticClosure）可以共享同一个 DarticFuncProto 实例。

**DarticFuncProto**

| 属性 | 类型 | 说明 |
|------|------|------|
| funcId | int | 函数唯一标识，用于 CallStack 帧记录和全局函数表索引 |
| bytecode | Uint32List | 32 位定宽指令序列（编码格式详见 Ch1） |
| valueRegCount | int | 值栈帧空间需求（编译器寄存器分配的输出，含参数+局部变量+临时值） |
| refRegCount | int | 引用栈帧空间需求（同上） |
| paramCount | int | 参数数量 |
| icTable | List\<ICEntry\> | 内联缓存表，每个 `CALL_VIRTUAL` 指令关联一个槽位（IC 结构详见 Ch1，分发流程详见 Ch3） |
| exceptionTable | List\<ExceptionHandler\> | 异常处理器表，按 `(startPC, endPC)` 范围排序（匹配算法详见 Ch3） |
| upvalueDescriptors | List\<UpvalueDescriptor\> | 上值描述符列表，`CLOSURE` 指令据此构建闭包的上值表（详见"闭包对象"节） |

> `valueRegCount` 和 `refRegCount` 由编译器在寄存器分配阶段确定（详见 Ch5）。`CALL` 指令压帧时直接将值栈和引用栈的 sp 分别推进 `valueRegCount` 和 `refRegCount` 个槽位，完成帧空间预留。

**UpvalueDescriptor**

| 属性 | 类型 | 说明 |
|------|------|------|
| isLocal | bool | true = 从直接外层帧的引用栈槽位捕获；false = 从外层闭包的上值表传递 |
| index | int | `isLocal` 时为引用栈槽位相对偏移；否则为外层闭包 upvalues 列表的索引 |

### 上值对象

闭包捕获外层作用域的变量通过上值（Upvalue）对象实现。每个上值有开放和关闭两种状态：

**Upvalue**

| 属性 | 类型 | 说明 |
|------|------|------|
| stackIndex | int | 开放状态时指向引用栈的槽位偏移（关闭后无效） |
| value | Object? | 关闭状态时持有的值（开放时为 null） |
| isOpen | bool | 是否仍指向栈槽 |

**开放上值**：变量仍在栈上活跃时，`LOAD_UPVALUE` / `STORE_UPVALUE` 通过 `stackIndex` 间接访问引用栈槽位。同一栈槽位可被多个闭包共享同一个 Upvalue 对象。

**关闭上值**：变量所在作用域结束时，`CLOSE_UPVALUE` 将引用栈 `slots[stackIndex]` 的值复制到 `value` 字段，设 `isOpen = false`，原栈槽置 null 助 GC。此后 `LOAD_UPVALUE` / `STORE_UPVALUE` 直接读写 `value` 字段。

**不变式**：被捕获的原始类型（int/double/bool）强制走引用栈的装箱路径（编译器 StackKind 标记为 `ref`），因为上值的间接访问机制仅支持引用栈。详见 Ch5。

### 闭包对象

闭包是运行时中除 DarticObject 外的另一种核心实体，表示携带捕获环境的函数引用。

**DarticClosure**

| 属性 | 类型 | 说明 |
|------|------|------|
| funcProto | DarticFuncProto | 闭包体的字节码函数原型 |
| upvalues | List\<Upvalue\> | 捕获的上值列表（无捕获时为空列表） |

`CLOSURE A, Bx` 指令根据 `funcProto[Bx]` 的 `upvalueDescriptors` 列表构建闭包：

1. 遍历 DarticFuncProto 的上值描述符列表（`upvalueDescriptors`）
2. 对每个描述符：
   - `isLocal = true`：从当前帧的引用栈槽位创建或复用 Upvalue（同一槽位共享同一 Upvalue 对象）
   - `isLocal = false`：从当前闭包的上值表中传递已有 Upvalue
3. 将 DarticFuncProto + 收集的上值列表打包为 DarticClosure，存入 `refStack[A]`

**调用路径**：`CALL` 指令检测 `refStack[B]` 的类型——若为 DarticClosure，从中提取 `funcProto` 和 `upvalues`，将 upvalues 关联到新帧，按正常流程压帧执行。

**Tear-off 表示**：静态 tear-off（`StaticTearOff`）、构造函数 tear-off（`ConstructorTearOff`）等在编译期已解析为具体的 DarticFuncProto 引用，运行时表示为无上值的 DarticClosure（`upvalues` 为空列表）。实例方法 tear-off（`InstanceTearOff`）需额外捕获 receiver 作为第一个上值。

**不变式**：DarticClosure 不是 DarticObject——它没有 classId、runtimeType 等属性。当闭包需要作为 `Function` 类型传递给宿主 VM 时，通过 DarticCallbackProxy 包装（详见 Ch4）。

### 执行帧 -- DarticFrame

DarticFrame 是分发循环操作的基本调度单位，封装一次函数调用的完整执行状态。它是堆对象，在 `execute()` 创建顶层帧和异步恢复时创建。

> **术语辨析**：DarticFrame 堆对象上的 `savedVSP` / `savedRSP` / `savedVBase` / `savedRBase` 用于异步挂起时的**深保存**（快照栈数据到堆）。它们与 CallStack 中同名的 `savedVSP` / `savedRSP` 不同——后者用于同步调用链的帧切换（保存调用者的栈指针），存储在 `Uint32List` 中，随 CALL/RETURN 自动管理。

**基础与栈快照字段**

| 字段名 | 类型 | 用途 |
|--------|------|------|
| funcProto | DarticFuncProto | 当前函数原型（含 bytecode、icTable、exceptionTable 等） |
| pc | int | 程序计数器，挂起时保存恢复点 |
| upvalues | List\<Upvalue\> | 当前帧关联的上值表（闭包调用时从 DarticClosure 传入，非闭包调用时为空列表） |
| savedVBase | int | 挂起时值栈帧基址 |
| savedRBase | int | 挂起时引用栈帧基址 |
| savedVSP | int | 挂起时的值栈指针 |
| savedRSP | int | 挂起时的引用栈指针 |
| savedValueSlots | Int64List? | 值栈快照（帧占用区间），恢复后置 null |
| savedRefSlots | List\<Object?\>? | 引用栈快照（帧占用区间），恢复后置 null |

> 帧通过 `funcProto` 引用访问字节码（`funcProto.bytecode`）、内联缓存表（`funcProto.icTable`）和异常处理器表（`funcProto.exceptionTable`）。这些数据属于函数元数据，多个帧执行同一函数时共享同一份。异常处理器表为 `List<ExceptionHandler>`，按 PC 范围匹配（详见 Ch3 异常分发节），DarticFrame 不单独持有副本。

**异步与生成器控制字段**

| 字段名 | 类型 | 用途 |
|--------|------|------|
| resultCompleter | Completer\<Object?\>? | async 函数的结果 Completer |
| thenCallback | Function? | 惰性创建的 then 回调，避免每次 await 分配 |
| errorCallback | Function? | 惰性创建的 error 回调 |
| streamController | StreamController\<Object?\>? | async* 的输出 Stream |
| streamPaused | bool | Stream 是否被暂停 |
| isSuspendedAtYield | bool | 是否因 Stream 暂停而在 yield 点挂起 |
| cancelled | bool | 订阅是否已取消 |

**挂起恢复字段**

| 字段名 | 类型 | 用途 |
|--------|------|------|
| awaitDestReg | int | AWAIT 指令的目标寄存器 A（恢复时写入结果） |
| resumeValue | Object? | Future 正常完成的恢复值 |
| resumeException | Object? | Future 异常完成的异常对象 |
| resumeStackTrace | StackTrace? | 异常对应的栈追踪 |
| capturedZone | Zone | 帧创建时捕获的 Zone.current |
| awaiterFrame | DarticFrame? | 等待此帧结果的帧（异步栈追踪用） |

**不变式**：DarticFrame 是堆对象（非栈上结构），`_runQueue` 持有引用。同步嵌套调用不创建新 DarticFrame——通过 CallStack 的帧元数据管理；DarticFrame 仅在顶层入口（`execute()`）和异步恢复时创建。

### 栈帧布局

每个函数调用占用三部分空间：

```
值栈 (ValueStack)                 引用栈 (RefStack)
┌────────────────────┐           ┌────────────────────┐
│ [调用者帧]         │           │ [调用者帧]         │
├────────────────────┤           ├────────────────────┤
│ int/double 参数    │           │ ITA (类类型参数)   │ <- rsp+0 (所有帧均预留，非泛型时为 null)
│ int/double 局部变量 │           │ FTA (方法类型参数) │ <- rsp+1 (所有帧均预留，非泛型时为 null)
│ int/double 临时值  │           │ this / receiver    │ <- rsp+2
├────────────────────┤ <- vsp    │ ref 参数           │
│ (空闲)             │           │ ref 局部变量       │
└────────────────────┘           │ ref 临时值         │
                                 ├────────────────────┤ <- rsp
                                 │ (空闲)             │
                                 └────────────────────┘

调用栈 (CallStack)
┌──────────────────────────────────┐
│ funcId      │ 当前函数 ID (DarticFuncProto.funcId) │
│ returnPC    │ 调用者的 PC        │
│ savedFP     │ 调用者的帧指针     │
│ savedVSP    │ 调用者的值栈指针   │
│ savedRSP    │ 调用者的引用栈指针 │
│ resultReg   │ 调用者的返回值寄存器│
├──────────────────────────────────┤ <- fp
│ (下一帧)                         │
└──────────────────────────────────┘
```

**funcId 与 DarticFuncProto 的关系**：CallStack 中的 `funcId` 是 DarticFuncProto 在全局函数表中的索引，可通过 `funcId` 查找对应的 DarticFuncProto 获取字节码和元数据。CallStack 使用 `Uint32List` 存储，只能存整数，因此记录 funcId 而非 DarticFuncProto 引用。

**帧空间预留**：函数入口时，编译器已知该函数需要的值栈槽位数（`DarticFuncProto.valueRegCount`）和引用栈槽位数（`DarticFuncProto.refRegCount`），`CALL` 指令直接推进 sp 预留空间。

**引用栈前三槽约定**：每帧的引用栈起始固定预留三个槽位——ITA（rsp+0）、FTA（rsp+1）、this/receiver（rsp+2）。非泛型函数的 ITA/FTA 为 null，静态函数/顶层函数的 this 为 null。这些槽位计入 `refRegCount`。ITA/FTA 由泛型系统使用（详见 Ch6）。

## 关键约束与边界条件

| 约束项 | 值 | 来源 |
|--------|-----|------|
| CallStack 帧大小 | 6 个 uint32 | funcId + returnPC + savedFP + savedVSP + savedRSP + resultReg |
| DarticFuncProto 字段 | bytecode + valueRegCount + refRegCount + paramCount + icTable + exceptionTable + upvalueDescriptors | 编译器产出，loadModule 时注册到全局函数表 |
| DarticFrame 字段总数 | 22 个（9 基础与栈快照 + 7 异步与生成器控制 + 6 挂起恢复） | 含 upvalues 字段 |
| DarticClosure 开销 | DarticFuncProto 引用 + upvalues 列表 | 无上值闭包仅 2 个指针；上值数 <= 256（WIDE 扩展到 65536） |
| ValueStack 槽位 | 8 字节/槽 | Int64List 和 Float64List 共享同一缓冲区 |
| ValueStack 初始容量 | 10,240 槽（80 KB） | maxCallDepth x 平均 20 值栈槽/帧 |
| RefStack 初始容量 | 5,120 槽（~40 KB） | maxCallDepth x 平均 10 引用栈槽/帧 |
| 三栈总预分配 | ~132 KB | ValueStack 80KB + RefStack 40KB + CallStack 12KB，移动设备可接受 |

## 已知局限与演进路径

> **Phase 2**：DarticObject 内存优化。当前每实例固定开销 ~88-96 字节（约为原生 Dart 对象的 5 倍）。优化方向：对常见字段数量（0-4 个 ref 字段）使用内联字段存储的子类，消除 `List` 间接引用。触发条件：profiling 显示小对象大量创建导致内存压力。

> **Phase 2**：ValueStack/RefStack 容量动态扩展（倍增 + memcpy，`Float64List` 视图需重建）。触发条件：实际应用中出现深调用链导致预分配栈空间不足。

> **Phase 2**：debug 模式双视图安全校验。为值栈槽位维护 `StackKind` 标记数组，每次读写校验视图类型一致性，帮助发现编译器 StackKind 分类的 bug。Release 模式不检查。
