# Chapter 1: 字节码指令集架构

## 模块定位

字节码 ISA 定义 dartic 的指令编码格式、操作码分类和常量池结构。它是编译器（Ch5）的输出目标和执行引擎（Ch3）的执行输入，也是沙箱验证器（Ch8）的检查对象。ISA 设计直接决定了分发循环的性能上界。

## 与其他模块的关系

| 方向 | 模块 | 接口 |
|------|------|------|
| 被消费 | Ch5 编译器 | 编译器生成符合 ISA 编码格式的 `Uint32List` 字节码 |
| 被消费 | Ch3 执行引擎 | 分发循环解码并执行 ISA 定义的指令 |
| 被消费 | Ch8 沙箱 | 验证器检查操作码合法性、操作数范围、WIDE 规则 |
| 契约 | Ch6 泛型 | 泛型相关指令（PUSH_ITA, INSTANTIATE_TYPE 等）的语义 |

## 设计决策

| 决策项 | 选择 | 备选方案与拒绝理由 | 理由 |
|--------|------|-------------------|------|
| 指令宽度 | 固定 32 位 | 16 位变长：解码需条件分支，分支预测差；8 位：操作数空间不足 | 单次加载，缓存行容纳 16 条指令 |
| 架构类型 | 寄存器式 | 栈式：wasmi v0.32 从栈式改为寄存器式获 5x 提升 | 相比栈式减少约 46% 指令执行数 |
| Opcode 编号 | 0-255 连续稠密 | 稀疏编号：Dart AOT 对稀疏 switch 生成二分查找而非跳转表 | O(1) 跳转表分发 |
| 值栈 | 共享 ByteBuffer 双视图 | 独立 int/double 栈：两套栈指针管理复杂 | int 保留 64 位精度，double 无装箱 |
| 引用栈 | 独立 `List<Object?>` | 混入值栈：无法参与 GC 追踪 | 参与宿主 GC 追踪 |
| 常量池 | 四分区（refs/ints/doubles/names） | 统一 `List<Object?>`：不同类型混存导致装箱开销 | `LOAD_CONST_INT` 直接从 Int64List 读取，零装箱 |

## 核心概念

### ISA 可见的双栈

ISA 指令直接操作两个栈（完整的三栈模型——含 CallStack——详见 Ch2）：

| 栈 | 底层结构 | 存储内容 | 寻址方式 |
|----|---------|---------|---------|
| 值栈（ValueStack） | 共享 `ByteBuffer`，叠加 `Int64List` (intView) 和 `Float64List` (doubleView) 两个视图 | int、double、bool（bool 编码为 0/1） | `valueStack[slot]` / `doubleView[slot]` |
| 引用栈（RefStack） | `List<Object?>` | String、对象实例、闭包、null 等引用类型 | `refStack[slot]` |

> 注意：运行时实际使用三栈模型（ValueStack + RefStack + CallStack）。CallStack 存储帧元数据（returnPC、savedFP 等），由执行引擎的 CALL/RETURN 逻辑隐式管理，ISA 指令不直接寻址 CallStack。

**双视图安全约束**：intView 和 doubleView 共享底层 ByteBuffer，编译器必须保证——**同一值栈槽位在其活跃区间内只通过一种视图访问**。违反此不变式会导致位模式误读。编译器通过 `StackKind` 分类确保正确性：`int`/`bool` 变量只生成 intView 访问指令，`double` 变量只生成 doubleView 访问指令，同一槽位不会在不同类型间复用。

分栈设计使数值运算零装箱——`ADD_INT` 直接操作 `Int64List` 元素，无需 Object 装拆箱。引用类型独立存放于 `List<Object?>`，参与宿主 GC 追踪。

### 四分区常量池

每个编译单元关联一个常量池，由四个独立分区组成：

| 分区 | 存储类型 | 对应指令 | 底层容器 |
|------|---------|---------|---------|
| refs | String, Type, FunctionProto 等引用常量 | `LOAD_CONST` | `List<Object?>` |
| ints | int 常量 | `LOAD_CONST_INT` | `Int64List` |
| doubles | double 常量 | `LOAD_CONST_DBL` | `Float64List` |
| names | 属性名/方法名（动态访问用） | `GET_FIELD_DYN` 等 | `List<String>` |

