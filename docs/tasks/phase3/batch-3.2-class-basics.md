# Batch 3.2: 类基础

## 概览

实现类的核心功能：类定义编译（DarticClassInfo 构建 + 字段布局计算 + 方法表构建），实例化（NEW_INSTANCE），字段访问（GET_FIELD_REF/VAL, SET_FIELD_REF/VAL），实例方法调用（CALL_VIRTUAL + IC 缓存），构造器（默认/命名/重定向/工厂），静态成员，getter/setter。这是 Phase 3 最大的 Batch，为后续继承、多态和 co19 harness v1 奠定基础。

**设计参考：** `docs/design/02-object-model.md`（DarticObject、DarticClassInfo、FieldLayout、方法表结构、构造器策略）、`docs/design/03-execution-engine.md`（NEW_INSTANCE、GET_FIELD_\*、SET_FIELD_\*、CALL_VIRTUAL、IC 缓存语义）、`docs/design/05-compiler.md`（类编译、构造器编译、字段偏移计算）

**依赖：** Batch 3.1（构造器可能有可选参数/命名参数）

---

### Task 3.2.1: 类定义与实例化（NEW_INSTANCE）

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`（类编译 Pass）
- Modify: `lib/src/runtime/interpreter.dart`（NEW_INSTANCE opcode）
- Modify: `lib/src/bytecode/module.dart`（类注册表）
- Modify: `lib/src/runtime/class_info.dart`（方法表构建、字段布局计算）
- Test: `test/compiler/class_compile_test.dart`
- Test: `test/e2e/class_basic_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch2"DarticClassInfo"结构（classId, name, superClassId, refFieldCount, valueFieldCount, methods, fields, supertypeIds）。Ch2"DarticObject"结构（classId, refFields, valueFields）。Ch5"类编译"策略（遍历 Class 节点，提取字段/方法/构造器，构建 DarticClassInfo）。Ch3"NEW_INSTANCE"语义（分配 DarticObject，初始化字段为默认值）
2. **写测试** — 验证：
   - 编译简单类定义：`class Point { int x; int y; Point(this.x, this.y); }`
   - DarticModule 包含正确的 DarticClassInfo（字段数、方法数）
   - NEW_INSTANCE 创建对象，refFields/valueFields 大小正确
   - 多个类共存于同一模块
   - 端到端：创建对象并通过构造器初始化字段
3. **实现** —
   - 编译器 Pass 1 增加类遍历：对每个 Kernel Class 节点分配 classId，收集字段声明（区分 ref/value 类型），计算 FieldLayout（name → offset + StackKind），收集方法/构造器分配 funcId
   - DarticModule 增加 classes 列表（`List<DarticClassInfo>`）
   - 编译 ConstructorInvocation：发射 NEW_INSTANCE A, classId → 编译参数 → MOVE receiver → CALL_STATIC constructorFuncId（构造器作为普通函数，receiver 为新对象）
   - 解释器实现 NEW_INSTANCE（0x64）：从模块查找 DarticClassInfo，分配 DarticObject（valueFields 大小为 classInfo.valueFieldCount, refFields 大小为 classInfo.refFieldCount），存入 refStack[A]
4. **运行** — `fvm dart analyze && fvm dart test test/compiler/class_compile_test.dart test/e2e/class_basic_test.dart`

---

