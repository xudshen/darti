# Batch 5.3: 集合字面量、字符串插值与回调代理

## 概览

实现集合字面量指令（CREATE_LIST/MAP/SET）、字符串插值（STRING_INTERP）、DarticCallbackProxy（回调代理）和 DarticProxyManager + DarticProxy（对象代理）。集合字面量和字符串插值是 co19 测试中广泛使用的基础特性；回调代理使 List.forEach/map/where 等高阶方法可用。

**设计参考：** `docs/design/02-object-model.md`（CREATE_LIST/MAP/SET 创建 VM 原生对象）、`docs/design/01-bytecode-isa.md`（0x90-0x93 集合指令、0x98 STRING_INTERP）、`docs/design/04-interop.md`（DarticCallbackProxy proxy0-3、DarticProxyManager 双向 Expando 缓存、DarticProxy 通用代理）

**依赖：** Batch 5.1-5.2（CALL_HOST 管线 + dart:core Bridge）

---

### Task 5.3.1: CREATE_LIST/MAP/SET 解释器 + 编译器

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`（CREATE_LIST, CREATE_MAP, CREATE_SET case）
- Modify: `lib/src/compiler/compiler_expressions.dart`（ListLiteral, MapLiteral, SetLiteral 编译）
- Test: `test/runtime/collection_create_test.dart`
- Test: `test/e2e/collection_literal_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch2"基本类型与集合的运行时表示"：CREATE_LIST/MAP/SET 创建 VM 原生对象（List/Map/Set），泛型参数为 dynamic（解释器无法创建参数化 VM 集合）。Ch1 指令编码：CREATE_LIST A, B, C（A=目标 ref 寄存器，B=起始元素 ref 寄存器，C=元素个数）；CREATE_MAP 类似但元素是 key-value 交替排列；CREATE_SET 与 LIST 类似。Kernel 中 ListLiteral/MapLiteral/SetLiteral 的 AST 结构
2. **写测试** —
   - 手工字节码测试：CREATE_LIST 从 ref 栈连续区域读取元素创建 List
   - 手工字节码测试：CREATE_MAP 从 ref 栈交替读取 key/value 创建 Map
   - 手工字节码测试：CREATE_SET 创建 Set
   - 空集合：`[]` / `{}` / `<int>{}` 创建空 List/Map/Set
   - 端到端：`var list = [1, 2, 3]; return list.length;` → 3
   - 端到端：`var map = {'a': 1, 'b': 2}; return map['a'];` → 1
   - 端到端：`var set = {1, 2, 3}; return set.contains(2);` → true
   - 端到端：嵌套集合 `[[1,2],[3,4]]`、`{'a': [1,2]}`
   - 端到端：集合元素含表达式 `[1+2, 3*4]`
   - 端到端：常量集合 `const [1, 2, 3]`
3. **实现** —
   - 解释器 CREATE_LIST (0x90)：从 refStack[rBase+B] 开始读取 C 个元素 → 创建 `List<Object?>.from(...)` → 存入 refStack[rBase+A]
   - 解释器 CREATE_MAP (0x91)：从 refStack 读取 C 对 key/value → 创建 `Map<Object?, Object?>` → 存入 refStack
   - 解释器 CREATE_SET (0x92)：从 refStack 读取 C 个元素 → 创建 `Set<Object?>` → 存入 refStack
   - 编译器 ListLiteral：编译每个元素表达式到连续 ref 寄存器（值类型需 BOX）→ emit CREATE_LIST
   - 编译器 MapLiteral：编译 key/value 交替到连续 ref 寄存器 → emit CREATE_MAP
   - 编译器 SetLiteral：编译每个元素 → emit CREATE_SET
   - 编译器需区分 Map 和 Set 字面量——Kernel 中 SetLiteral 是独立节点，不与 MapLiteral 混淆
   - ConstantListLiteral / ConstantMapLiteral 处理：常量集合在 Kernel 中可能已降糖为 Constant 节点
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/collection_create_test.dart test/e2e/collection_literal_test.dart`

---

### Task 5.3.2: STRING_INTERP 解释器 + 编译器

**产出文件：**
- Modify: `lib/src/runtime/interpreter.dart`（STRING_INTERP case）
- Modify: `lib/src/compiler/compiler_expressions.dart`（StringConcatenation 编译）
- Test: `test/runtime/string_interp_test.dart`
- Test: `test/e2e/string_interp_e2e_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch1 STRING_INTERP 0x98：将多个 ref 栈值拼接为 String。每个值先调用 toString()（若非 String），然后 StringBuffer 拼接。Kernel 中字符串插值表示为 `StringConcatenation`（parts 列表：StringLiteral 和 Expression 交替）
2. **写测试** —
   - 手工字节码：STRING_INTERP 将 2 个字符串拼接
   - 手工字节码：STRING_INTERP 将 int（已装箱）+ 字符串拼接（int 自动 toString）
   - 端到端：`'hello ${'world'}'` → `'hello world'`
   - 端到端：`int x = 42; return 'value is $x';` → `'value is 42'`
   - 端到端：`'${1 + 2} items'` → `'3 items'`
   - 端到端：`double d = 3.14; return 'pi is $d';` → `'pi is 3.14'`
   - 端到端：多段插值 `'$a + $b = ${a + b}'`
   - 端到端：嵌套插值 `'${list.length} items'`
   - 端到端：空字符串插值 `'${''}empty'`
   - 端到端：null 插值 `'${null}'` → `'null'`
