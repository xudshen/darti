# Batch 4.1: Mixin 与接口

## 概览

扩展类系统支持接口（implements）、mixin 组合（with/mixin/mixin class）和 Dart 3 类修饰符（sealed/base/final/interface）。Kernel CFE 已完成 mixin 线性化（生成匿名中间类）和类修饰符的编译时检查，dartic 编译器需要正确处理这些 Kernel 表示，确保运行时的 `is` 检查和方法分发正确。

**设计参考：** `docs/design/02-object-model.md`（DarticClassInfo.supertypeIds、方法表继承）、`docs/design/05-compiler.md`（类编译策略）、`docs/design/06-generics.md`（SuperTypeMap 多路径处理）

**依赖：** Phase 3 全部（特别是 Batch 3.2 类基础 + Batch 3.3 继承与多态）

---

### Task 4.1.1: implements 接口契约

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`（Pass 1c 接口处理）
- Modify: `lib/src/runtime/class_info.dart`（supertypeIds 扩展）
- Test: `test/e2e/interface_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch2"DarticClassInfo.supertypeIds"（传递闭包，含所有祖先 classId）。Kernel 中 `Class.implementedTypes` 列表提供 implements 声明的接口。目前 Pass 1c 仅通过 `supertype` 链构建 supertypeIds，需要扩展为同时包含 implementedTypes 的传递闭包
2. **写测试** — 验证：
   - 简单 implements：`abstract class Animal { String speak(); } class Dog implements Animal { String speak() => 'Woof'; }` → `Dog()` 的 `is Animal` 为 true
   - 多接口 implements：`class C implements A, B { ... }` → `is A` 和 `is B` 均为 true
   - 接口继承链：`abstract class A {} abstract class B implements A {} class C implements B {}` → `C()` 的 `is A` 为 true
   - 接口方法调用：通过接口类型引用调用实现方法
   - 抽象方法不生成字节码（仅用于类型检查）
3. **实现** —
   - Pass 1c 遍历 `Class.implementedTypes`，为每个 implementedType 查找 classId 并加入 supertypeIds
   - supertypeIds 构建改为传递闭包：对每个直接超类型（supertype + implementedTypes），递归加入其 supertypeIds
   - 抽象方法（`isAbstract=true`）在 Pass 2c 跳过编译，仅在 Pass 1c 注册占位（方法表中不生成 FuncProto）
   - Kernel 中 abstract class 实际上也可以有 constructors（factory），确保 abstract 标记不影响构造器编译
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/interface_test.dart`

---

### Task 4.1.2: mixin / mixin class / with

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`（mixin 线性化处理）
- Modify: `lib/src/runtime/class_info.dart`
- Test: `test/e2e/mixin_test.dart`

**TDD 步骤：**

1. **读设计文档** — Kernel 的 mixin 表示：`class C extends A with M1, M2` 生成匿名中间类 `_C&A&M1`（`isAnonymousMixin=true, supertype=A, mixedInType=M1`）和 `_C&A&M1&M2`（`supertype=_C&A&M1, mixedInType=M2`），C 继承最终的中间类。`mixin M on S { ... }` 在 Kernel 中为 `Class(isMixinDeclaration=true)`。`mixin class MC { ... }` 为 `Class(isMixinClass=true)`。Ch2 方法表继承策略（子类方法表包含所有继承+覆写方法）
2. **写测试** — 验证：
   - 简单 mixin：`mixin M { int get value => 42; } class C with M {}` → `C().value == 42`
   - mixin 方法覆写：`mixin M { int f() => 1; } class C with M { int f() => 2; }` → `C().f() == 2`
   - 多重 mixin：`class C extends A with M1, M2 {}` → 线性化顺序：M2 覆盖 M1 的同名方法
   - mixin class：`mixin class MC { int f() => 1; } class C with MC {}` 和 `class D extends MC {}` 均可用
   - `mixin M on S` 约束：M 只能 with 在 S 或 S 的子类上（Kernel 中 `Class.onClause` / supertype 约束）
   - mixin 中的 super 调用：`mixin M on A { int f() => super.f() + 1; }` → 正确分发到 A 的方法
   - mixin 字段：`mixin M { int x = 0; }` → 字段布局正确合并到使用类
   - `is` 检查包含 mixin 类型：`C() is M` → true
