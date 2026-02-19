# Batch 5.2: dart:core 完整桥接

## 概览

为 dart:core 所有核心类型实现 HostBindings 注册：Object/Type/Null → int/num/double → bool → String → List/Iterable → Map/Set/Duration 及其他常用类。每个类型的桥接包括：方法调用、属性读取、操作符路由、构造器。优先级按 co19 测试解锁量排序。

**设计参考：** `docs/design/04-interop.md`（HostClassWrapper 分发路由、操作符路由命名、类型映射）

**依赖：** Batch 5.1（CALL_HOST 管线完整可用）

---

### Task 5.2.1: Object + Type + Null Bridge

**产出文件：**
- Modify: `lib/src/bridge/wrappers/object_wrapper.dart`（补全 Object 方法）
- Create: `lib/src/bridge/wrappers/type_wrapper.dart`
- Modify: `lib/src/bridge/core_bindings.dart`（注册入口扩展）
- Test: `test/bridge/object_type_bridge_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch4"基本类型传递"：null 直接传值。Object 基础方法列表：toString, hashCode, runtimeType, ==, noSuchMethod。Type 类型的 toString 和 == 行为
2. **写测试** — 端到端验证：
   - `Object().toString()` 返回 `'Instance of \'Object\''`
   - `Object().hashCode` 返回非零 int
   - `Object() == Object()` 返回 false（不同实例）
   - `identical(null, null)` 返回 true
   - `null.toString()` 返回 `'null'`
   - `42.runtimeType` 返回 Type 对象
   - `42.runtimeType.toString()` 返回 `'int'`
   - `(42).runtimeType == (1).runtimeType` 返回 true
   - `null is Object?` 返回 true
   - `null is Object` 返回 false（Dart 3 空安全语义）
3. **实现** —
   - Object Bridge：补全 Batch 5.1 的最小桥接，覆盖 toString/hashCode/runtimeType/==
   - Type Bridge：Type.toString 委托 VM `Type.toString()`，Type.== 按 VM `identical` 或 DarticType identical
   - Null 处理：null 在 ref 栈中直接表示为 Dart null，null 方法调用（toString 等）通过 HostBindings 路由到 `null.toString()` 等 VM 调用
   - 注册到 CoreBindings
4. **运行** — `fvm dart analyze && fvm dart test test/bridge/object_type_bridge_test.dart`

---

### Task 5.2.2: int + num Bridge

**产出文件：**
- Create: `lib/src/bridge/wrappers/int_wrapper.dart`
- Create: `lib/src/bridge/wrappers/num_wrapper.dart`
- Test: `test/bridge/int_num_bridge_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch4"操作符路由命名"：使用 Dart 规范操作符名（`+`, `-`, `unary-` 等），与 Kernel `Name.text` 一致。注意：int 基本算术已有特化操作码（ADD_INT 等），Bridge 主要覆盖非特化方法
2. **写测试** — 端到端验证：
   - `42.toString()` → `'42'`
   - `42.toDouble()` → `42.0`
   - `(-42).abs()` → `42`
   - `42.isEven` → true / `43.isOdd` → true
   - `42.isNegative` → false
   - `42.clamp(0, 10)` → 10
   - `42.compareTo(43)` → 负数
   - `42.remainder(5)` → 2
   - `42.toRadixString(16)` → `'2a'`
   - `int.parse('42')` → 42（静态方法）
   - `int.tryParse('abc')` → null
   - `42.sign` → 1
   - `42.bitLength` → 6
   - `num.parse('3.14')` → 3.14
   - `42.ceil()` / `.floor()` / `.round()` / `.truncate()` → 42（num 方法，int 上为恒等）
   - `42.toInt()` → 42（恒等）
   - `42.toStringAsFixed(2)` → `'42.00'`（num 方法）