**分区设计理由**：`LOAD_CONST_INT` 直接从 `Int64List` 读取，避免了通用常量池中 `List<Object?>` 的装箱开销。`LOAD_CONST_DBL` 同理通过 `Float64List` 零装箱加载。

### 内联缓存

每个 `CALL_VIRTUAL` 指令关联一个内联缓存（IC）条目，存储在函数元数据的 IC 表中：

| 属性 | 类型 | 说明 |
|------|------|------|
| methodNameIndex | int | 方法名在常量池 names 中的索引 |
| cachedClassId | int | 单态缓存的类 ID（-1 = 未缓存） |
| cachedMethodOffset | int | 缓存的方法入口偏移 |

`CALL_VIRTUAL A, B, C` 的操作数 C 编码 IC 表索引（`funcProto.icTable[C]`）。IC 分发流程详见 Ch3 执行引擎。

## 指令编码格式

所有指令固定 32 位，`Uint32List` 存储。8 位操作码 + 24 位操作数空间，支持五种编码格式：

```
ABC    [op:8][A:8][B:8][C:8]      三操作数：R(A) = R(B) op R(C)
ABx    [op:8][A:8][Bx:16]         寄存器 + 无符号 16 位立即数
AsBx   [op:8][A:8][sBx:16]        寄存器 + 有符号 16 位偏移（excess-K 编码，K = 0x7FFF）
Ax     [op:8][Ax:24]              24 位无符号立即数（常量索引等）
sAx    [op:8][sAx:24]             24 位有符号立即数（大范围跳转，excess-K 编码，K = 0x7FFFFF）
```

**编解码方式**：操作码通过 `instr & 0xFF` 提取；操作数通过位移和掩码提取（如 `A = (instr >> 8) & 0xFF`）。有符号偏移 sBx 使用 excess-K 编码（实际值 = 编码值 - 0x7FFF）；有符号偏移 sAx 同理（实际值 = 编码值 - 0x7FFFFF）。

### WIDE 前缀

当操作数超出 8 位或 16 位范围时，`WIDE` 前缀（0xFE）将下一条指令的操作数宽度扩展。WIDE 后紧跟一条 32 位扩展字（高位），再跟原指令：

```
WIDE    [0xFE][padding:24]            ← 前缀
扩展字  [layout depends on format]     ← 高位扩展
原指令  [op:8][operands:24]            ← 正常编码
```

各格式的扩展字布局：

| 原指令格式 | 扩展字布局 | 组合后范围 |
|-----------|-----------|----------|
| ABC | `[_:8][extA:8][extB:8][extC:8]` | A/B/C 各 16 位 |
| ABx | `[_:8][extA:8][extBx:16]` | A 16 位, Bx 32 位 |
| AsBx | `[_:8][extA:8][extSBx:16]` | A 16 位, sBx 32 位有符号 |
| Ax / sAx | `[_:8][extAx:24]` | Ax/sAx 48 位 |

**WIDE 约束规则**：

1. WIDE 后必须跟 2 个字（扩展字 + 原指令），不得出现在字节码末尾 2 个位置内
2. 不可嵌套（扩展字后的原指令不得为 WIDE）
3. 扩展字位域拆分必须与原指令编码格式严格对应，验证器在加载时检查
4. 包含 WIDE 的指令序列占 3 个字，跳转目标计算必须正确处理

WIDE 前缀极少使用（函数局部变量 >256 或常量池 >65K 时），不影响主路径性能。

## 工作流程

### 指令解码与分发

分发循环对每条指令的处理流程：

1. 从 `code[pc]` 读取一个 32 位字
2. 提取操作码：`op = instr & 0xFF`
3. 按操作码分发（O(1) 跳转表 switch）
4. 在对应处理分支中，按指令格式提取操作数（位移 + 掩码）
5. 执行语义操作（操作值栈 / 引用栈 / 常量池）
6. `pc++`，回到步骤 1

### WIDE 前缀解码

遇到 `WIDE`（0xFE）时的扩展解码流程：

1. 识别 `op == 0xFE`，读取 `code[pc+1]`（扩展字）和 `code[pc+2]`（原指令）
2. 从原指令提取操作码，确定编码格式（ABC / ABx / AsBx / Ax / sAx）
3. 从扩展字和原指令中分别提取高位和低位操作数
4. 组合为完整操作数（高位左移 + 低位拼接）
5. 执行语义操作
6. `pc += 3`（跳过前缀 + 扩展字 + 原指令）