3. **实现** —
   - Pass 1c 识别 `isAnonymousMixin` 类：为其分配 classId，从 `mixedInType` 引用的 mixin 类中复制方法和字段声明到中间类的方法表/字段表
   - mixin 方法复制策略：遍历 mixin 的 procedures/fields → 为中间类生成对应条目。如果子类已有同名方法则跳过（覆写优先）
   - supertypeIds 扩展：中间类的 supertypeIds 包含 mixin 的 classId 及其 supertypeIds
   - `isMixinDeclaration` 类：仅注册 classId 和方法表（不直接实例化），其方法供匿名中间类复制使用
   - super 调用在 mixin 中：Kernel 的 SuperMethodInvocation 引用已解析到线性化链中正确的目标，编译器直接使用 CALL_SUPER 即可
   - mixin 字段：合并到中间类的 refFieldCount/valueFieldCount，字段偏移基于继承链计算
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/mixin_test.dart`

---

### Task 4.1.3: sealed / base / final / interface 类修饰符

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`（修饰符识别）
- Test: `test/e2e/class_modifier_test.dart`

**TDD 步骤：**

1. **读设计文档** — Dart 3 类修饰符在 Kernel 中的表示：`Class.isSealed`、`Class.isBase`、`Class.isFinal`、`Class.isInterface`、`Class.isMixinClass`。这些修饰符的编译时限制由 Dart CFE 强制执行（跨库 extends/implements 限制），dartic 编译器主要确保正确编译这些类并在运行时支持正确的 `is` 检查
2. **写测试** — 验证：
   - sealed class：`sealed class Shape {} class Circle extends Shape {}` → `Circle() is Shape` 为 true
   - base class：`base class Base {} class Sub extends Base {}` → 正确继承
   - final class：`final class Config { int value; Config(this.value); }` → 实例化和字段访问正常
   - interface class：`interface class Printable { void print(); } class Doc implements Printable { void print() {} }` → 接口实现正确
   - abstract + 修饰符组合：`abstract base class AbstractBase {}` → 不能直接实例化但可继承
   - 负面测试：co19 中大量 Class-modifiers 负面测试验证 CFE 正确拒绝违规用法（这些由 isNegative 机制处理，编译失败即 pass）
3. **实现** —
   - 编译器 Pass 1c 读取 Kernel Class 的修饰符标记（isSealed/isBase/isFinal/isInterface），存储到 DarticClassInfo（可选：新增 classModifiers 字段或使用 bitfield）
   - sealed class 的子类枚举：目前不需要运行时 exhaustiveness 检查（switch exhaustiveness 由 CFE 在编译时验证），运行时仅需 `is` 检查正确
   - 确保修饰符不影响现有编译流程：这些类的实例化、方法调用、字段访问均走已有路径
   - 关注点：co19 Class-modifiers 测试中约 60% 为负面测试（验证编译错误），仅 ~40% 为正面测试（验证运行时行为）
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/class_modifier_test.dart`

---

## Commit

```
feat: support interfaces, mixins, and class modifiers
```

**提交文件：** 修改的 compiler.dart + class_info.dart + 全部新测试

## 核心发现

_(执行时填写：mixin 线性化在 Kernel 中的实际表示、匿名中间类的方法复制策略、super 调用在 mixin 中的解析方式等)_

## Batch 完成检查

- [ ] 4.1.1 implements 接口契约
- [ ] 4.1.2 mixin / mixin class / with
- [ ] 4.1.3 sealed / base / final / interface 类修饰符
- [ ] `fvm dart analyze` 零警告
- [ ] `fvm dart test` 全部通过
- [ ] commit 已提交
- [ ] overview.md 已更新
- [ ] code review 已完成