3. **实现** —
   - int Bridge：注册 toString, toDouble, abs, isEven, isOdd, isNegative, clamp, compareTo, remainder, toRadixString, sign, bitLength, gcd, toSigned, toUnsigned, modPow, modInverse 等方法
   - int 静态方法：int.parse, int.tryParse
   - num Bridge：注册 ceil, floor, round, truncate, toInt, toDouble, abs, sign, isFinite, isInfinite, isNaN, isNegative, clamp, compareTo, remainder, toStringAsFixed, toStringAsPrecision, toStringAsExponential 等方法
   - num 静态方法：num.parse, num.tryParse
   - 所有 wrapper 统一使用 `(args) { final self = args[0] as int; ... }` 模式
4. **运行** — `fvm dart analyze && fvm dart test test/bridge/int_num_bridge_test.dart`

---

### Task 5.2.3: double Bridge

**产出文件：**
- Create: `lib/src/bridge/wrappers/double_wrapper.dart`
- Test: `test/bridge/double_bridge_test.dart`

**TDD 步骤：**

1. **读设计文档** — double 在值栈中以 Float64 存储（通过 Int64List 双视图）。跨边界时需要 BOX_DOUBLE（值→ref）。double 方法大部分继承自 num，额外特有的常量（infinity, nan, minPositive 等）需要桥接
2. **写测试** — 端到端验证：
   - `3.14.toString()` → `'3.14'`
   - `3.14.ceil()` → 4
   - `3.14.floor()` → 3
   - `3.14.round()` → 3
   - `3.14.truncate()` → 3
   - `3.14.toInt()` → 3
   - `3.14.isFinite` → true
   - `double.infinity.isInfinite` → true
   - `double.nan.isNaN` → true
   - `double.parse('3.14')` → 3.14
   - `double.tryParse('abc')` → null
   - `3.14.abs()` → 3.14
   - `(-3.14).sign` → -1.0
   - `3.14.toStringAsFixed(1)` → `'3.1'`
   - `3.14.ceilToDouble()` / `.floorToDouble()` / `.roundToDouble()` / `.truncateToDouble()`
   - `double.maxFinite` / `double.minPositive` 常量访问
3. **实现** —
   - double Bridge：注册 num 继承方法（复用 num wrapper 实现）+ double 特有方法
   - double 静态方法：double.parse, double.tryParse
   - double 常量：double.infinity, double.nan, double.maxFinite, double.minPositive, double.negativeInfinity — 作为 getter 绑定注册
   - 注意 ceilToDouble/floorToDouble/roundToDouble/truncateToDouble 是 double 特有方法
4. **运行** — `fvm dart analyze && fvm dart test test/bridge/double_bridge_test.dart`

---

### Task 5.2.4: bool + String Bridge

**产出文件：**
- Create: `lib/src/bridge/wrappers/bool_wrapper.dart`
- Create: `lib/src/bridge/wrappers/string_wrapper.dart`
- Test: `test/bridge/bool_string_bridge_test.dart`

**TDD 步骤：**

1. **读设计文档** — bool 只有少量方法（toString）。String 是高频使用类型，方法众多：length, substring, indexOf, contains, startsWith, endsWith, trim, split, replaceAll, toLowerCase, toUpperCase, compareTo, codeUnitAt, 操作符 [] 和 + 等
2. **写测试** — 端到端验证：
   - bool: `true.toString()` → `'true'`、`false.toString()` → `'false'`
   - String 属性: `'hello'.length` → 5、`''.isEmpty` → true、`'hi'.isNotEmpty` → true
   - String 方法: `'hello world'.substring(0, 5)` → `'hello'`、`'hello'.indexOf('l')` → 2、`'hello'.contains('ell')` → true
   - String 操作: `'hello'[0]` → `'h'`（operator []）、`'hello' + ' world'` → `'hello world'`（operator +）
   - String 变换: `'Hello'.toLowerCase()` → `'hello'`、`' hi '.trim()` → `'hi'`、`'a,b,c'.split(',')` → `['a','b','c']`
   - String 比较: `'abc'.compareTo('abd')` → 负数、`'hello'.startsWith('hel')` → true
   - String 其他: `'hello'.replaceAll('l', 'r')` → `'herro'`、`'hello'.codeUnitAt(0)` → 104
   - String 静态: `String.fromCharCode(65)` → `'A'`、`String.fromCharCodes([72, 101])` → `'He'`
   - `'hello'.padLeft(10)` / `.padRight(10)` / `.replaceFirst` / `.replaceRange` / `.toUpperCase`
