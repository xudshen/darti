# Chapter 1: 字节码指令集架构

## 设计决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 指令宽度 | 固定 32 位 | 解码简单（位运算）、`Uint32List` 单次加载、缓存行容纳 16 条指令 |
| 架构类型 | 寄存器式 | 相比栈式减少约 46% 指令执行数，适合 switch 分发 |
| Opcode 编号 | 0-255 连续稠密 | Dart AOT 编译器对稠密 switch 生成 O(1) 跳转表 |
| 值栈 | 共享 ByteBuffer 上的 Int64List + Float64List 双视图 | int 保留 64 位精度，double 无装箱运算 |
| 引用栈 | 独立 `List<Object?>` | 参与 Dart GC 追踪 |

## 指令编码格式

所有指令固定 32 位，`Uint32List` 存储。8 位操作码 + 24 位操作数空间，支持四种编码格式：

```
ABC    [op:8][A:8][B:8][C:8]      三操作数：R(A) = R(B) op R(C)
ABx    [op:8][A:8][Bx:16]         寄存器 + 无符号 16 位立即数
AsBx   [op:8][A:8][sBx:16]        寄存器 + 有符号 16 位偏移（excess-K 编码）
Ax     [op:8][Ax:24]              24 位无符号立即数（大范围跳转/常量索引）
```

### 编码/解码

```dart
// 编码
int encodeABC(int op, int a, int b, int c) =>
    op | (a << 8) | (b << 16) | (c << 24);

int encodeABx(int op, int a, int bx) =>
    op | (a << 8) | (bx << 16);

int encodeAsBx(int op, int a, int sbx) =>
    op | (a << 8) | ((sbx + 0x7FFF) << 16);  // excess-K 偏移

int encodeAx(int op, int ax) =>
    op | (ax << 8);

// 解码
int decodeOp(int instr) => instr & 0xFF;
int decodeA(int instr) => (instr >> 8) & 0xFF;
int decodeB(int instr) => (instr >> 16) & 0xFF;
int decodeC(int instr) => (instr >> 24) & 0xFF;
int decodeBx(int instr) => (instr >> 16) & 0xFFFF;
int decodesBx(int instr) => decodeBx(instr) - 0x7FFF;
int decodeAx(int instr) => (instr >> 8) & 0xFFFFFF;
```

### 双视图安全约束

值栈的 `intView` 和 `doubleView` 共享底层 `ByteBuffer`。编译器必须保证：**同一值栈槽位在其活跃区间内只通过一种视图访问**。违反此不变式会导致位模式误读（将 double 的 IEEE 754 位模式当作 int 解释，反之亦然）。

编译器通过 `StackKind` 分类确保正确性——`int`/`bool` 变量只生成 `intView` 访问指令，`double` 变量只生成 `doubleView` 访问指令。同一槽位不会在不同类型间复用（作用域级分配按 `StackKind` 独立分配寄存器）。

> **Debug 模式**：可添加运行时断言，在每次值栈写入时记录槽位的视图类型，读取时校验一致性。仅用于开发期验证，生产模式无开销。

### WIDE 前缀

当操作数超出 8 位或 16 位范围时，`WIDE` 前缀将下一条指令的操作数宽度扩展。`WIDE` 后紧跟一条 32 位扩展字（高位扩展），再跟原指令：

```
WIDE    [0xFE][padding:24]            ← 前缀
扩展字  [layout depends on format]     ← 高位扩展（见下表）
原指令  [op:8][operands:24]            ← 正常编码
```

#### 各格式的扩展字布局

扩展字的位域拆分与下一条指令的编码格式对应，为每个操作数提供高位：

```
ABC  指令：扩展字  [_:8][extA:8][extB:8][extC:8]
           组合后  A' = (extA << 8) | A     → 16 位寄存器索引
                   B' = (extB << 8) | B     → 16 位
                   C' = (extC << 8) | C     → 16 位

ABx  指令：扩展字  [_:8][extA:8][extBx:16]
           组合后  A'  = (extA << 8) | A    → 16 位
                   Bx' = (extBx << 16) | Bx → 32 位无符号

AsBx 指令：扩展字  [_:8][extA:8][extSBx:16]
           组合后  A'   = (extA << 8) | A   → 16 位
                   sBx' = ((extSBx << 16) | unsigned_Bx) - 0x7FFFFFFF → 32 位有符号

Ax   指令：扩展字  [_:8][extAx:24]
           组合后  Ax' = (extAx << 24) | Ax → 48 位无符号
```

