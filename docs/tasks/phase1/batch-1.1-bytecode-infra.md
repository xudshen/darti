# Batch 1.1: 字节码基础设施 (Ch1)

## 概览

实现 Ch1 ISA 的基础数据结构：操作码枚举、五种编码格式的编解码工具、四分区常量池、WIDE 前缀支持、以及字节码模块容器。

**设计参考：** `docs/design/01-bytecode-isa.md`

**依赖：** 无

---

### Task 1.1.1: Opcode 枚举与编解码工具函数

**产出文件：**
- Create: `lib/src/bytecode/opcodes.dart`
- Create: `lib/src/bytecode/encoding.dart`
- Test: `test/bytecode/opcodes_test.dart`
- Test: `test/bytecode/encoding_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch1"操作码分类"节，了解 0x00-0xFF 的全部操作码分组与语义
2. **写 opcodes 测试** — 验证：所有操作码值唯一且在 0-255 范围内；按功能分组的边界值正确（如加载/存储 0x00-0x0F、整数算术 0x10-0x1F）；WIDE=0xFE、HALT=0xFF
3. **实现 opcodes** — 定义枚举或静态常量类，包含 Ch1 中全部 105 个已定义操作码 + 预留区间填充 ILLEGAL
4. **写 encoding 测试** — 验证五种编码格式（ABC、ABx、AsBx、Ax、sAx）的编解码往返正确性；excess-K 有符号编码的边界值（sBx: -32767~+32768，sAx: -8388607~+8388608）；操作数提取位运算（`instr & 0xFF`、`(instr >> 8) & 0xFF` 等）
5. **实现 encoding** — 参考 Ch1 附录的编解码参考实现，实现 `encodeABC`/`decodeA`/`decodeB`/`decodeC`/`encodeABx`/`decodeBx`/`encodeAsBx`/`decodesBx`/`encodeAx`/`decodeAx`/`encodesAx`/`decodesAx`
6. **运行** — `fvm dart analyze && fvm dart test test/bytecode/`

---

### Task 1.1.2: 常量池四分区数据结构

**产出文件：**
- Create: `lib/src/bytecode/constant_pool.dart`
- Test: `test/bytecode/constant_pool_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch1"四分区常量池"节，了解 refs/ints/doubles/names 四个分区各自的容器类型和对应指令
2. **写测试** — 验证：refs 分区能存取 `Object?`（String、null 等）；ints 分区使用 `Int64List`，零装箱存取 64 位整数；doubles 分区使用 `Float64List`，零装箱存取双精度浮点；names 分区使用 `List<String>`；各分区索引独立递增；去重逻辑（相同值只存一份，返回相同索引）
3. **实现 ConstantPool** — 四个独立列表/typed list + `addXxx`/`getXxx` 方法 + 去重映射
4. **运行** — `fvm dart analyze && fvm dart test test/bytecode/constant_pool_test.dart`

---

### Task 1.1.3: WIDE 前缀编解码

**产出文件：**
- Modify: `lib/src/bytecode/encoding.dart`
- Test: `test/bytecode/wide_encoding_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch1"WIDE 前缀"节，了解扩展字布局（ABC→A/B/C 各 16 位，ABx→A 16 位+Bx 32 位，等）和约束规则
2. **写测试** — 验证：ABC 格式 WIDE 编码后 A/B/C 各扩展到 16 位范围；ABx 格式 WIDE 编码后 A 16 位、Bx 32 位；AsBx 格式 WIDE 编码后有符号范围正确；Ax/sAx 格式 WIDE 编码后扩展到 48 位；WIDE 指令序列总长 3 个字；边界值往返正确
3. **实现** — 扩展 encoding.dart，添加 `encodeWideABC`/`decodeWideABC`/`encodeWideABx`/`decodeWideABx` 等函数，每组输出 3 个 uint32（前缀字 + 扩展字 + 原指令字）
4. **运行** — `fvm dart analyze && fvm dart test test/bytecode/`

---

### Task 1.1.4: 字节码模块容器

**产出文件：**
- Create: `lib/src/bytecode/module.dart`
- Test: `test/bytecode/module_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch1 IC 结构、Ch2 DarticFuncProto 字段列表（bytecode/valueRegCount/refRegCount/paramCount/icTable/exceptionTable/upvalueDescriptors）、Ch5 ".darticb 文件格式"节
2. **写测试** — 验证：DarticModule 能持有函数表（`List<DarticFuncProto>`）+ 常量池（ConstantPool）+ 入口点 funcId；DarticFuncProto 能持有 bytecode/valueRegCount/refRegCount/paramCount；ICEntry 结构能持有 methodNameIndex/cachedClassId/cachedMethodOffset（cachedClassId 初始为 -1）；能通过 funcId 索引检索 DarticFuncProto
3. **实现** — DarticModule、DarticFuncProto、ICEntry 数据类。暂不实现序列化（Batch 1.5），此处只做内存中的容器结构
4. **运行** — `fvm dart analyze && fvm dart test test/bytecode/module_test.dart`

---

## Commit

```
feat(bytecode): add ISA encoding, opcodes, and constant pool
```

**提交文件：** `lib/src/bytecode/` 全部新文件 + `test/bytecode/` 全部新文件

## 核心发现

- Dart enum 有内置 `index` 属性（声明顺序），不能用于自定义 opcode 值。改用 `code` 字段 + `byCode()` 静态查找表
- 常量池 doubles 分区的去重需要按 bit pattern 比较（`NaN != NaN`），通过 `ByteData.setFloat64/getInt64` 转换
- WIDE AsBx 的 excess-K 编码用 `K = 0x7FFFFFFF`（32 位），而标准 AsBx 用 `K = 0x7FFF`（16 位）——K 值随操作数宽度变化

## Batch 完成检查

- [x] 1.1.1 Opcode 枚举与编解码
- [x] 1.1.2 常量池四分区
- [x] 1.1.3 WIDE 前缀编解码
- [x] 1.1.4 字节码模块容器
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test test/bytecode/` 全部通过（111 tests）
- [ ] commit 已提交
- [ ] overview.md 已更新