## 操作码总览

操作码从 0x00 开始连续编号，按功能分段。每段预留若干编号供扩展，未使用的编号填充 `ILLEGAL` 指向错误处理。

| 范围 | 分组 | 已用 | 预留 |
|------|------|------|------|
| 0x00-0x0F | 加载/存储 | 16 | 0 |
| 0x10-0x1F | 整数算术 | 14 | 2 |
| 0x20-0x2F | 浮点算术 | 7 | 9 |
| 0x30-0x3F | 比较 | 12 | 4 |
| 0x40-0x4F | 控制流 | 6 | 10 |
| 0x50-0x5F | 调用与返回 | 8 | 8 |
| 0x60-0x6F | 对象操作 | 9 | 7 |
| 0x70-0x77 | 闭包 | 2 | 6 |
| 0x78-0x7F | 泛型与类型 | 7 | 1 |
| 0x80-0x8F | 异步与生成器 | 9 | 7 |
| 0x90-0x97 | 集合操作 | 4 | 4 |
| 0x98-0x9F | 字符串与动态 | 3 | 5 |
| 0xA0-0xA3 | 全局变量 | 2 | 2 |
| 0xA4-0xA7 | 异常处理与断言 | 4 | 0 |
| 0xA8-0xFD | 预留（Superinstruction 等） | 0 | 86 |
| 0xFE-0xFF | 系统 | 2 | 0 |
| **合计** | | **105** | **151** |

## 操作码分类

### 加载/存储 (0x00-0x0F)

```
0x00  NOP                         空操作
0x01  LOAD_CONST    A, Bx         refStack[A] = constPool[Bx]
0x02  LOAD_NULL     A             refStack[A] = null
0x03  LOAD_TRUE     A             valueStack[A] = 1 (true)
0x04  LOAD_FALSE    A             valueStack[A] = 0 (false)
0x05  LOAD_INT      A, sBx        valueStack[A] = sBx (小整数立即数)
0x06  LOAD_CONST_INT A, Bx        valueStack[A] = intConstPool[Bx]
0x07  LOAD_CONST_DBL A, Bx        valueStack[A] = dblConstPool[Bx] (通过 doubleView)
0x08  MOVE_REF      A, B          refStack[A] = refStack[B]
0x09  MOVE_VAL      A, B          valueStack[A] = valueStack[B]
0x0A  LOAD_UPVALUE  A, Bx         refStack[A] = upvalues[Bx].value
0x0B  STORE_UPVALUE A, Bx         upvalues[Bx].value = refStack[A]
0x0C-0x0F  （预留，box/unbox 已迁至 Type Conversion 区段 0x27-0x2C）
```

### 整数算术 (0x10-0x1F)

```
0x10  ADD_INT       A, B, C       valueStack[A] = valueStack[B] + valueStack[C]
0x11  SUB_INT       A, B, C       valueStack[A] = valueStack[B] - valueStack[C]
0x12  MUL_INT       A, B, C       valueStack[A] = valueStack[B] * valueStack[C]
0x13  DIV_INT       A, B, C       valueStack[A] = valueStack[B] ~/ valueStack[C]
0x14  MOD_INT       A, B, C       valueStack[A] = valueStack[B] % valueStack[C]
0x15  NEG_INT       A, B          valueStack[A] = -valueStack[B]
0x16  BIT_AND       A, B, C       valueStack[A] = valueStack[B] & valueStack[C]
0x17  BIT_OR        A, B, C       valueStack[A] = valueStack[B] | valueStack[C]
0x18  BIT_XOR       A, B, C       valueStack[A] = valueStack[B] ^ valueStack[C]
0x19  BIT_NOT       A, B          valueStack[A] = ~valueStack[B]
0x1A  SHL           A, B, C       valueStack[A] = valueStack[B] << valueStack[C]
0x1B  SHR           A, B, C       valueStack[A] = valueStack[B] >> valueStack[C]
0x1C  USHR          A, B, C       valueStack[A] = valueStack[B] >>> valueStack[C]
0x1D  ADD_INT_IMM   A, B, C       valueStack[A] = valueStack[B] + C (C 为无符号 8 位立即数 [0, 255])
0x1E-0x1F 预留
```

