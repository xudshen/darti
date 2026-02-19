# Batch 3.4: 作用域与名称解析

## 概览

完善作用域处理和名称解析：验证块级作用域变量遮蔽（Phase 2 已部分支持），实现多库编译与 import 解析（为 harness v1 导入 expect.dart 铺路），支持 this / super 引用在表达式中的使用。

**设计参考：** `docs/design/05-compiler.md`（作用域分析、多库编译、import 解析策略、this 引用）

**依赖：** Batch 3.2（this/super 引用需要类和实例方法就绪）

---

### Task 3.4.1: 块级作用域变量遮蔽

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`（如需修复）
- Test: `test/e2e/scope_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5 作用域分析节。Kernel 中 Block 节点自动创建新作用域，内部 VariableDeclaration 在 Block 结束时不再可见。Phase 2 的 RegisterAllocator 是否已正确处理嵌套 Block 的寄存器释放
2. **写测试** — 验证：
   - 同名变量在不同 Block 中独立：`{ int x = 1; } { int x = 2; }` → 不冲突
   - 内层 Block 遮蔽外层变量：`int x = 1; { int x = 2; /* x is 2 here */ } /* x is 1 here */`
   - 循环中的块作用域：每次迭代的局部变量独立
   - 函数参数与局部变量的作用域交互
   - 嵌套函数中的作用域（闭包捕获的变量 vs 局部变量）
   - if/else 分支中的变量作用域
3. **实现** — 验证并补全 Phase 2 的作用域实现。确保 Block 编译时 push 新作用域 → 编译体 → pop 作用域（释放寄存器）。检查 RegisterAllocator 在嵌套 Block 退出时是否正确回收寄存器。如果已正确实现，此 Task 主要是测试补全
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/scope_test.dart`

---

### Task 3.4.2: 库导入/导出与可见性（多文件编译）

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/e2e/import_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5 多库编译策略。Kernel 中 Component 包含多个 Library，每个 Library 有 importUri 和依赖列表。`fvm dart compile kernel` 已将所有依赖解析和合并到单个 `.dill` 文件中。编译器需遍历 Component 中所有相关 Library（不仅仅是 main library）
2. **写测试** — 验证：
   - 多文件编译：main.dart import helper.dart → 两个文件的函数/类均可访问
   - 库级可见性：`_private` 函数/变量在导入方不可见（Kernel 中 private 成员已由 CFE 解析，编译器无需额外处理）
   - 跨库类使用：在 A 库定义类，B 库导入并实例化
   - show / hide 组合子（Kernel 中已由 CFE 处理——只有可见的成员出现在依赖 Library 的引用中）
   - 多库中同名顶层变量/函数不冲突（各自 Library scope）
3. **实现** —
   - 编译器从 Kernel Component 中遍历所有非 `dart:*` Library（Platform 库延迟到 Phase 5 Bridge）
   - Pass 1 为所有 Library 的顶层函数/变量/类分配 funcId/globalIndex/classId
   - Pass 2 编译所有 Library 的函数/类体
   - 确保 Kernel 的跨库引用（interfaceTarget 指向其他 Library 的 Member）正确解析到已分配的 funcId/classId
   - 入口函数：Component.mainMethod 指向 main() 所在 Library
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/import_test.dart`

---

### Task 3.4.3: this / super 引用

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/e2e/this_super_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch2 帧布局（rsp+2 为 this/receiver 引用）。Ch5 ThisExpression 编译策略（直接从 refStack 的 this 槽位加载）。Kernel 中 ThisExpression 节点
2. **写测试** — 验证：
   - this 隐式引用：方法中访问自身字段 `this.x` → GET_FIELD 从 rsp+2
   - this 显式引用：`return this;` → 返回 rsp+2 的值
   - this 传递：`other.method(this)` → 将 this 作为参数传递
   - super 属性访问：`super.x`（SuperPropertyGet）→ 等同于 this.x（字段不会被重写）
   - super 方法调用（已在 3.3.1 覆盖，此处补充边界场景）
   - 方法内隐式 this：Kernel 中 `x` 在实例方法中可能被解析为 `this.x`（InstanceGet with ThisExpression as receiver）
3. **实现** —
   - ThisExpression：编译为 MOVE_REF result, rsp+2（从 this 槽位读取 receiver 到目标寄存器）
   - 注意编译器在实例方法/构造器中需标记"有 this"，以便 ThisExpression 能正确引用 rsp+2
   - SuperPropertyGet：编译 this 为 receiver → 然后根据 interfaceTarget 判断是 Field（GET_FIELD）还是 getter（CALL_SUPER）
   - SuperPropertySet：类似，编译 this 为 receiver → SET_FIELD 或 CALL_SUPER setter
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/this_super_test.dart`

---

## Commit

```
feat: support scoping, imports/exports, and name resolution
```

**提交文件：** 修改的 compiler.dart + 全部新测试

## 核心发现

- **Task 3.4.1**: 发现并修复 `_compileVariableDeclaration` 中的变量别名 bug。当初始化器为 `VariableGet`（如 `int b = a;`）时，`declareWithReg` 将新变量绑定到源变量的同一个寄存器，导致两个变量共享寄存器——对其中一个赋值会同时修改另一个。修复方法：当初始化器为 `VariableGet` 时，使用 `_scope.declare()` 分配独立寄存器并发射 MOVE 指令。33 个 e2e 测试覆盖：同名变量在兄弟块/嵌套块中独立、内层遮蔽外层变量恢复正确、循环变量独立、函数参数与局部变量交互、闭包与局部变量遮蔽、if/else 分支作用域、寄存器回收复用。另发现 LocalFunctionInvocation 作为二元表达式左操作数时结果丢失的 pre-existing bug（如 `f() + x`），已记录但不在此 Task 修复范围内。
- **Task 3.4.2**: 多库编译零代码改动即全部通过。编译器已在所有 Pass（1a/1b/1c/2a/2b/2c）中遍历 `_component.libraries` 的全部非平台库，Kernel CFE 将所有导入合并到单个 `.dill`，跨库引用通过 `interfaceTarget` 正确解析到已分配的 `funcId`/`classId`/`globalIndex`。新增 `compileDartMultiFile` / `compileAndRunMultiFile` 测试辅助函数，6 个 e2e 测试全部通过。
- **Task 3.4.3**: this/super 引用的编译实现完全正确，22 个 e2e 测试全部通过，无需修改生产代码。覆盖场景：this 隐式/显式引用、this 作为参数传递、this 在构造器中使用、super 字段读取（value/ref）、super getter/setter 调用、super 带参方法调用（value/ref/mixed args）、多级 super 链式调用（最多 4 层）、this 与 super 混合使用。

## Batch 完成检查

- [x] 3.4.1 块级作用域变量遮蔽
- [x] 3.4.2 库导入/导出与可见性
- [x] 3.4.3 this / super 引用
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test` 全部通过
- [x] commit 已提交
- [x] overview.md 已更新
- [x] code review 已完成