### Task 3.2.2: 字段访问（GET_FIELD / SET_FIELD）

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Modify: `lib/src/runtime/interpreter.dart`
- Test: `test/e2e/field_access_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch3"GET_FIELD_REF / GET_FIELD_VAL / SET_FIELD_REF / SET_FIELD_VAL"操作码语义（直接偏移访问，O(1)）。Ch2"FieldLayout"结构（offset + StackKind）。Ch5 中 InstanceGet / InstanceSet 的编译策略（Kernel interfaceTarget 指向字段 Member，编译器查找 FieldLayout 获取偏移量和 StackKind）
2. **写测试** — 验证：
   - 读取 ref 类型字段：`obj.name`（String 字段）→ GET_FIELD_REF
   - 读取 value 类型字段：`obj.x`（int 字段）→ GET_FIELD_VAL
   - 写入字段：`obj.x = 42` → SET_FIELD_VAL
   - 链式字段访问：`obj.inner.value`
   - 端到端：创建对象 → 设置字段 → 读取字段 → 验证值正确
   - null 对象字段访问应抛异常
3. **实现** —
   - 编译 InstanceGet：编译 receiver 到 ref 寄存器 → 从 Kernel interfaceTarget 查找字段的 FieldLayout → 根据 StackKind 发射 GET_FIELD_REF 或 GET_FIELD_VAL（A=目标寄存器, B=receiver 寄存器, offset 作为立即数）
   - 编译 InstanceSet：编译 receiver → 编译 value → 发射 SET_FIELD_REF 或 SET_FIELD_VAL
   - 解释器实现 GET_FIELD_REF（0x60）：从 refStack[B] 取 DarticObject，读 refFields[offset]。GET_FIELD_VAL（0x62）：读 valueFields[offset]。SET_FIELD_REF（0x61）/SET_FIELD_VAL（0x63）类似
   - null receiver 检查：GET_FIELD_* 前需检查 receiver 非 null
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/field_access_test.dart`

---

### Task 3.2.3: 实例方法调用（CALL_VIRTUAL + IC）

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Modify: `lib/src/runtime/interpreter.dart`
- Modify: `lib/src/runtime/class_info.dart`（方法查找）
- Test: `test/runtime/virtual_dispatch_test.dart`
- Test: `test/e2e/method_call_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch3"CALL_VIRTUAL"节（ABC 格式：A=result, B=receiver, C=IC 索引。IC 快速路径：比较 classId → 直接调用。慢速路径：MethodTable 查找 → 更新缓存）。Ch2"方法表"结构（<=8 方法 sorted list + binary search；>8 方法 HashMap）。Ch5 中 InstanceInvocation 编译为 CALL_VIRTUAL 的策略
2. **写解释器测试** — 手工构造包含 DarticClassInfo + 方法表的模块，验证：
   - CALL_VIRTUAL IC 命中：第一次调用走慢速路径（查找方法表），第二次命中 IC 缓存
   - IC 未命中（多态场景）：不同 classId 的对象调用同名方法
   - 方法查找失败：调用不存在的方法 → 抛 NoSuchMethodError
   - receiver 为 null → 抛异常
3. **写编译器测试** — 端到端验证：
   - 简单方法调用：`class Foo { int bar() => 42; } int main() { var f = Foo(); return f.bar(); }` → 结果 42
   - 带参数的方法：`class Calc { int add(int a, int b) => a + b; }`
   - 方法返回不同类型（int / String / bool）
   - 同一对象多次方法调用（IC 命中率验证）
4. **实现** —
   - 编译器将一般的 InstanceInvocation（非算术运算符快速路径）编译为 CALL_VIRTUAL：编译 receiver → 编译参数 → 发射 CALL_VIRTUAL A, B, C（C 为 IC 表索引，编译时为每个 CALL_VIRTUAL 分配一个 ICEntry，记录 methodNameIndex）
   - IC 表条目记录 methodNameIndex（常量池名称索引），运行时缓存 cachedClassId + cachedMethodOffset
   - 解释器 CALL_VIRTUAL（0x53）：取 receiver.classId → 比较 IC.cachedClassId → 命中则直接跳到 cached funcProto → 未命中则从 DarticClassInfo.methods 查找 → 更新 IC → 建立新帧（receiver 放 rsp+2）→ 执行方法体
   - DarticClassInfo.methods 查找：按 methodNameIndex 在方法表中查找，返回 DarticFuncProto
5. **运行** — `fvm dart analyze && fvm dart test test/runtime/virtual_dispatch_test.dart test/e2e/method_call_test.dart`

---

### Task 3.2.4: 构造器（默认 / 命名 / 重定向 / 工厂）

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/e2e/constructor_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch2"构造器策略"（初始化链扁平化：字段初始化器 → super 构造器 → 构造器体，编译为单个 DarticFuncProto）。Ch5"构造器编译"（Kernel Constructor 节点结构：initializers 列表 + function body）。重定向构造器（`this(...)`）编译为 CALL 到目标构造器。工厂构造器是 Procedure（isFactory=true），编译为普通 static 函数
2. **写测试** — 验证：
   - 默认构造器：`class Foo { int x; Foo(this.x); }` → 字段正确初始化
   - 命名构造器：`class Foo { int x; Foo.fromInt(this.x); }` → 通过 `Foo.fromInt(42)` 调用
   - 初始化列表：`class Foo { int x; int y; Foo(int v) : x = v, y = v * 2; }`
   - 重定向构造器：`class Foo { int x; Foo(this.x); Foo.zero() : this(0); }`
   - 工厂构造器：`class Foo { int x; Foo._(this.x); factory Foo(int x) => Foo._(x); }`
   - `this.x` 语法糖：Kernel 中 this.x 参数的 FieldInitializer 表示
   - 构造器参数类型混合（int + String + 可选参数）
3. **实现** —
   - 编译 Constructor 为 DarticFuncProto：receiver 在 rsp+2（this 引用）。编译初始化列表（FieldInitializer → SET_FIELD、SuperInitializer → CALL_STATIC super 构造器、RedirectingInitializer → CALL_STATIC 目标构造器）→ 编译构造器体
   - 编译 ConstructorInvocation（在调用端）：NEW_INSTANCE → 编译参数 → MOVE receiver → CALL_STATIC constructorFuncId
   - 工厂构造器：Kernel 中为 Procedure（isFactory=true），编译为普通静态函数，调用处直接 CALL_STATIC（无 NEW_INSTANCE）
   - `this.x` 参数：Kernel 的 FieldInitializer(field, value=VariableGet(param))，编译为 SET_FIELD
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/constructor_test.dart`