#### 解释器处理

```dart
case OpCode.wide:
  final ext = code[pc++];        // 读取扩展字
  final nextInstr = code[pc++];  // 读取原指令
  final op = decodeOp(nextInstr);

  switch (OpCode.format(op)) {
    case InstrFormat.ABC:
      final a = ((ext >> 8) & 0xFF) << 8 | decodeA(nextInstr);
      final b = ((ext >> 16) & 0xFF) << 8 | decodeB(nextInstr);
      final c = ((ext >> 24) & 0xFF) << 8 | decodeC(nextInstr);
      // 执行 op(a, b, c)
    case InstrFormat.ABx:
      final a = ((ext >> 8) & 0xFF) << 8 | decodeA(nextInstr);
      final bx = ((ext >> 16) & 0xFFFF) << 16 | decodeBx(nextInstr);
      // 执行 op(a, bx)
    // AsBx, Ax 同理
  }
```

#### WIDE 约束规则

1. **位置约束**：WIDE 前缀后必须跟 2 个字（扩展字 + 原指令），即 `pc + 2 < codeLength` 必须成立。WIDE 不得出现在字节码末尾 2 个位置内
2. **不可嵌套**：扩展字后的原指令不得为 WIDE（`OpCode.isWideCompatible(op)` 排除 WIDE 自身）
3. **格式一致性**：扩展字的位域拆分必须与原指令的编码格式（ABC/ABx/AsBx/Ax）严格对应，验证器在加载时检查格式匹配
4. **PC 计算**：包含 WIDE 前缀的指令序列占 3 个字（前缀 + 扩展字 + 原指令），跳转目标计算和 PC 步进必须正确处理 3 字宽度

WIDE 前缀极少使用（函数局部变量 >256 或常量池 >65K 时），不影响主路径性能。

## 操作码分类

操作码从 0x00 开始连续编号，按功能分段。未使用的编号填充 `ILLEGAL` 指向错误处理。

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
0x0C  BOX_INT       A, B          refStack[A] = valueStack[B] (装箱 int)
0x0D  BOX_DOUBLE    A, B          refStack[A] = valueStack[B] (装箱 double, 通过 doubleView)
0x0E  UNBOX_INT     A, B          valueStack[A] = refStack[B] as int (拆箱)
0x0F  UNBOX_DOUBLE  A, B          valueStack[A] = (refStack[B] as double) (拆箱, 写 doubleView)
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
```

### 浮点算术 (0x20-0x2F)

```
0x20  ADD_DBL       A, B, C       doubleView[A] = doubleView[B] + doubleView[C]
0x21  SUB_DBL       A, B, C       doubleView[A] = doubleView[B] - doubleView[C]
0x22  MUL_DBL       A, B, C       doubleView[A] = doubleView[B] * doubleView[C]
0x23  DIV_DBL       A, B, C       doubleView[A] = doubleView[B] / doubleView[C]
0x24  NEG_DBL       A, B          doubleView[A] = -doubleView[B]
0x25  INT_TO_DBL    A, B          doubleView[A] = valueStack[B].toDouble()
0x26  DBL_TO_INT    A, B          valueStack[A] = doubleView[B].toInt()
```

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
0x3B  EQ_GENERIC    A, B, C       valueStack[A] = refStack[B] == refStack[C] ? 1 : 0
```

### 控制流 (0x40-0x4F)

```
0x40  JUMP          sBx           PC += sBx (AsBx 格式，A 未使用)
0x41  JUMP_IF_TRUE  A, sBx        if valueStack[A] != 0 then PC += sBx
0x42  JUMP_IF_FALSE A, sBx        if valueStack[A] == 0 then PC += sBx
0x43  JUMP_IF_NULL  A, sBx        if refStack[A] == null then PC += sBx
0x44  JUMP_IF_NNULL A, sBx        if refStack[A] != null then PC += sBx
0x45  JUMP_AX       Ax            PC += Ax (大范围跳转，Ax 格式)
```