3. **实现** —
   - bool Bridge：toString（简单包装）
   - String Bridge：覆盖所有常用实例方法和属性。分组注册：
     - 属性：length, isEmpty, isNotEmpty, hashCode, runes, codeUnits
     - 查找：indexOf, lastIndexOf, contains, startsWith, endsWith
     - 变换：substring, trim, trimLeft, trimRight, toLowerCase, toUpperCase, replaceAll, replaceFirst, replaceRange
     - 分割/拼接：split, operator +, operator *, padLeft, padRight
     - 字符访问：operator [], codeUnitAt, compareTo
     - 静态方法：String.fromCharCode, String.fromCharCodes, String.fromEnvironment
   - 注意 `split` 返回 `List<String>`，需要 List Bridge（5.2.5）就绪后才能完整测试——先注册绑定，集成测试在 5.2.5 后补充
4. **运行** — `fvm dart analyze && fvm dart test test/bridge/bool_string_bridge_test.dart`

---

### Task 5.2.5: List + Iterable Bridge

**产出文件：**
- Create: `lib/src/bridge/wrappers/list_wrapper.dart`
- Create: `lib/src/bridge/wrappers/iterable_wrapper.dart`
- Test: `test/bridge/list_iterable_bridge_test.dart`

**TDD 步骤：**

1. **读设计文档** — Ch2"基本类型与集合的运行时表示"：`CREATE_LIST` 创建的是 VM 原生 List，直接存 ref 栈。List 方法通过 CALL_HOST 路由。Ch4"VM 对象进入解释器"：VM 原生对象直接存 ref 栈。Iterable 是 List/Set 等集合的超类型接口
2. **写测试** — 端到端验证：
   - List 属性: `[1,2,3].length` → 3、`[].isEmpty` → true、`[1].isNotEmpty` → true、`[1,2].first` → 1、`[1,2].last` → 2
   - List 索引: `[10,20,30][1]` → 20（operator []）、赋值 `list[0] = 99`（operator []=）
   - List 修改: `list.add(4)` / `list.addAll([5,6])` / `list.insert(0, 0)` / `list.removeAt(0)` / `list.removeLast()` / `list.clear()`
   - List 查询: `list.contains(2)` → true / `list.indexOf(2)` → 1 / `list.lastIndexOf(2)`
   - List 变换: `list.reversed` / `list.sublist(1, 3)` / `list.getRange(0, 2)` / `list.join(',')` → `'1,2,3'`
   - List 排序: `list.sort()` / `list.sort((a,b) => b.compareTo(a))` — 注意回调参数需要 DarticCallbackProxy（Batch 5.3.3 支持后补充测试）
   - List 构造: `List.filled(3, 0)` → `[0,0,0]` / `List.generate(3, (i) => i)` — 回调版 Batch 5.3.3 后测试
   - Iterable: `iterable.map((e) => e * 2)` / `iterable.where((e) => e > 1)` / `iterable.toList()` / `iterable.toSet()` — 回调版 Batch 5.3.3 后测试
   - 先测试不涉及回调的方法（length, [], []=, add, contains, indexOf, join, sublist, reversed, first, last, isEmpty）
3. **实现** —
   - List Bridge：注册所有常用方法（优先不含回调的方法，含回调的方法同样注册但集成测试延迟到 5.3.3）
     - 属性：length, isEmpty, isNotEmpty, first, last, reversed, hashCode
     - 操作符：operator [], operator []=
     - 修改：add, addAll, insert, insertAll, remove, removeAt, removeLast, removeWhere, clear, sort, shuffle, fillRange, setRange, replaceRange
     - 查询：contains, indexOf, lastIndexOf, indexWhere, lastIndexWhere, any, every
     - 变换：sublist, getRange, join, asMap, toSet, toList, iterator
     - 构造：List.filled, List.generate, List.of, List.from, List.empty, List.unmodifiable
   - Iterable Bridge：注册通用迭代器方法
     - map, where, expand, fold, reduce, forEach, toList, toSet, any, every, contains, join, take, skip, firstWhere, lastWhere, singleWhere, elementAt, cast, followedBy, whereType
   - 含回调参数的方法：先注册绑定（直接将 VM 对象参数传递给 host 方法），回调包装逻辑在 5.3.3 DarticCallbackProxy 就绪后补充