### 浮点算术与类型转换 (0x20-0x2F)

```
0x20  ADD_DBL       A, B, C       doubleView[A] = doubleView[B] + doubleView[C]
0x21  SUB_DBL       A, B, C       doubleView[A] = doubleView[B] - doubleView[C]
0x22  MUL_DBL       A, B, C       doubleView[A] = doubleView[B] * doubleView[C]
0x23  DIV_DBL       A, B, C       doubleView[A] = doubleView[B] / doubleView[C]
0x24  NEG_DBL       A, B          doubleView[A] = -doubleView[B]
0x25  INT_TO_DBL    A, B          doubleView[A] = valueStack[B].toDouble()
0x26  DBL_TO_INT    A, B          valueStack[A] = doubleView[B].toInt()
0x27  BOX_INT       A, B          refStack[A] = valueStack[B] (装箱 int)
0x28  BOX_DOUBLE    A, B          refStack[A] = doubleView[B] (装箱 double)
0x29  BOX_BOOL      A, B          refStack[A] = (valueStack[B] != 0) (装箱 bool: 0/1 → false/true)
0x2A  UNBOX_INT     A, B          valueStack[A] = refStack[B] as int (拆箱 int)
0x2B  UNBOX_DOUBLE  A, B          doubleView[A] = refStack[B] as double (拆箱 double)
0x2C  UNBOX_BOOL    A, B          valueStack[A] = (refStack[B] as bool) ? 1 : 0 (拆箱 bool)
0x2D  NOT_BOOL      A, B          valueStack[A] = valueStack[B] ^ 1 (布尔取反)
0x2E-0x2F 预留
```

**BOX/UNBOX 分离 bool**：编译器通过 `StackKind.boolVal` 区分 bool 和 int，使用对应的 BOX_BOOL/UNBOX_BOOL 指令。UNBOX_INT 不再需要运行时 `is bool` 分支检查，只处理纯 int 值。

### 比较 (0x30-0x3F)

```
0x30  LT_INT        A, B, C       valueStack[A] = valueStack[B] < valueStack[C] ? 1 : 0
0x31  LE_INT        A, B, C       valueStack[A] = valueStack[B] <= valueStack[C] ? 1 : 0
0x32  GT_INT        A, B, C       valueStack[A] = valueStack[B] > valueStack[C] ? 1 : 0
0x33  GE_INT        A, B, C       valueStack[A] = valueStack[B] >= valueStack[C] ? 1 : 0
0x34  EQ_INT        A, B, C       valueStack[A] = valueStack[B] == valueStack[C] ? 1 : 0
0x35  LT_DBL        A, B, C       (同上，操作 doubleView)
0x36  LE_DBL        A, B, C
0x37  GT_DBL        A, B, C
0x38  GE_DBL        A, B, C
0x39  EQ_DBL        A, B, C
0x3A  EQ_REF        A, B, C       valueStack[A] = identical(refStack[B], refStack[C]) ? 1 : 0
0x3B  EQ_GENERIC    A, B, C       valueStack[A] = refStack[B] == refStack[C] ? 1 : 0 (调用 operator==)
0x3C-0x3F 预留
```

`EQ_REF` 执行引用相等性检查（`identical()`），不调用任何方法。`EQ_GENERIC` 调用接收者的 `operator==`，支持用户自定义相等性语义。编译器根据静态类型选择：已知基本类型用 `EQ_INT`/`EQ_DBL`/`EQ_REF`，其他用 `EQ_GENERIC`。

### 控制流 (0x40-0x4F)

```
0x40  JUMP          sBx           PC += sBx (AsBx 格式，A 未使用，固定为 0)
0x41  JUMP_IF_TRUE  A, sBx        if valueStack[A] != 0 then PC += sBx
0x42  JUMP_IF_FALSE A, sBx        if valueStack[A] == 0 then PC += sBx
0x43  JUMP_IF_NULL  A, sBx        if refStack[A] == null then PC += sBx
0x44  JUMP_IF_NNULL A, sBx        if refStack[A] != null then PC += sBx
0x45  JUMP_AX       sAx           PC += sAx (大范围跳转，Ax 格式，有符号 24 位，excess-K 编码，K = 0x7FFFFF)
0x46-0x4F 预留
```

