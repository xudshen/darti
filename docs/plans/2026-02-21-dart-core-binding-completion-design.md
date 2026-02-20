# dart:core Binding 补全设计

**日期：** 2026-02-21
**阶段：** Phase 5 新增 Batch 5.6（在 5.4 co19 验证之前执行）
**目标：** 全面补齐 dart:core 所有类的 bindings，最大化 co19 LibTest/core 通过率

## 背景

Phase 5 已完成 14 个 dart:core 类 ~245+ 个方法绑定（覆盖率 ~88%）。剩余工作分两类：
1. **补面**：已绑定类缺失的 callback/泛型方法（~50 个方法）
2. **新类**：RegExp/Match, StringBuffer, DateTime, Uri, BigInt 等（~10 个新类）

## 决策记录

| 问题 | 决策 | 理由 |
|------|------|------|
| 补全范围 | dart:core 全部类 | 最大化 co19 覆盖率 |
| 实施阶段 | Phase 5 新 batch 5.6 | 在 5.4 co19 验证前补齐，一次性拿到最大通过率收益 |
| 分批策略 | 按工作类型分 3 批（补面 → 正则族 → 独立类） | 工作量均匀，依赖关系清晰 |
| `whereType<T>()` / `cast<T>()` | 跳过，标注已知局限 | CALL_HOST 无类型参数通道，且 Dart 不支持动态泛型调用 |

## 方案概览

| Batch | 内容 | 新绑定数 |
|-------|------|---------|
| 5.6.1 | 已有类 callback/方法补齐（Map, Set, List, Iterable, String） | ~50 |
| 5.6.2 | 新类 - 字符串/正则族（RegExp, Match, StringBuffer, Runes, RuneIterator） | ~46 |
| 5.6.3 | 新类 - 时间/数值/其他（DateTime, Uri, BigInt, Stopwatch, StackTrace, Symbol, Expando, MapEntry, Iterator） | ~92 |

---

## Batch 5.6.1：已有类 callback/方法补齐

### Map（+5 方法）

- `forEach(void Function(K, V))` — 极常用
- `map<K2,V2>(MapEntry<K2,V2> Function(K, V))` — 变换
- `updateAll(V Function(K, V))` — 批量更新
- `removeWhere(bool Function(K, V))` — 条件删除
- `cast<K2,V2>()` — ❌ 跳过（需要 reified 泛型）

### Set（+16 方法，callback 全缺）

- callback 类：`forEach`, `map`, `where`, `any`, `every`, `fold`, `reduce`, `expand`
- callback + orElse：`firstWhere`, `lastWhere`, `singleWhere`
- callback 类：`takeWhile`, `skipWhile`
- getter/方法：`toSet()`, `elementAt(int)`, `take(int)`, `skip(int)`, `single`
- ❌ 跳过：`whereType<T>()`, `cast<T>()`

### List（+9 方法 + _GrowableList 镜像）

- callback 类：`removeWhere(bool Function(E))`, `retainWhere(bool Function(E))`
- callback 类：`expand(Iterable Function(E))`, `reduce(E Function(E,E))`
- callback + orElse：`firstWhere(bool Function(E), {orElse})`, `lastWhere`, `singleWhere`
- 操作符：`operator +`（List 拼接）
- getter：`single`
- ❌ 跳过：`whereType<T>()`, `cast<T>()`
- 需同步在 `_GrowableList` 上镜像注册

### Iterable（+9 方法）

- callback 类：`reduce`, `expand`, `takeWhile`, `skipWhile`
- callback + orElse：`firstWhere`, `lastWhere`, `singleWhere`
- getter：`single`
- 方法：`followedBy(Iterable)`
- ❌ 跳过：`whereType<T>()`, `cast<T>()`

### String（+1 getter）

- `codeUnits` — 返回 `List<int>` unmodifiable view
- `runes` — 依赖 5.6.2 的 Runes 类，在 5.6.2 中补

### 实现策略