3. **实现** —
   - 解释器 STRING_INTERP (0x98)：A = 目标 ref 寄存器，B = 起始 ref 寄存器，C = part 个数。遍历 refStack[rBase+B..B+C-1]，每个元素：如果是 String 直接拼接，否则调用 toString()（通过 HostClassWrapper 或直接 `.toString()`），StringBuffer 拼接结果存入 refStack[rBase+A]
   - 编译器 StringConcatenation：遍历 parts 列表，每个 part：
     - StringLiteral → LOAD_CONST 到 ref 寄存器
     - Expression → 编译到 ref 寄存器（值类型需 BOX）
   - 所有 parts 编译到连续 ref 寄存器后，emit STRING_INTERP
   - 优化：两段拼接（`'prefix' + expr.toString()`）可简化为 CALL_HOST + 操作符 +
4. **运行** — `fvm dart analyze && fvm dart test test/runtime/string_interp_test.dart test/e2e/string_interp_e2e_test.dart`

---

### Task 5.3.3: DarticCallbackProxy + DarticProxyManager

**产出文件：**
- Create: `lib/src/bridge/callback_proxy.dart`
- Create: `lib/src/bridge/proxy_manager.dart`
- Create: `lib/src/bridge/dartic_proxy.dart`
- Modify: `lib/src/bridge/core_bindings.dart`（含回调参数的 Bridge 方法补全）
- Test: `test/bridge/callback_proxy_test.dart`
- Test: `test/e2e/callback_bridge_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch4"DarticCallbackProxy"：将解释器闭包包装为 VM 可调用 Dart Function。proxy0()-proxy3() 生成 0-3 参数闭包。参数转换：VM 参数 → unwrapForInterpreter → _runtime.invokeClosure → 返回值 → wrapForVM。Ch4"DarticProxyManager"：双向 Expando 缓存（DarticObject ↔ DarticProxy），ephemeron 语义。Ch4"DarticProxy"：重写 ==、hashCode、toString()
2. **写测试** —
   - DarticCallbackProxy 单元测试：创建 mock closure → proxy1() 返回 Function(Object?) → 调用 → 验证回调触发
   - DarticProxyManager 单元测试：wrapForVM(DarticObject) 返回 DarticProxy → 再次 wrapForVM 返回 identical 实例 → unwrapForInterpreter(proxy) 返回原始 DarticObject
   - DarticProxy 单元测试：两个 proxy 包装同一 DarticObject → == 返回 true → hashCode 相同
   - 端到端：`[3,1,2].forEach((e) { /* side effect */ })` — forEach 回调调用
   - 端到端：`[1,2,3].map((e) => e * 2).toList()` → `[2,4,6]` — map 回调 + 返回值
   - 端到端：`[1,2,3,4].where((e) => e > 2).toList()` → `[3,4]` — where 谓词回调
   - 端到端：`[3,1,2].sort((a, b) => a.compareTo(b))` — sort 双参数比较器
   - 端到端：`List.generate(3, (i) => i * 10)` → `[0, 10, 20]` — 工厂回调
3. **实现** —
   - DarticCallbackProxy：持有 DarticClosure + DarticRuntime 引用。proxy0() 返回 `() => _invoke([])`，proxy1() 返回 `(a) => _invoke([a])`，...proxy3() 返回 `(a,b,c) => _invoke([a,b,c])`。_invoke 内部：对每个参数 unwrap → invokeClosure → wrapForVM 返回值
   - DarticRuntime 接口：定义 invokeClosure(DarticClosure, args) 方法。由 DarticInterpreter 实现。invokeClosure 需要在 CallStack 上建立回调帧，执行闭包字节码，返回结果。参考 Ch4"VM -> 解释器回调流程"中的 HOST_BOUNDARY 哨兵帧
   - DarticProxyManager：`_interpToProxy` Expando + `_proxyToInterp` Expando。wrapForVM/unwrapForInterpreter 实现
   - DarticProxy：持有 target DarticObject + DarticRuntime。重写 operator ==（比较 target 身份）、hashCode（identityHashCode(target)）、toString()（委托给 _runtime.invokeMethod）
   - 修改含回调参数的 Bridge 方法：在 HostClassWrapper 的 invokeMethod 中，检测参数是否为 DarticClosure → 自动创建 DarticCallbackProxy → 按回调参数数量选择 proxyN()
4. **运行** — `fvm dart analyze && fvm dart test test/bridge/callback_proxy_test.dart test/e2e/callback_bridge_test.dart`

---

### Task 5.3.4: HostClassWrapper 动态分发 + Spread 编译

**产出文件：**
- Create: `lib/src/bridge/host_class_wrapper.dart`（HostClassWrapper 基类 + 动态分发路由）
- Modify: `lib/src/runtime/interpreter.dart`（CALL_VIRTUAL 非 DarticObject 回退、GET_FIELD_DYN/SET_FIELD_DYN）
- Modify: `lib/src/compiler/compiler_expressions.dart`（Spread 编译）
- Test: `test/bridge/dynamic_dispatch_test.dart`
- Test: `test/e2e/spread_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch4"HostClassWrapper"：`getProperty(host, name)` + `invokeMethod(host, name, args)`。运行时维护 `Type → HostClassWrapper` 映射表。Ch3 中 CALL_VIRTUAL 对非 DarticObject 的处理（当前直接抛错，需要回退到 HostClassWrapper）。Ch1 GET_FIELD_DYN (0x67) / SET_FIELD_DYN (0x68)。Kernel 中 SpreadElement 的 AST 表示
2. **写测试** —
   - HostClassWrapper 单元测试：注册 int wrapper → `invokeMethod(42, 'abs', [])` → 42 / `getProperty(42, 'isEven')` → true
   - CALL_VIRTUAL 回退测试：receiver 为 VM 原生 List → 调用 `.length` → 通过 HostClassWrapper 正确分发
   - 动态类型测试：`dynamic x = [1,2,3]; return x.length;` — CALL_VIRTUAL 或 INVOKE_DYN 分发到 HostClassWrapper
   - GET_FIELD_DYN 测试：`dynamic x = 'hello'; return x.length;` → 5
   - Spread 端到端：`[1, ...[2, 3], 4]` → `[1, 2, 3, 4]`
   - Spread 端到端：`{...{'a': 1}, 'b': 2}` → `{'a': 1, 'b': 2}`
   - Spread null-aware：`[1, ...?nullableList, 2]`
   - Spread + if：`[1, if (true) 2, 3]` → `[1, 2, 3]`（collection if）
   - Spread + for：`[for (var i = 0; i < 3; i++) i]` → `[0, 1, 2]`（collection for）