### 调用与返回 (0x50-0x5F)

```
0x50  CALL          A, B, C       refStack[A] = call refStack[B] with C args
0x51  CALL_STATIC   A, Bx         refStack[A] = call staticFunc[Bx]
0x52  CALL_HOST     A, Bx         refStack[A] = hostBindings.invoke(Bx, args)
0x53  CALL_VIRTUAL  A, B, C       refStack[A] = refStack[B].method(IC[C])(args)
0x54  CALL_SUPER    A, Bx         refStack[A] = super.method[Bx](args)
0x55  RETURN_REF    A             return refStack[A]
0x56  RETURN_VAL    A             return valueStack[A] (需装箱)
0x57  RETURN_NULL                 return null
0x58-0x5F 预留
```

**调用约定**：

参数传递采用**调用者预布局**策略——编译器在调用者帧的栈顶预先将参数放置在被调用者帧的对应寄存器位置（值参数放值栈、引用参数放引用栈）。被调用者入口时直接使用这些寄存器，无需额外的参数复制。具体的帧布局详见 Ch2 栈帧布局节。

- `CALL A, B, C`：B 为 refStack 中的 DarticClosure 或 DarticFuncProto 引用，C 为参数个数（编译器已将参数预布局到被调用者帧位置），返回值写入 refStack[A]
- `CALL_VIRTUAL A, B, C`：B 为接收者在 refStack 中的寄存器，C 为 IC 表索引（IC 条目包含方法名和缓存的 classId/方法偏移）。参数个数由 DarticFuncProto 的元数据提供（IC 命中后从缓存的 funcProto 读取）
- `CALL_STATIC A, Bx`：Bx 为函数表索引，参数个数由目标 DarticFuncProto 的元数据提供
- `CALL_HOST A, Bx`：Bx 为宿主绑定表索引，参数通过引用栈传递（跨边界参数均需装箱）
- `CALL_SUPER A, Bx`：Bx 为编译期解析的超类方法函数索引（Kernel 的 interfaceTarget 已确定具体方法）
- `RETURN_REF A` / `RETURN_VAL A` / `RETURN_NULL`：将返回值写入调用者帧的 resultReg 寄存器（CallStack 中保存的目标位置），然后弹帧恢复调用者状态

### 对象操作 (0x60-0x6F)

```
0x60  GET_FIELD_REF A, B, C       refStack[A] = refStack[B].refFields[C] (引用字段，C 为编译期确定的字段偏移)
0x61  SET_FIELD_REF A, B, C       refStack[A].refFields[C] = refStack[B]
0x62  GET_FIELD_VAL A, B, C       valueStack[A] = refStack[B].valueFields[C] (值字段)
0x63  SET_FIELD_VAL A, B, C       refStack[A].valueFields[C] = valueStack[B]
0x64  NEW_INSTANCE  A, Bx         refStack[A] = allocate class[Bx] (ABx 格式)
0x65  INSTANCEOF    A, B, C       valueStack[A] = refStack[B] is type[C] ? 1 : 0 (C 为类型常量池索引)
0x66  CAST          A, B, C       refStack[A] = refStack[B] as type[C]; throw if fail (C 为类型常量池索引)
0x67  GET_FIELD_DYN A, B, C       refStack[A] = refStack[B].getProperty(names[C]) (C 为 names 常量池索引)
0x68  SET_FIELD_DYN A, B, C       refStack[A].setProperty(names[C], refStack[B])
0x69-0x6F 预留
```

> 注意：`INSTANCEOF`/`CAST`/`GET_FIELD_DYN`/`SET_FIELD_DYN` 的 C 操作数在 ABC 格式下仅 8 位（0-255）。当类型常量池或 names 常量池索引超过 255 时，需使用 WIDE 前缀扩展。

### 闭包 (0x70-0x77)

```
0x70  CLOSURE       A, Bx         refStack[A] = Closure(funcProto[Bx], captured upvalues)
0x71  CLOSE_UPVALUE A             关闭所有指向 >= A 槽位的开放上值
0x72-0x77 预留
```

### 泛型与类型 (0x78-0x7F)

