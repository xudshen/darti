# POC-4: 端到端最小原型

> 方案来源: `docs/plans/2026-02-15-poc-implementation.md` Task 15–19

## 目标

组合 ISA 子集 + 最小编译器 + 分发循环，实现 .dill → 字节码 → 执行的全链路原型。

## 任务

### Task 15: ISA 定义与数据结构

**依赖:** Task 1
**产出文件:**
- `lib/src/runtime/opcodes.dart`
- `lib/src/runtime/value_stack.dart`
- `lib/src/runtime/ref_stack.dart`
- `lib/src/runtime/types.dart`
- `test/runtime/opcodes_test.dart`

**TDD 步骤:**
- [x] 写失败测试 `opcodes_test.dart`
- [x] 运行验证测试失败
- [x] 实现 `opcodes.dart`
- [x] 实现 `value_stack.dart`
- [x] 实现 `ref_stack.dart`
- [x] 实现 `types.dart`
- [x] 运行验证测试通过
- [x] **Commit**（ISA 定义 + 栈数据结构）

### Task 16: 分发循环

**依赖:** Task 15
**产出文件:**
- `lib/src/runtime/host_bindings.dart`
- `lib/src/runtime/dispatch_loop.dart`
- `test/runtime/dispatch_loop_test.dart`

**TDD 步骤:**
- [x] 写失败测试 `dispatch_loop_test.dart`
- [x] 运行验证测试失败
- [x] 实现 `host_bindings.dart`
- [x] 实现 `dispatch_loop.dart`
- [x] 运行验证测试通过

### Task 17: 手写字节码集成测试（Counter 程序）

**依赖:** Task 16
**产出文件:**
- `test/e2e/handwritten_bytecode_test.dart`

**TDD 步骤:**
- [x] 写集成测试 `handwritten_bytecode_test.dart`
- [x] 运行验证测试失败
- [x] 调试直到测试通过
- [x] **Commit**（分发循环 + 集成测试）

### Task 18: 最小编译器（Kernel → 字节码）

**依赖:** Task 16, POC-1（Task 3 KernelWalker）
**产出文件:**
- `lib/src/compiler/kernel_loader.dart`
- `lib/src/compiler/simple_compiler.dart`
- `lib/src/compiler/bytecode_emitter.dart`
- `test/e2e/compiler_e2e_test.dart`
- `test/fixtures/counter.dart`

**TDD 步骤:**
- [x] 写失败测试 `compiler_e2e_test.dart`
- [x] 运行验证测试失败
- [x] 实现 `kernel_loader.dart`
- [x] 实现 `simple_compiler.dart`
- [x] 实现 `bytecode_emitter.dart`
- [x] 运行验证测试通过

### Task 19: 更新导出与全部测试

**依赖:** Task 15, 16, 17, 18
**产出文件:**
- `lib/darti.dart`（修改，添加导出）

**TDD 步骤:**
- [x] 更新 `lib/darti.dart` 导出
- [x] 运行全部测试确认通过（10 tests, 0 issues）
- [x] **Commit**（编译器 + POC-4 完成）

## 关键发现

### 1. 必须使用 linked-platform .dill（不能 `--no-link-platform`）

`--no-link-platform` 编出的 .dill 中，dart:core 等平台库的 Reference 不绑定 AST 节点。
访问 `interfaceTarget`、`target` 等属性会抛 `Reference is not bound to an AST node`。

**正确做法：** 不加 `--no-link-platform`，编出 ~8MB 的 linked .dill：
- 所有 Reference 正确解析到 AST 节点
- 编译器可直接用 `x.interfaceTarget.enclosingClass` 等属性
- 无需 canonicalName fallback hack

### 2. callHost ABC 格式（设计文档已同步更新）

原始设计用 ABx（单参数），但 `list.add(element)` 需要传 receiver + argument。
改为 ABC 格式：A=baseReg, B=argCount, C=hostId，参数从 ref[A..A+B-1] 取。

### 3. CFE 会将 list literal 脱糖为 `_GrowableList._literal*`（设计文档已同步更新）

`<int>[1, 2, 3]` 在 Kernel AST 中变成 `StaticInvocation(_GrowableList._literal3(1, 2, 3))`。
编译器需检测 `_literal*` 模式并转为 `List.create` host binding 调用。

### 4. 编译器整体架构（POC 简化方案，正式版按设计走 LSRA）

3-pass 编译：
1. **注册 class** → ClassInfo + fieldOffsets
2. **编译方法** → FuncProto per method/constructor
3. **编译 top-level** → entry point

寄存器分配用简单线性分配器 `_Regs`，val/ref 两套寄存器独立编号。
`_R` 结果类型携带 `isVal` 标记，在 val↔ref 边界自动插入 box/unbox。