所有方法沿用现有 `registry.register('dart:core::Class::method#N', ...)` 模式。callback 方法的 DarticCallbackProxy 管线在 5.3 已验证（List.forEach/map/where/fold/any/every 已工作），这里只是扩面到 Map、Set。

---

## Batch 5.6.2：字符串/正则族

### 依赖关系

```
RegExp ──► Match/RegExpMatch（firstMatch/allMatches 返回 Match）
  │
  ▼
String.replaceAllMapped ──► Match（callback 参数类型）
String.replaceFirstMapped ──► Match
String.splitMapJoin ──► Match
String.allMatches ──► Match（Pattern 接口实现）
```

### RegExp（~15 个绑定）

- 构造器：`RegExp(String source, {bool multiLine, bool caseSensitive, bool unicode, bool dotAll})`
- getter：`pattern`, `isMultiLine`, `isCaseSensitive`, `isUnicode`, `isDotAll`
- 方法：`hasMatch(String)`, `firstMatch(String)`, `allMatches(String, [int])`, `stringMatch(String)`, `matchAsPrefix(String, [int])`
- `toString()`

### Match（~8 个绑定）

- getter：`start`, `end`, `input`, `groupCount`, `pattern`
- 方法：`group(int)`, `operator [](int)`, `groups(List<int>)`

### RegExpMatch（+2 个绑定，继承 Match）

- `namedGroup(String)`, `groupNames` getter

### StringBuffer（~10 个绑定）

- 构造器：`StringBuffer([String content])`
- getter：`length`, `isEmpty`, `isNotEmpty`
- 方法：`write(Object)`, `writeln([Object])`, `writeAll(Iterable, [String])`, `writeCharCode(int)`, `clear()`, `toString()`

### Runes（~5 个绑定）

- 构造器：`Runes(String)`
- getter：`length`, `first`, `last`, `isEmpty`
- 方法：`elementAt(int)`, `iterator`, `toList()`, `contains(Object)`

### RuneIterator（~5 个绑定）

- getter：`current`, `currentSize`, `currentAsString`, `rawIndex`
- 方法：`moveNext()`, `reset([int])`, `movePrevious()`

### String 补充（依赖 Match，+5 方法）

- `replaceAllMapped(Pattern, String Function(Match))`
- `replaceFirstMapped(Pattern, String Function(Match), [int])`
- `splitMapJoin(Pattern, {onMatch, onNonMatch})`
- `allMatches(String, [int])` — Pattern 接口
- `matchAsPrefix(String, [int])` — Pattern 接口
- `runes` getter — 返回 Runes 实例

### 实现要点

- Match/RegExpMatch 是 VM 原生对象（由 RegExp.firstMatch 等返回），直接走 HostFunctionRegistry 注册
- DarticCallbackProxy 已支持 1 参数回调（proxy1），`replaceAllMapped` 的 `String Function(Match)` 可直接工作
- StringBuffer 是 mutable 对象，binding 需确保同一实例在多次调用间保持状态

---

## Batch 5.6.3：时间/数值/其他

所有类之间无互相依赖，可并行开发。

### DateTime（~25 个绑定，co19 65 个测试）

- 构造器：`DateTime(year, [month, day, hour, minute, second, millisecond, microsecond])`, `DateTime.utc(...)`, `DateTime.now()`, `DateTime.fromMillisecondsSinceEpoch(int, {isUtc})`, `DateTime.fromMicrosecondsSinceEpoch(int, {isUtc})`
- 静态方法：`DateTime.parse(String)`, `DateTime.tryParse(String)`
- getter：`year`, `month`, `day`, `hour`, `minute`, `second`, `millisecond`, `microsecond`, `weekday`, `isUtc`, `timeZoneName`, `timeZoneOffset`, `millisecondsSinceEpoch`, `microsecondsSinceEpoch`
- 方法：`add(Duration)`, `subtract(Duration)`, `difference(DateTime)`, `compareTo(DateTime)`, `isAfter(DateTime)`, `isBefore(DateTime)`, `isAtSameMomentAs(DateTime)`, `toLocal()`, `toUtc()`, `toIso8601String()`, `toString()`
- `hashCode` getter