```
0x78  PUSH_ITA      A             refStack[A] = 当前帧的 instantiator type args
0x79  PUSH_FTA      A             refStack[A] = 当前帧的 function type args
0x7A  LOAD_TYPE_ARG A, B, C       refStack[A] = refStack[B].typeArgs[C]
0x7B  INSTANTIATE_TYPE A, Bx      refStack[A] = instantiate typeTemplate[Bx] with ITA/FTA
0x7C  CREATE_TYPE_ARGS A, B       refStack[A] = TypeArgs(refStack[A..A+B-1])
0x7D  ALLOC_GENERIC A, B          refStack[A] = new class with TypeArgs from refStack[B]
0x7E  CHECK_COVARIANT A, Bx       检查 refStack[A] 匹配协变参数类型 type[Bx]
0x7F  预留
```

### 异步与生成器 (0x80-0x8F)

```
0x80  INIT_ASYNC    A, Bx         创建 Completer<T>，refStack[A] = completer.future
0x81  AWAIT         A, Bx         await refStack[A]，恢复点 IP = Bx
0x82  ASYNC_RETURN  A             completer.complete(refStack[A])
0x83  ASYNC_THROW   A, B          completer.completeError(refStack[A], refStack[B])
0x84  INIT_ASYNC_STAR A, Bx       创建 StreamController<T>，refStack[A] = stream
0x85  YIELD         A, Bx         yield refStack[A]，恢复点 IP = Bx
0x86  YIELD_STAR    A, Bx         yield* refStack[A]
0x87  INIT_SYNC_STAR A, Bx        创建惰性 Iterable<T>
0x88  AWAIT_STREAM_NEXT A, Bx     await for 挂起等待 stream 事件
0x89-0x8F 预留
```

### 集合操作 (0x90-0x97)

```
0x90  CREATE_LIST   A, B, C       refStack[A] = List(refStack[A+1..A+C]), typeArgs from refStack[B]
0x91  CREATE_MAP    A, B, C       refStack[A] = Map(key-value pairs), typeArgs from refStack[B]
0x92  CREATE_SET    A, B, C       refStack[A] = Set(refStack[A+1..A+C]), typeArgs from refStack[B]
0x93  CREATE_RECORD A, Bx         refStack[A] = Record(fields...), shape from constPool.refs[Bx]
0x94-0x97 预留
```

`CREATE_RECORD` 的 Bx 索引常量池 `refs` 分区，对应条目为 `RecordShape` 描述符（包含命名字段名列表和位置字段数量）。

**Record 字段访问**：Record 在运行时采用与类实例相同的对象布局（位置字段在前，命名字段按名称排序在后）。编译器根据 `RecordShape` 在编译期将 `RecordIndexGet` / `RecordNameGet` 映射为确定的字段索引，生成 `GET_FIELD_REF` / `GET_FIELD_VAL` 指令，无需专用操作码。

### 字符串与动态 (0x98-0x9F)

```
0x98  STRING_INTERP A, B          refStack[A] = string interpolation of B parts from refStack
0x99  ADD_GENERIC   A, B, C       refStack[A] = refStack[B] + refStack[C] (dynamic +)
0x9A  INVOKE_DYN    A, B, C       refStack[A] = dynamicDispatch(refStack[B], names[C], args)
0x9B-0x9F 预留
```

`INVOKE_DYN` 用于 `dynamic` 类型接收者的方法调用（对应 Kernel 的 `DynamicInvocation`）。运行时语义：按 `names[C]` 查找接收者实际类型的方法，找到则调用，找不到则转发 `noSuchMethod`。`ADD_GENERIC` 是 `dynamic` 上 `+` 运算的特化快路径，其他动态运算符（`-`、`*` 等）通过 `INVOKE_DYN` 分发。

### 全局变量 (0xA0-0xA3)

```
0xA0  LOAD_GLOBAL   A, Bx         refStack[A] = globals[Bx]（若未初始化则触发惰性初始化）
0xA1  STORE_GLOBAL  A, Bx         globals[Bx] = refStack[A]
0xA2-0xA3 预留
```

### 异常处理与断言 (0xA4-0xA7)

```
0xA4  THROW         A             throw refStack[A]
0xA5  RETHROW       A, B          rethrow refStack[A] with stackTrace refStack[B]
0xA6  ASSERT        A, Bx         if valueStack[A] == 0 → throw AssertionError(constPool[Bx])
0xA7  NULL_CHECK    A             if refStack[A] == null → throw TypeError; else fall-through
```