### 调用与返回 (0x50-0x5F)

```
0x50  CALL          A, B, C       refStack[A] = call refStack[B] with C args
                                  参数从 refStack[B+1] 开始连续排列
0x51  CALL_STATIC   A, Bx         refStack[A] = call staticFunc[Bx]
                                  参数数量和类型从 funcProto[Bx].paramCount 获取
                                  参数从 refStack[A+1] 开始连续排列
0x52  CALL_HOST     A, Bx         refStack[A] = hostBindings.invoke(Bx, args)
                                  A=baseReg, Bx=绑定索引(16-bit); argCount 从绑定表条目获取
0x53  CALL_VIRTUAL  A, B, C       refStack[A] = refStack[B].method(IC)(args)
                                  关联内联缓存槽
0x54  CALL_SUPER    A, Bx         refStack[A] = super.method[Bx](args)
0x55  RETURN_REF    A             return refStack[A]
0x56  RETURN_VAL    A             return valueStack[A] (需装箱)
0x57  RETURN_NULL                 return null
```

### 对象操作 (0x60-0x6F)

```
0x60  GET_FIELD_REF A, B, C       refStack[A] = refStack[B].field[C] (引用字段)
0x61  SET_FIELD_REF A, B, C       refStack[A].field[C] = refStack[B]
0x62  GET_FIELD_VAL A, B, C       valueStack[A] = refStack[B].valueField[C] (值字段)
0x63  SET_FIELD_VAL A, B, C       refStack[A].valueField[C] = valueStack[B]
0x64  NEW_INSTANCE  A, Bx         refStack[A] = allocate class[Bx]
0x65  INSTANCEOF    A, B, Cx      valueStack[A] = refStack[B] is type[Cx] ? 1 : 0
0x66  CAST          A, B, Cx      refStack[A] = refStack[B] as type[Cx]; throw if fail
0x67  GET_FIELD_DYN A, B, Cx      refStack[A] = refStack[B].getProperty(names[Cx])
0x68  SET_FIELD_DYN A, B, Cx      refStack[A].setProperty(names[Cx], refStack[B])
```

### 闭包 (0x70-0x77)

```
0x70  CLOSURE       A, Bx         refStack[A] = Closure(funcProto[Bx], captured upvalues)
0x71  CLOSE_UPVALUE A             关闭所有指向 >= A 槽位的开放上值
```

### 异步与生成器 (0x78-0x7F)

```
0x78  INIT_ASYNC    A, Bx         创建 Completer<T>，refStack[A] = completer.future
0x79  AWAIT         A, Bx         await refStack[A]，恢复点 IP = Bx
0x7A  ASYNC_RETURN  A             completer.complete(refStack[A])
0x7B  ASYNC_THROW   A, B          completer.completeError(refStack[A], refStack[B])
0x7C  INIT_ASYNC_STAR A, Bx       创建 StreamController<T>，refStack[A] = stream
0x7D  YIELD         A, Bx         yield refStack[A]，恢复点 IP = Bx
0x7E  YIELD_STAR    A, Bx         yield* refStack[A]
0x7F  INIT_SYNC_STAR A, Bx        创建惰性 Iterable<T>
```

#### 异步扩展 (0x87-0x8F 区段借用)

```
0x87  AWAIT_STREAM_NEXT A, Bx    await for 挂起等待 stream 事件
                                  恢复点 IP = Bx，结果存入 refStack[A]
```

### 泛型与类型 (0x80-0x86)

```
0x80  PUSH_ITA      A             refStack[A] = 当前帧的 instantiator type args
0x81  PUSH_FTA      A             refStack[A] = 当前帧的 function type args
0x82  LOAD_TYPE_ARG A, B, C       refStack[A] = refStack[B].typeArgs[C]
0x83  INSTANTIATE_TYPE A, Bx      refStack[A] = instantiate typeTemplate[Bx] with ITA/FTA
0x84  CREATE_TYPE_ARGS A, B       refStack[A] = TypeArgs(refStack[A..A+B-1])
0x85  ALLOC_GENERIC A, B          refStack[A] = new class with TypeArgs from refStack[B]
0x86  CHECK_COVARIANT A, Bx       检查 refStack[A] 匹配协变参数类型 type[Bx]
```

