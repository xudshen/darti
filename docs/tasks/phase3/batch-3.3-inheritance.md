# Batch 3.3: 继承与多态

## 概览

在 Batch 3.2 类基础之上实现继承体系：单继承 + super 调用（CALL_SUPER），方法重写与虚分发（CALL_VIRTUAL 继承链查找），抽象类与抽象方法，操作符重载（自定义类的 +, -, ==, [] 等运算符）。

**设计参考：** `docs/design/02-object-model.md`（继承链、superClassId、supertypeIds 集合构建）、`docs/design/03-execution-engine.md`（CALL_SUPER 编译时解析语义、CALL_VIRTUAL 慢速路径继承链查找）、`docs/design/05-compiler.md`（SuperMethodInvocation / SuperPropertyGet 编译、操作符重载编译、抽象类处理）

**依赖：** Batch 3.2（类基础必须就绪）

---

### Task 3.3.1: 单继承 + super 调用（CALL_SUPER）

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Modify: `lib/src/runtime/interpreter.dart`
- Modify: `lib/src/runtime/class_info.dart`
- Test: `test/e2e/inheritance_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch2 继承链（superClassId 链接父类，字段偏移需累加父类字段数）。Ch3"CALL_SUPER"语义（ABx 格式：编译时已解析目标 funcId，无需运行时查找。receiver 仍为当前 this 对象）。Ch5 SuperMethodInvocation / SuperPropertyGet 编译策略
2. **写测试** — 验证：
   - 简单继承：`class Animal { int legs; Animal(this.legs); } class Dog extends Animal { Dog() : super(4); }` → 字段继承正确
   - 继承字段访问：子类实例访问父类定义的字段
   - super 方法调用：`class A { int f() => 1; } class B extends A { int g() => super.f() + 10; }` → 结果 11
   - super 构造器调用：子类构造器中 `super(...)` 正确初始化父类字段
   - 多层继承：A → B → C，C 调用 super 访问 B 的方法
   - 字段偏移计算：父类有 2 个 int 字段 + 子类有 1 个 int 字段 → 子类字段偏移从 2 开始
3. **实现** —
   - 编译器 Pass 1 类遍历时，计算继承链字段偏移：子类 valueFieldCount = 父类 valueFieldCount + 自身 value 字段数，refFieldCount 类似。子类 FieldLayout 偏移以父类字段数为基准
   - 编译 SuperMethodInvocation → CALL_SUPER A, Bx（Bx = 编译时从 Kernel interfaceTarget 解析出的父类方法 funcId）
   - 编译 SuperPropertyGet → 类似，视 target 为 getter 或 field
   - 解释器 CALL_SUPER（0x54）：直接从 funcProto 表取 Bx 对应的 DarticFuncProto → 建立新帧（receiver = 当前 this）→ 执行
   - DarticClassInfo 构建时设置 superClassId，构建 supertypeIds（包含自身 classId + 所有祖先的 classId）
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/inheritance_test.dart`

---

### Task 3.3.2: 方法重写 + 虚分发

**产出文件：**
- Modify: `lib/src/runtime/class_info.dart`
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/e2e/override_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch3 CALL_VIRTUAL 慢速路径（方法表查找沿继承链向上搜索：先查当前 classId 的方法表，未找到则查 superClassId，直到根类）。Ch2 方法表构建策略（方案 A：运行时链式查找——每个类方法表只含自身方法；方案 B：编译时扁平化——子类方法表包含所有继承+重写的方法。根据设计文档确定具体方案）
2. **写测试** — 验证：
   - 方法重写：`class A { int f() => 1; } class B extends A { int f() => 2; }` → B 实例调用 f() 返回 2
   - 多态分发：`A obj = B(); obj.f();` → 运行时根据实际类型分发到 B.f()
   - 未重写方法继承：`class A { int g() => 10; } class B extends A {}` → B 实例调用 g() 返回 10
   - 多层重写：A.f → B.f → C.f，不同类型对象调用得到不同结果
   - 多态 IC 场景：同一 CALL_VIRTUAL 站点先调 A.f 再调 B.f → IC 未命中触发重新查找
3. **实现** —
   - 方法表策略选择（两种方案，根据设计文档确定）：方案 A（运行时链式查找）：每个类方法表只含自身方法，CALL_VIRTUAL 慢速路径沿 superClassId 链向上查找。方案 B（编译时扁平化）：子类方法表包含继承+重写的所有方法，查找 O(1)
   - 编译器构建继承链时检测方法重写（子类方法名匹配父类方法名）
   - CALL_VIRTUAL IC 机制不变：命中直接调用，未命中触发完整方法查找后更新缓存
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/override_test.dart`

---

### Task 3.3.3: 抽象类与抽象方法

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/e2e/abstract_class_test.dart`

**TDD 步骤：**