3. **实现** —
   - HostClassWrapper 抽象基类：`Object? getProperty(Object host, String name)` + `Object? invokeMethod(Object host, String name, List<Object?> args)`。维护 `Map<Type, HostClassWrapper> _wrappers`
   - 为每个已桥接类型创建 HostClassWrapper 子类（复用 Batch 5.2 的 wrapper 实现，统一入口）。注册到 `_wrappers` 映射
   - 解释器 CALL_VIRTUAL 修改：receiver 不是 DarticObject 时，按 `receiver.runtimeType` 查找 HostClassWrapper → invokeMethod
   - 解释器 GET_FIELD_DYN (0x67)：按 receiver 类型路由——DarticObject 用方法表查找，VM 对象用 HostClassWrapper.getProperty
   - 解释器 SET_FIELD_DYN (0x68)：类似 GET_FIELD_DYN 的双路径路由
   - Spread 编译：Kernel 中 SpreadElement 是 ListLiteral/SetLiteral 的特殊 element。编译策略：先创建空集合 → 遍历 elements，普通元素 add，SpreadElement 编译 expression → addAll。或者：编译器分析 element 列表，非 spread 元素用 CREATE_LIST，包含 spread 时退化为 CREATE_LIST(0) + add/addAll 序列
   - Collection if/for 编译：Kernel CFE 可能已经将 collection if/for 降糖为 Block+IfStatement/ForStatement。检查 Kernel AST 确认——如果已降糖，无需额外处理