---

### Task 3.2.5: 静态方法与静态字段

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/e2e/static_members_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5"静态字段与顶层变量"节（静态字段复用全局变量机制：分配 globalIndex，LOAD_GLOBAL/STORE_GLOBAL 访问）。静态方法编译为普通 DarticFuncProto + CALL_STATIC
2. **写测试** — 验证：
   - 静态方法调用：`class Math { static int square(int x) => x * x; } int main() => Math.square(5);` → 25
   - 静态字段读写：`class Counter { static int count = 0; static void increment() { count += 1; } }`
   - 静态字段惰性初始化（复用全局变量的初始化器机制）
   - 同一类中静态方法访问静态字段
   - 不同类的静态方法共存
3. **实现** —
   - 静态方法：编译为 DarticFuncProto（无 receiver），调用处 StaticInvocation → CALL_STATIC（与顶层函数相同）
   - 静态字段：编译器 Pass 1 为每个静态字段分配 globalIndex（与顶层变量共享全局变量表）。StaticGet/StaticSet → LOAD_GLOBAL/STORE_GLOBAL（与 Phase 2 的顶层变量处理逻辑合并）
   - Kernel 中静态成员的 Class.procedures（isStatic=true）和 Class.fields（isStatic=true）遍历
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/static_members_test.dart`

---

### Task 3.2.6: getter / setter

**产出文件：**
- Modify: `lib/src/compiler/compiler.dart`
- Test: `test/e2e/getter_setter_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch5 getter/setter 编译策略。Kernel 中 getter 为 Procedure（isGetter=true, kind=ProcedureKind.Getter），setter 为 Procedure（isSetter=true）。调用端 InstanceGet/InstanceSet 的 interfaceTarget 可能指向 getter/setter Procedure 而非 Field
2. **写测试** — 验证：
   - 实例 getter：`class Rect { int w; int h; Rect(this.w, this.h); int get area => w * h; }` → `rect.area` 返回正确值
   - 实例 setter：`class Box { int _v = 0; set value(int v) { _v = v; } int get value => _v; }`
   - getter/setter 与字段混合：同一类中既有字段又有 getter/setter
   - 静态 getter/setter
   - getter 无参数，setter 有一个参数的调用约定