### Uri（~25 个绑定，co19 158 个测试）

- 静态工厂：`Uri.parse(String)`, `Uri.tryParse(String)`, `Uri(...)`, `Uri.http(...)`, `Uri.https(...)`, `Uri.file(...)`, `Uri.directory(...)`, `Uri.dataFromString(...)`
- getter：`scheme`, `authority`, `userInfo`, `host`, `port`, `path`, `query`, `fragment`, `pathSegments`, `queryParameters`, `origin`, `isAbsolute`, `hasAuthority`, `hasPort`, `hasQuery`, `hasFragment`, `hasEmptyPath`, `hasAbsolutePath`, `hasScheme`
- 方法：`resolve(String)`, `resolveUri(Uri)`, `replace({...})`, `normalizePath()`, `toFilePath({windows})`, `toString()`, `isScheme(String)`
- 静态方法：`Uri.encodeFull(String)`, `Uri.decodeFull(String)`, `Uri.encodeComponent(String)`, `Uri.decodeComponent(String)`, `Uri.encodeQueryComponent(String)`, `Uri.decodeQueryComponent(String)`, `Uri.splitQueryString(String)`
- `hashCode`, `operator ==`

### BigInt（~20 个绑定）

- 工厂：`BigInt.from(num)`, `BigInt.parse(String, {radix})`, `BigInt.tryParse(String, {radix})`
- 静态常量：`BigInt.zero`, `BigInt.one`, `BigInt.two`
- getter：`isEven`, `isOdd`, `isNegative`, `isValidInt`, `bitLength`, `sign`, `hashCode`
- 方法：`abs()`, `compareTo(BigInt)`, `gcd(BigInt)`, `modInverse(BigInt)`, `modPow(BigInt, BigInt)`, `pow(int)`, `remainder(BigInt)`, `toInt()`, `toDouble()`, `toRadixString(int)`, `toString()`, `toSigned(int)`, `toUnsigned(int)`
- 操作符：`+`, `-`, `*`, `~/`, `%`, `<<`, `>>`, `&`, `|`, `^`, `~`, `<`, `<=`, `>`, `>=`, `unary-`

### Stopwatch（~8 个绑定）

- 构造器：`Stopwatch()`
- getter：`elapsed`, `elapsedMilliseconds`, `elapsedMicroseconds`, `elapsedTicks`, `frequency`, `isRunning`
- 方法：`start()`, `stop()`, `reset()`

### StackTrace（~2 个绑定）

- `StackTrace.current` — 静态 getter
- `toString()`

### Symbol（~3 个绑定）

- 构造器：`Symbol(String)`
- `hashCode`, `operator ==`, `toString()`

### Expando（~4 个绑定）

- 构造器：`Expando([String name])`
- getter：`name`
- `operator [](Object)`, `operator []=(Object, T)`
- `toString()`

### MapEntry（~3 个绑定）

- 构造器：`MapEntry(K, V)`
- getter：`key`, `value`
- `toString()`

### Iterator（~2 个绑定）

- getter：`current`
- 方法：`moveNext()`

---

## 已知局限

以下方法因 CALL_HOST 无类型参数通道 + Dart 不支持动态泛型调用而跳过：

| 方法 | 类 | 原因 |
|------|-----|------|
| `whereType<T>()` | Iterable, List, Set | 需要 reified 泛型 T |
| `cast<T>()` | Iterable, List, Set | 需要 reified 泛型 T |
| `cast<K2,V2>()` | Map | 需要 reified 泛型 K2,V2 |

未来可能的解决路径：
1. 预生成常见类型组合的专用 binding
2. 解释器层面实现（遍历 + INSTANCEOF 检查）
3. 扩展 CALL_HOST 指令格式传递 DarticType

## 预期收益

补全后 dart:core binding 将达到 ~190+ 新增绑定（总计 ~435+），覆盖 dart:core 公开 API 的 ~95%+。预估 co19 LibTest/core 通过率可从当前基线大幅提升，为 batch 5.4 的验证跑分提供最大化覆盖。
