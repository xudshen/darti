# Batch 1.5: 模块格式与运行时补全

## 概览

审查发现 Phase 1 遗漏了设计文档中明确要求的关键组件，本 Batch 补充：`.darb` 二进制模块格式、序列化/反序列化管线、异常处理表结构、StackKind 分类基础设施、IC 表元数据初始化。最终通过编译→序列化→反序列化→执行的 roundtrip 测试验证。

**设计参考：** Ch5"编译产物格式"节、Ch3"异常分发"节、Ch2"StackKind 分类"节、Ch1 IC 结构

**依赖：** Batch 1.1, 1.2, 1.3, 1.4

---

### Task 1.5.1: `.darb` 二进制模块格式

**产出文件：**
- Create: `lib/src/bytecode/format.dart`
- Test: `test/bytecode/format_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"编译产物格式"节，了解 `.darb` 文件结构：magic (0x44415242 "DARB") + version (UInt32) + checksum (CRC32) + 各 section
2. **写测试** — 验证：magic 常量正确（0x44415242 "DARB"）；version 编码规则；文件头定义常量（Section 标识、字节序约定等）；CRC32 校验和计算正确
3. **实现** — DarbFormat 常量类，定义 magic、version、section 标识等。CRC32 实现（或引用现有纯 Dart 实现）。二进制编码约定常量（小端字节序、UInt32 定宽、UTF-8 前缀长度字符串编码）
4. **运行** — `fvm dart analyze && fvm dart test test/bytecode/format_test.dart`

---

### Task 1.5.2: 模块序列化/反序列化管线

**产出文件：**
- Create: `lib/src/bytecode/serializer.dart`
- Create: `lib/src/bytecode/deserializer.dart`
- Test: `test/bytecode/serialization_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"编译产物格式"节中各 section 的二进制布局：绑定名称表 → 常量池 → 函数表 → 类表 → 全局变量表 → 入口点
2. **写测试** — 构造包含简单函数的 DarticModule → 序列化为 `Uint8List` → 反序列化为新的 DarticModule → 验证所有字段一致：
   - 常量池四分区内容一致（refs/ints/doubles/names）
   - DarticFuncProto 字段一致（bytecode/valueRegCount/refRegCount/paramCount）
   - 入口点 funcId 一致
   - 校验和验证正确
   - 损坏数据抛出明确错误（magic 不匹配、校验和失败）
3. **实现** — DarticSerializer（DarticModule → Uint8List）和 DarticDeserializer（Uint8List → DarticModule）。按 Ch5 格式规范的 section 顺序写入/读取。使用 `ByteData` 写入小端 UInt32
4. **运行** — `fvm dart analyze && fvm dart test test/bytecode/serialization_test.dart`

---

### Task 1.5.3: 异常处理表结构

**产出文件：**
- Create: `lib/src/runtime/exception_handler.dart`
- Modify: `lib/src/bytecode/module.dart` — DarticFuncProto 添加 exceptionTable 字段
- Modify: `lib/src/bytecode/serializer.dart` — 支持序列化 exceptionTable
- Modify: `lib/src/bytecode/deserializer.dart` — 支持反序列化 exceptionTable
- Test: `test/runtime/exception_handler_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch3"异常分发"节中的 ExceptionHandler 表结构（8 字段：startPC/endPC/handlerPC/catchType/valStackDP/refStackDP/exceptionReg/stackTraceReg）
2. **写测试** — 验证：ExceptionHandler 数据结构正确持有 8 个字段；处理器表按 (startPC, endPC) 排序；catchType=-1 表示 catch-all/finally；序列化/反序列化往返正确
3. **实现** — ExceptionHandler 数据类 + 在 DarticFuncProto 中集成 `List<ExceptionHandler>` + 更新序列化/反序列化支持。Phase 1 只定义结构，不实现 THROW/RETHROW 分发逻辑（Phase 2 Batch 2.3 实现）
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/exception_handler_test.dart`

---

### Task 1.5.4: StackKind 分类

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart` — 添加 StackKind 分类逻辑
- Test: `test/compiler/stack_kind_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch2"StackKind 分类"节和 Ch5"类型流分析"节。StackKind 决定变量/临时值存放值栈还是引用栈
2. **写测试** — 验证 `classifyType(DartType)` 的分类结果：
   - `int` → `StackKind.intVal`
   - `double` → `StackKind.doubleVal`
   - `bool` → `StackKind.intVal`（编码为 0/1）
   - `String` → `StackKind.ref`
   - `Object` / `Object?` → `StackKind.ref`
   - `dynamic` → `StackKind.ref`
   - `num` → `StackKind.ref`（编译期无法确定具体类型）
   - 被闭包捕获的 int/double/bool → 强制 `StackKind.ref`（Phase 3 再验证捕获场景）