### 系统 (0xFE-0xFF)

```
0xFE  WIDE                        下一条指令使用扩展操作数
0xFF  HALT          A, B, C       停机并记录入口函数返回值
```

**HALT 编码**：使用 ABC 格式。A = 结果寄存器编号，B = 结果类型（0=void/无返回值，1=int，2=double，3=ref），C = 保留。解释器在重置栈指针前根据 B 字段从对应栈读取返回值，存入 `entryResult`。`encodeABC(Op.halt, 0, 0, 0)` 与旧的 `encodeAx(Op.halt, 0)` 二进制兼容（均为 `0x000000FF`）。

**0xA8-0xFD 预留**：用于 Superinstruction（高频指令序列合并）等后续优化。当前已定义 105 个操作码（含 WIDE 和 HALT），预留 86 个槽位。

> **Phase 2**：具体特化 opcode 留待 profiling 数据确定。触发条件：基准测试显示指令分发成为瓶颈。

## 关键约束与边界条件

| 约束 | 值 | 来源 |
|------|-----|------|
| Opcode 空间 | 0-255（8 位） | 32 位指令编码，低 8 位为 opcode |
| 当前已定义 opcode | 105 个 | ISA 定义（含 WIDE 和 HALT） |
| 预留 opcode 槽位 | 86 个（0xA8-0xFD） | 供 Superinstruction 使用 |
| 标准寄存器上限 | 256（8 位 A/B/C） | ABC 编码格式 |
| WIDE 扩展后寄存器上限 | 65536（16 位） | WIDE 前缀组合 |
| 标准 Bx 范围 | 0-65535（16 位无符号） | ABx 编码格式 |
| 标准 sBx 范围 | -32767 ~ +32768 | AsBx excess-K 编码（0 − 0x7FFF = −32767, 0xFFFF − 0x7FFF = +32768） |
| 标准 sAx 范围 | -8388607 ~ +8388608 | sAx excess-K 编码（0 − 0x7FFFFF = −8388607, 0xFFFFFF − 0x7FFFFF = +8388608） |
| WIDE 指令宽度 | 3 个字（前缀 + 扩展字 + 原指令） | WIDE 规范 |

## 已知局限与演进路径

| 局限 | 影响 | 演进计划 |
|------|------|---------|
| 无 `NOT` 指令（逻辑非） | 需用 `BIT_XOR A, B, #1` 间接实现 | Phase 2 可添加专用 opcode |
| WIDE 前缀规格 | 实现时需仔细处理扩展字位域拆分 | 本文档已明确各格式布局 |
| `ADD_INT_IMM` 的 C 操作数 | 定义为无符号 [0, 255]，不支持负立即数 | 负立即数通过 `SUB_INT` 或常量池加载 |
| Quickening 未实现 | 编译器已做静态特化，运行时快化留待 profiling | Phase 2。触发条件：profiling 显示需要运行时 profile-guided 优化 |

<details>
<summary>附录：编解码参考实现</summary>

```dart
// 编码
int encodeABC(int op, int a, int b, int c) =>
    op | (a << 8) | (b << 16) | (c << 24);

int encodeABx(int op, int a, int bx) =>
    op | (a << 8) | (bx << 16);

int encodeAsBx(int op, int a, int sbx) =>
    op | (a << 8) | ((sbx + 0x7FFF) << 16);

int encodeAx(int op, int ax) =>
    op | (ax << 8);

int encodesAx(int op, int sax) =>
    op | ((sax + 0x7FFFFF) << 8);

// 解码
int decodeOp(int instr) => instr & 0xFF;
int decodeA(int instr) => (instr >> 8) & 0xFF;
int decodeB(int instr) => (instr >> 16) & 0xFF;
int decodeC(int instr) => (instr >> 24) & 0xFF;
int decodeBx(int instr) => (instr >> 16) & 0xFFFF;
int decodesBx(int instr) => decodeBx(instr) - 0x7FFF;
int decodeAx(int instr) => (instr >> 8) & 0xFFFFFF;
int decodesAx(int instr) => decodeAx(instr) - 0x7FFFFF;
```

</details>