4. **运行** — `fvm dart analyze && fvm dart test test/bridge/dynamic_dispatch_test.dart test/e2e/spread_test.dart`

---

## Commit

```
feat: add collection literals, string interpolation, callback proxy, and dynamic dispatch
```

**提交文件：** `lib/src/bridge/callback_proxy.dart`, `proxy_manager.dart`, `dartic_proxy.dart`, `host_class_wrapper.dart`（新）+ 修改的 interpreter.dart + compiler_expressions.dart + 全部新测试

## 核心发现

- **HOST_BOUNDARY 哨兵帧**: funcId=0xFFFFFFFF 标记 VM→解释器回调边界。RETURN 指令检测到哨兵帧时存储结果到 `_callbackResult` 并退出 `_executeLoop`。异常同理 — 直接 rethrow 到 VM 调用方
- **paramKinds 元数据**: `DarticFuncProto` 新增 `Uint8List? paramKinds` 存储每个参数的 StackKind index（后续 boolVal 重构后编码为 0=ref, 1=boolVal, 2=intVal, 3=doubleVal）。`invokeClosure` 据此将宿主参数路由到正确的栈（value 栈 vs ref 栈）。不设置 paramKinds 时回退到旧行为（全部写入 ref 栈 rBase+2+i）
- **returnKind 元数据**: `DarticFuncProto` 新增 `int returnKind`（后续 boolVal 重构后编码为 0=ref, 1=boolVal, 2=intVal, 3=doubleVal）。解决了 bool 在 value 栈上以 0/1 存储但宿主 VM 期望 Dart bool 的阻抗不匹配问题
- **DarticCallbackProxy proxy0()-proxy3()**: 0-3 参数闭包覆盖 forEach/map/where/sort/fold/any/every/List.generate 等全部回调场景
- **CFE 降糖**: `[a,b,c]` → `_GrowableList._literalN()`，`{a,b,c}` (Set) → `_Set()..add()..add()`。需注册 `_GrowableList` 和 `_Set` 变体绑定
- **CALL_HOST 自动包装**: DarticClosure 参数在 CALL_HOST handler 中按 paramCount 自动选择 proxyN() 包装，桥接 wrapper 无需感知解释器闭包
- **HostClassWrapper 动态分发**: `BindingsClassWrapper` 复用已注册的 HostBindings 按名称查找，`HostClassRegistry` 通过 `is` 检查路由 8 种宿主类型（String/int/double/bool/List/Map/Set/Duration/Iterable）。`invokeMethod` 自动向上搜索 arity+1..+3 以覆盖可选参数缺省场景
- **Spread/if/for 均为 CFE 降糖**: `[1,...[2,3],4]` → `_GrowableList._literal1(1)` + `addAll([2,3])` + `add(4)`，`{...map}` → `LinkedHashMap.of(map)`。编译器无需特殊处理，只需注册 `LinkedHashMap.of#1` 和 `LinkedHashMap::#0` 绑定
- **DynamicGet/Set/Invocation 编译**: Kernel `DynamicGet` → `GET_FIELD_DYN` (ABC: A=result, B=receiver, C=names index)。`DynamicInvocation` → `INVOKE_DYN` (ABC: A=result, B=totalArgCount, C=names index; receiver at A+1, args at A+2+)。CALL_VIRTUAL 新增非 DarticObject 回退到 HostClassWrapper

## Batch 完成检查

- [x] 5.3.1 CREATE_LIST/MAP/SET 解释器 + 编译器
- [x] 5.3.2 STRING_INTERP 解释器 + 编译器
- [x] 5.3.3 DarticCallbackProxy + DarticProxyManager
- [x] 5.3.4 HostClassWrapper 动态分发 + Spread 编译
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test` 全部通过（1864 tests）
- [x] commit 已提交 (4004be4 + bc2798a review fix)
- [x] overview.md 已更新
- [x] code review 已完成