3. **实现** —
   - getter 编译为 DarticFuncProto（无参数，有 receiver）。调用端：InstanceGet 的 interfaceTarget 是 getter Procedure 时，发射 CALL_VIRTUAL（而非 GET_FIELD）
   - setter 编译为 DarticFuncProto（一个参数 + receiver）。调用端：InstanceSet 的 interfaceTarget 是 setter Procedure 时，发射 CALL_VIRTUAL
   - 编译器需区分 InstanceGet/InstanceSet 的 target 是 Field 还是 Procedure：Field → GET_FIELD/SET_FIELD，Procedure → CALL_VIRTUAL
   - 静态 getter/setter：编译为无 receiver 的函数，调用处 StaticGet/StaticSet → CALL_STATIC
4. **运行** — `fvm dart analyze && fvm dart test test/e2e/getter_setter_test.dart`

---

## Commit

```
feat: support class instantiation, fields, methods, and constructors
```

**提交文件：** 修改的 compiler.dart + interpreter.dart + class_info.dart + module.dart + 全部新测试

## 核心发现

1. **方法表陈旧引用 (Task 3.2.3)**：两遍编译在 Pass 1c 创建占位 FuncProto 并存入 `DarticClassInfo.methods`。Pass 2c 编译出真正的 FuncProto 替换 `_functions[funcId]`，但方法表 Map 仍持有旧占位对象的引用。解决方案：在 Pass 2c 后增加刷新循环，将所有方法表条目更新为已编译的 FuncProto。

2. **compileAndRun 测试模式**：`compileAndRun` 读取 `valueStack.readInt(0)`，只有结果恰好落在 v0 时才正确。构造器调用和中间计算会偏移结果寄存器。解决方案：将逻辑包装在辅助函数中 `int _test() { ... } int main() => _test();`，通过 RETURN_VAL → CALL_STATIC 将结果路由到 v0。

3. **CALL_VIRTUAL receiver 处理**：解释器自动将 receiver 放置在 callee 的 rsp+2（不同于构造器调用中 CALL_STATIC 需要显式 MOVE）。减少了每次虚调用的指令数。

4. **IC 表是逐函数状态**：编译器中的 `_icEntries` 列表在函数编译开始时清空，闭包编译时通过 `_CompilationContext` 保存/恢复。

5. **Setter 命名约定 (Task 3.2.6)**：Setter 在方法表中使用 "name=" 命名（如 `value=`），以区分同名的 getter/方法。IC 条目使用相同约定。

6. **工厂构造器透明处理**：Kernel 将其表示为 `Procedure(isFactory=true, isStatic=true)`，作为普通静态函数编译。调用端使用 `StaticInvocation`，无需特殊处理。

7. **重定向构造器 (Task 3.2.4)**：编译为 CALL_STATIC 到目标构造器，传递 `this`（rsp+2）和重定向参数。`RedirectingInitializer` 节点提供目标构造器引用和参数。

## Batch 完成检查

- [x] 3.2.1 类定义与实例化
- [x] 3.2.2 字段访问
- [x] 3.2.3 实例方法调用 (CALL_VIRTUAL + IC)
- [x] 3.2.4 构造器
- [x] 3.2.5 静态方法与静态字段
- [x] 3.2.6 getter / setter
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test` 全部通过 (996 tests)
- [x] commit 已提交 (c38e83a, e760b8a)
- [x] overview.md 已更新
- [x] code review 已完成 — 3 issues fixed (null receiver check, IC naming, error message)
