# Batch 1.2: 三栈与对象模型 (Ch2)

## 概览

实现 Ch2 定义的核心运行时数据结构：ValueStack（共享 ByteBuffer 双视图）、RefStack（引用栈）、CallStack（调用栈 + DarticFrame）、以及对象模型基础（DarticObject / DarticClassInfo）。

**设计参考：** `docs/design/02-object-model.md`

**依赖：** Batch 1.1（Opcode 枚举、DarticFuncProto 定义）

---

### Task 1.2.1: ValueStack（共享 ByteBuffer 双视图）

**产出文件：**
- Create: `lib/src/runtime/value_stack.dart`
- Test: `test/runtime/value_stack_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch2"三栈内存模型"节 ValueStack 段，了解底层为 `Uint8List` 缓冲区 + `Int64List`（intView）和 `Float64List`（doubleView）两个视图共享同一内存
2. **写测试** — 验证：intView 写入后能正确读取 64 位整数；doubleView 写入后能正确读取双精度浮点；sp（栈顶指针）正确递增/递减；预分配容量 10240 槽（可配置）；不同槽位互不干扰；边界值测试（Int64 最大最小值、double 特殊值 NaN/Infinity）
3. **实现 ValueStack** — `Uint8List` 缓冲区 + `Int64List.view()` + `Float64List.view()` + sp 指针 + `pushInt`/`popInt`/`readInt`/`writeInt`/`readDouble`/`writeDouble` 等方法。每槽 8 字节
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/value_stack_test.dart`

---

### Task 1.2.2: RefStack（引用栈）

**产出文件：**
- Create: `lib/src/runtime/ref_stack.dart`
- Test: `test/runtime/ref_stack_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch2 RefStack 段，了解 `List<Object?>` 存储 + sp 指针 + 弹出置 null 不变式
2. **写测试** — 验证：能存取各种引用类型（String、DarticObject、null 等）；sp 正确维护；弹出后槽位被置 null（GC 安全不变式）；预分配容量 5120 槽（可配置）；连续 push/pop 往返正确
3. **实现 RefStack** — `List<Object?>` + sp 指针 + `push`/`pop`/`read`/`write` 方法。pop 时 `slots[sp] = null`
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/ref_stack_test.dart`

---

### Task 1.2.3: CallStack + DarticFrame

**产出文件：**
- Create: `lib/src/runtime/call_stack.dart`
- Create: `lib/src/runtime/frame.dart`
- Test: `test/runtime/call_stack_test.dart`
- Test: `test/runtime/frame_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch2"CallStack"段（`Uint32List`，每帧 6 字段：funcId/returnPC/savedFP/savedVSP/savedRSP/resultReg）和"执行帧——DarticFrame"段（堆对象，22 字段）
2. **写 CallStack 测试** — 验证：压帧后 fp 正确偏移（每帧 6 个 uint32）；6 个字段的读写正确（funcId/returnPC/savedFP/savedVSP/savedRSP/resultReg）；弹帧恢复到前一帧；预分配 3072 uint32（512 帧 x 6）；HOST_BOUNDARY 哨兵帧检测
3. **写 DarticFrame 测试** — 验证：基础字段（funcProto/pc/upvalues）可设置；栈快照字段（savedVBase/savedRBase/savedVSP/savedRSP/savedValueSlots/savedRefSlots）初始值正确。Phase 1 只需基础和栈快照字段，异步/生成器字段留空
4. **实现 CallStack** — `Uint32List(3072)` + fp 指针 + `pushFrame`/`popFrame`/`readField`/`isHostBoundary` 方法。常量定义帧字段偏移
5. **实现 DarticFrame** — 数据类，Phase 1 只需基础字段 + 栈快照字段。异步字段标注 TODO Phase 6
6. **运行** — `fvm dart analyze && fvm dart test test/runtime/`

---

### Task 1.2.4: DarticObject / DarticClassInfo 基础结构

**产出文件：**
- Create: `lib/src/runtime/object.dart`
- Create: `lib/src/runtime/class_info.dart`
- Test: `test/runtime/object_test.dart`
- Test: `test/runtime/class_info_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch2"对象模型"节（DarticObject：classId/runtimeType/refFields/valueFields）和"类元数据"节（DarticClassInfo：classId/name/superClassId/refFieldCount/valueFieldCount/methods/fields/supertypeIds）
2. **写 DarticObject 测试** — 验证：构造时根据 DarticClassInfo 的 refFieldCount/valueFieldCount 分配字段存储；无引用字段时 refFields 为空 List 单例；无值字段时 valueFields 为空 Int64List 单例；字段读写通过偏移索引（`refFields[i]`/`valueFields[i]`）
3. **写 DarticClassInfo 测试** — 验证：classId 唯一性；MethodTable 结构（Phase 1 简化为 `Map<int, DarticFuncProto>`，Phase 3 再实现双策略）；FieldLayout 结构（offset + StackKind）；supertypeIds 集合包含自身和所有祖先 classId
4. **实现** — DarticObject（classId + refFields/valueFields + 空单例共享）、DarticClassInfo（类元数据 + MethodTable + FieldLayout + supertypeIds）、StackKind 枚举（intVal/doubleVal/ref）
5. **运行** — `fvm dart analyze && fvm dart test test/runtime/`

---

## Commit

```
feat(runtime): add three-stack model and object representation
```

**提交文件：** `lib/src/runtime/` 全部新文件 + `test/runtime/` 全部新文件

## 核心发现

- `Int64List.view()` / `Float64List.view()` 共享同一 `Uint8List.buffer`，每槽 8 字节自动对齐——无需手动处理对齐问题
- DarticObject 空字段单例：`List<Object?>.unmodifiable([])` 用于 refFields，`Int64List(0)` 用于 valueFields。所有零字段实例共享同一对象
- CallStack fp 设计：fp 指向当前帧"之后"（即 base + frameSize），读当前帧用 `fp - frameSize + offset`。这样 pushFrame 只需写入再前进，popFrame 只需读 savedFP
- DarticFrame Phase 1 只实现 9 个基础+栈快照字段（共 22 个中的 9 个），异步/生成器字段留 TODO

## Batch 完成检查

- [x] 1.2.1 ValueStack
- [x] 1.2.2 RefStack
- [x] 1.2.3 CallStack + DarticFrame
- [x] 1.2.4 DarticObject / DarticClassInfo
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test test/runtime/` 全部通过（73 tests）
- [x] commit 已提交 (`757b160`)
- [x] overview.md 已更新