3. **实现** — `classifyType` 函数（参考 Ch5 附录 StackKind 分类参考实现），集成到编译器的变量分析阶段。确保编译器根据 StackKind 选择正确的值栈/引用栈指令（如 int 参数用 valueStack 寄存器、String 参数用 refStack 寄存器）
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/stack_kind_test.dart`

---

### Task 1.5.5: IC 表元数据初始化

**产出文件：**
- Modify: `lib/src/bytecode/module.dart` — DarticFuncProto 确认 icTable 字段
- Modify: `lib/src/runtime/interpreter.dart` — 模块加载时 IC 表零填充
- Test: `test/runtime/ic_init_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch1 IC 结构（methodNameIndex/cachedClassId/cachedMethodOffset）和 Ch3"IC 失效"节
2. **写测试** — 验证：DarticFuncProto 加载后 icTable 中所有 ICEntry 的 cachedClassId = -1（未缓存状态）；loadModule 时 IC 表正确初始化；新模块加载导致全局 IC 重置（cachedClassId 全部置 -1）
3. **实现** — 确保 DarticFuncProto 的 icTable 在反序列化和模块加载时正确初始化为未缓存状态。Phase 1 不需要实际的 IC 命中/未命中逻辑（Phase 3 CALL_VIRTUAL 时实现），只需正确初始化
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/ic_init_test.dart`

---

### Task 1.5.6: 端到端测试 — 编译→序列化→反序列化→执行

**产出文件：**
- Test: `test/e2e/module_roundtrip_test.dart`

**TDD 步骤：**

1. **设计测试场景** — 验证完整管线：Dart 源码 → Kernel (.dill) → DarticCompiler 编译 → DarticSerializer 序列化为 .darb bytes → DarticDeserializer 反序列化 → DarticInterpreter 执行 → 结果正确
2. **写测试** — 验证：
   - `int add(int a, int b) => a + b; int main() => add(1, 2);` → roundtrip 后执行结果仍为 3
   - 常量池内容在 roundtrip 后完全一致
   - 字节码在 roundtrip 后逐字节一致
   - 修改序列化数据后校验和检测到篡改
3. **运行** — `fvm dart analyze && fvm dart test test/e2e/module_roundtrip_test.dart`

> 注意：此测试是 Phase 1 的最终里程碑验证。roundtrip 通过意味着整个最小管线（ISA + 对象模型 + 执行引擎 + 编译器 + 模块格式）完整闭合。

---

## Commit

```
feat: add module format, exception tables, StackKind, and IC initialization
```

**提交文件：** `lib/src/bytecode/format.dart`、`lib/src/bytecode/serializer.dart`、`lib/src/bytecode/deserializer.dart`、`lib/src/runtime/exception_handler.dart`、所有修改文件、所有新测试文件

## 核心发现

- **Magic 值选定 0x44415242** — ASCII "DARB"，hexdump 时可直接识别文件格式
- **ExceptionHandler 已前置定义在 module.dart** — 8 字段结构在 Batch 1.2 定义时即包含，不需要创建单独的 exception_handler.dart 文件
- **StackKind 三分类** — 从 `{value, ref}` 细化为 `{intVal, doubleVal, ref}`，`isValue` getter 统一判断值栈归属，使 double-view 和 int-view 的选择有了编译期依据
- **IC 表仅序列化 methodNameIndex** — cachedClassId/cachedMethodOffset 是运行时缓存状态，反序列化时重置为 -1/0 (uncached)
- **CRC32 采用 IEEE 802.3 标准** — 反射多项式 0xEDB88320，table-driven 实现，校验和覆盖 payload（不含 header）
- **ConstantPool.from() 构造** — 反序列化需要从已有数据重建常量池，新增命名构造函数 + read accessors (refs/ints/doubles/names)

## Batch 完成检查

- [x] 1.5.1 `.darb` 二进制模块格式
- [x] 1.5.2 模块序列化/反序列化
- [x] 1.5.3 异常处理表结构
- [x] 1.5.4 StackKind 分类
- [x] 1.5.5 IC 表元数据初始化
- [x] 1.5.6 端到端 roundtrip 测试
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test` 全部通过
- [x] commit 已提交
- [x] overview.md 已更新
- [x] **Phase 1 里程碑通过**