1. **读设计文档** — Kernel 中抽象类（Class.isAbstract）和抽象方法（Procedure.isAbstract, body 为 null）的表示。编译器需阻止抽象类直接实例化
2. **写测试** — 验证：
   - 抽象类不能直接实例化：编译错误或运行时异常
   - 子类实现抽象方法：`abstract class Shape { int area(); } class Circle extends Shape { int area() => 314; }` → 正常实例化和调用
   - 抽象类作为类型声明：`Shape s = Circle();` → 多态使用
   - 混合抽象与具体方法：抽象类中有具体方法实现 + 抽象方法声明
   - 未实现抽象方法的具体子类（CFE 已检查，编译器可信任）
3. **实现** —
   - 编译器标记抽象类（DarticClassInfo 中设 isAbstract 标志）
   - ConstructorInvocation 编译时检查：目标类为抽象类 → 如果是直接实例化则报错（Kernel 中 CFE 不会生成对抽象类的直接 ConstructorInvocation，但 factory 构造器可能返回子类）
   - 抽象方法不生成 DarticFuncProto（body 为 null），方法表中不包含抽象方法条目
   - 虚分发中如果最终解析到抽象方法（不应发生，CFE 已检查）→ 抛 AbstractClassInstantiationError
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/abstract_class_test.dart`

---

### Task 3.3.4: 操作符重载

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/e2e/operator_overload_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5 操作符重载编译策略。Kernel 中操作符方法名格式（如 `operator+` 在 Kernel 中为 Name('+')）。InstanceInvocation 的 interfaceTarget 指向操作符方法。Ch3"EQ_GENERIC"用于用户类 == 比较
2. **写测试** — 验证：
   - 算术操作符：`class Vec { int x; Vec(this.x); Vec operator+(Vec other) => Vec(x + other.x); }` → 正确相加
   - == 操作符：`class Id { int v; Id(this.v); bool operator==(Object other) => other is Id && v == other.v; }`
   - [] 和 []= 操作符：自定义索引访问
   - -（一元取反）
   - 比较操作符：<, >, <=, >=
   - Kernel 中操作符调用与普通方法调用的区别
3. **实现** —
   - 编译器在 InstanceInvocation 处理中：检查 interfaceTarget 的 enclosingClass。如果是用户自定义类（非 int/double/bool/String 等内置类型），则不走算术快速路径（ADD_INT 等），改为 CALL_VIRTUAL
   - 操作符方法编译为普通 DarticFuncProto，方法名为操作符符号（'+', '==', '[]' 等），放入类的方法表
   - == 操作符：编译器对用户类的 EqualsCall 生成 CALL_VIRTUAL 而非 EQ_INT/EQ_REF。注意 null 判断仍走 EqualsNull 快速路径
   - [] 和 []=：Kernel 中分别为 InstanceInvocation(name='[]') 和类似模式
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/operator_overload_test.dart`

---

## Commit

```
feat: support inheritance, override, and operator overloading
```

**提交文件：** 修改的 compiler.dart + interpreter.dart + class_info.dart + 全部新测试

## 核心发现

- **方法表策略**：采用编译时扁平化（方案 B）——子类方法表包含所有继承+重写的方法，IC miss 慢路径 O(1) 查找，无需运行时沿 superClassId 链遍历。实现方式：`_registerClass` 中对父类 `methods` 做 `putIfAbsent` 拷贝。
- **抽象类零额外代码**：CFE 保证具体子类实现所有抽象方法，抽象方法 body 为 null 不会被编译，加上方法表扁平化自动继承具体方法，无需额外编译器逻辑。
- **操作符重载自然路由**：用户自定义操作符（+、-、*、<、>、[]、unary- 等）在 Kernel 中为 InstanceInvocation，`_compileInstanceInvocation` 跳过 int/double 快速路径后自然走 `_compileVirtualCall`（CALL_VIRTUAL），无需特殊处理。唯一例外是 `operator==`：Kernel 使用 EqualsCall 节点，需检测 interfaceTarget 是否为用户自定义类并改走 CALL_VIRTUAL。
- **`_inferExprType` 必须覆盖 super 表达式**：SuperMethodInvocation 未在 `_inferExprType` 注册导致 `super.f() + 10` 的 int 快速路径被跳过，receiver 从 value 栈被误读为 ref 栈 → null receiver 错误。修复后所有 super 表达式节点均已覆盖。
- **`_classInfos` 闭包捕获**：`_createTypeChecker` 和 `_createCaster` 闭包通过引用捕获 `_classInfos`，在单模块编译模型下安全（执行前列表已完全填充），多模块支持时需重新评估。

## Batch 完成检查

- [x] 3.3.1 单继承 + super 调用
- [x] 3.3.2 方法重写 + 虚分发
- [x] 3.3.3 抽象类与抽象方法
- [x] 3.3.4 操作符重载
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test` 全部通过
- [ ] commit 已提交
- [ ] overview.md 已更新
- [x] code review 已完成