4. **运行** — `fvm dart analyze && fvm dart test test/bridge/list_iterable_bridge_test.dart`

---

### Task 5.2.6: Map + Set + Duration + 其他常用类 Bridge

**产出文件：**
- Create: `lib/src/bridge/wrappers/map_wrapper.dart`
- Create: `lib/src/bridge/wrappers/set_wrapper.dart`
- Create: `lib/src/bridge/wrappers/duration_wrapper.dart`
- Create: `lib/src/bridge/wrappers/error_wrappers.dart`（Error 系列类）
- Test: `test/bridge/map_set_duration_bridge_test.dart`

**TDD 步骤：**

1. **读设计文档** — Map/Set 与 List 类似，是 VM 原生对象。Duration 是 Phase 4 的头号失败原因（422 测试）。Error/Exception 系列（TypeError, RangeError, ArgumentError 等）用于运行时错误
2. **写测试** — 端到端验证：
   - Map: `{'a': 1}['a']` → 1 / `map.containsKey('a')` → true / `map.keys.length` → 1 / `map.values` / `map.entries` / `map.length` / `map.isEmpty` / `map.putIfAbsent` / `map.remove` / `map.addAll` / `map.clear`
   - Set: `{1,2,3}.contains(2)` → true / `set.length` → 3 / `set.add(4)` / `set.remove(1)` / `set.union` / `set.intersection` / `set.difference` / `set.toList()`
   - Duration: `Duration(seconds: 1).inMilliseconds` → 1000 / `Duration(hours: 1, minutes: 30)` / `d1 + d2` / `d1 - d2` / `d1 > d2` / `d.isNegative` / `d.abs()` / `d.toString()` / `d.inSeconds` / `d.inMinutes` / `d.inHours` / `d.inDays`
   - Error 系列: `ArgumentError('msg').message` / `RangeError.range(5, 0, 3)` / `StateError('msg')` / `UnsupportedError('msg')` / `TypeError` / `FormatException` — 构造器 + 基本属性
3. **实现** —
   - Map Bridge：operator [], operator []=, containsKey, containsValue, keys, values, entries, length, isEmpty, isNotEmpty, putIfAbsent, remove, removeWhere, addAll, addEntries, update, updateAll, clear, map, forEach, cast
   - Map 构造器：Map(), Map.from, Map.of, Map.unmodifiable, Map.identity, Map.fromEntries, Map.fromIterable, Map.fromIterables
   - Set Bridge：contains, add, addAll, remove, removeAll, removeWhere, retainAll, retainWhere, union, intersection, difference, length, isEmpty, isNotEmpty, toList, first, last, lookup, containsAll, clear, cast
   - Set 构造器：Set(), Set.from, Set.of, Set.identity, Set.unmodifiable
   - Duration Bridge：全部属性（inDays, inHours, inMinutes, inSeconds, inMilliseconds, inMicroseconds, isNegative）+ 方法（abs, compareTo, toString）+ 操作符（+, -, *, ~/, <, >, <=, >=, ==, unary-）
   - Duration 构造器：`Duration({days, hours, minutes, seconds, milliseconds, microseconds})`
   - Duration 常量：Duration.zero, Duration.microsecondsPerMillisecond 等
   - Error 系列 Bridge：ArgumentError, RangeError, StateError, UnsupportedError, FormatException, IndexError, ConcurrentModificationError, TypeError — 构造器 + message/toString
4. **运行** — `fvm dart analyze && fvm dart test test/bridge/map_set_duration_bridge_test.dart`