### 集合操作 (0x90-0x97)

```
0x90  CREATE_LIST   A, B, C       refStack[A] = List(refStack[A+1..A+C]), typeArgs from refStack[B]
0x91  CREATE_MAP    A, B, C       refStack[A] = Map(key-value pairs), typeArgs from refStack[B]
0x92  CREATE_SET    A, B, C       refStack[A] = Set(refStack[A+1..A+C]), typeArgs from refStack[B]
0x93  CREATE_RECORD A, Bx         refStack[A] = Record(fields...), shape from constPool.refs[Bx]
```

`CREATE_RECORD` 的 Bx 索引常量池 `refs` 分区，对应条目为 `RecordShape` 描述符（包含命名字段名列表和位置字段数量）。

### 字符串与动态 (0x98-0x9F)

```
0x98  STRING_INTERP A, B          refStack[A] = string interpolation of B parts from refStack
0x99  ADD_GENERIC   A, B, C       refStack[A] = refStack[B] + refStack[C] (dynamic +)
0x9A  INVOKE_DYN    A, B, C       refStack[A] = refStack[B].noSuchMethod(invocation)
```

### 全局变量 (0xA0-0xA3)

```
0xA0  LOAD_GLOBAL   A, Bx         refStack[A] = globals[Bx]
                                  若 globals[Bx] == _UNINITIALIZED → 执行初始化器
0xA1  STORE_GLOBAL  A, Bx         globals[Bx] = refStack[A]
```

### 异常处理与断言 (0xA4-0xA7)

```
0xA4  THROW         A             throw refStack[A]
0xA5  RETHROW       A, B          rethrow refStack[A] with stackTrace refStack[B]
0xA6  ASSERT        A, Bx         if valueStack[A] == 0 → throw AssertionError(constPool[Bx])
                                  编译器根据 --enable-asserts 标志决定是否生成此指令
```

### 系统 (0xF0-0xFF)

```
0xFE  WIDE                        下一条指令使用扩展操作数
0xFF  HALT                        停机
```

**0xA8-0xFD 预留**：用于 Superinstruction（高频指令序列合并）等后续优化。

> **Phase 2**：具体特化 opcode 留待 profiling 数据确定。

## 常量池设计

每个编译单元关联一个常量池，由四个分区组成：

```dart
class ConstantPool {
  final List<Object?> refs;       // 引用常量：String, Type, FunctionProto 等
  final Int64List ints;           // int 常量
  final Float64List doubles;      // double 常量
  final List<String> names;       // 属性名/方法名（用于动态访问）
}
```

`LOAD_CONST` 从 `refs` 加载，`LOAD_CONST_INT` 从 `ints` 加载，`LOAD_CONST_DBL` 从 `doubles` 加载。分区存储避免了通用常量池中不同类型混存导致的装箱开销。

## 内联缓存槽

每个 `CALL_VIRTUAL` 指令关联一个内联缓存条目，存储在函数元数据的 IC 表中：

```dart
class InlineCacheEntry {
  final int methodNameIndex;      // 方法名在常量池 names 中的索引
  int cachedClassId = -1;         // 单态缓存的类 ID
  int cachedMethodOffset = -1;    // 缓存的方法入口偏移

  InlineCacheEntry(this.methodNameIndex);
}
```

`CALL_VIRTUAL` 的操作数 C 编码 IC 表索引。分发循环中先查 IC 单态缓存，命中则直接跳转；未命中走慢路径（虚方法表查找）并更新缓存。

## Quickening 预留

> **Phase 2**：操作码空间 0xA8-0xFD 预留给运行时指令快化。编译器已根据 CFE 静态类型信息生成特化指令（如 `ADD_INT`、`ADD_DBL`），运行时 Quickening 留待 profiling 显示需要时再引入。