---

## Commit

```
feat(bridge): add dart:core bridges for int, String, List, Map, Set, Duration, and errors
```

**提交文件：** `lib/src/bridge/wrappers/`（全部新 wrapper）+ 修改的 core_bindings.dart + 全部新测试

## 核心发现

**方法覆盖度统计：**

| 类型 | 注册绑定数 | 覆盖范围 |
|------|-----------|---------|
| Object | 5 | toString, hashCode, runtimeType, noSuchMethod, identical |
| Type | 2 | toString, hashCode |
| int | ~25 | isEven, isOdd, abs, bitLength, sign, toRadixString, gcd, modPow, parse, tryParse, ceil/floor/round/truncate... |
| num | ~18 | abs, ceil, floor, round, truncate, toInt, toDouble, sign, isFinite/Infinite/NaN/Negative, clamp, compareTo, parse, tryParse... |
| double | ~28 | toString, ceil/floor/round/truncate, toInt, abs, sign, is*, ceilToDouble/floorToDouble/roundToDouble/truncateToDouble, parse, tryParse, 常量... |
| bool | 2 | toString, hashCode |
| String | 28 | isEmpty/isNotEmpty, toLowerCase/toUpperCase, trim*, substring, indexOf, contains, startsWith/endsWith, replaceAll/First, split, compareTo, codeUnitAt, padLeft/Right, operator+/*/[], fromCharCode/Codes |
| List | ~40+ | length, isEmpty/isNotEmpty, first/last, reversed, []/[]=, add/addAll/insert, remove*/clear, contains, indexOf, sublist, join, toList/toSet, filled/empty/generate/of/from, + _GrowableList internal bindings |
| Iterable | ~14 | length, isEmpty/isNotEmpty, first/last, toList/toSet, contains, join, elementAt, take, skip |
| Map | ~15 | length, isEmpty/isNotEmpty, keys/values/entries, []/[]=, containsKey/Value, remove, addAll, clear, putIfAbsent |
| Set | ~18 | length, isEmpty/isNotEmpty, first/last, contains, add/addAll, remove/removeAll/retainAll, union/intersection/difference, toList, clear |
| Duration | ~25 | inDays/Hours/Minutes/Seconds/Milliseconds/Microseconds, isNegative, abs, compareTo, toString, operators(+/-/*/~/</>/<=/>=/unary-), 构造器#6, zero, 常量 |
| Error 系列 | ~17 | ArgumentError, RangeError, StateError, UnsupportedError, FormatException, Error, Exception, ConcurrentModificationError, StackOverflowError |

**需要延迟到 5.3.3 的回调方法（约 15+）：** List.sort(compare), List.forEach, List.map/where/any/every/reduce/fold, List.removeWhere/retainWhere, Map.forEach/map/putIfAbsent/update, Set.removeWhere/retainWhere

**关键发现：**
1. `int.parse` 在 Kernel 中有 3 个形参（source, radix, onError），非预期的 2 个
2. Dart SDK 前端将 List 字面量降级为 `_GrowableList._literalN()` 内部工厂调用，需要同时注册内部绑定名
3. operator[] 的 Kernel name.text 是 `[]`（不是 `[`）
4. Duration 构造器的命名参数在 CALL_HOST 中无法传递参数名，是已知的设计局限
5. Map/Set 字面量和 Duration 常量需要编译器支持 MapLiteral/SetLiteral/InstanceConstant，当前通过 HostBindings.invoke() 单元测试验证

## Batch 完成检查

- [x] 5.2.1 Object + Type + Null Bridge
- [x] 5.2.2 int + num Bridge
- [x] 5.2.3 double Bridge
- [x] 5.2.4 bool + String Bridge
- [x] 5.2.5 List + Iterable Bridge
- [x] 5.2.6 Map + Set + Duration + 其他常用类 Bridge
- [x] `fvm dart analyze` 零警告
- [x] `fvm dart test` 全部通过 (1758 tests)
- [ ] commit 已提交
- [ ] overview.md 已更新
- [ ] code review 已完成
