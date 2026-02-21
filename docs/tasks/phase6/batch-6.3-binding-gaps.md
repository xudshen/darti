# Batch 6.3+: Async / Collection / Math Binding 缺口补全

## 概览

Phase 6 Batch 6.3 已完成 dart:async bridge 和 dart:collection/math 的初始绑定。本补充批次补全三大模块中已知缺口方法/类，提升 co19 测试通过率和 Dart 代码完整支持。

---

## Batch A：简单 Async + Collection 方法

### Task A.1：Future.asStream + Future.ignore + Completer.sync — ✅

- [x] `dart:async::Future::asStream#0`
- [x] `dart:async::Future::ignore#0`
- [x] `dart:async::Completer::sync#0`
- [x] 测试通过

### Task A.2：Map.fromEntries + Set.symmetricDifference — ✅

- [x] `dart:collection::LinkedHashMap::_fromEntries#1`（CFE 将 Map.fromEntries 解析为此）
- [x] `dart:core::Set::symmetricDifference#1`
- [x] 测试通过

### Task A.3：Collection cast() — ✅

- [x] `dart:core::List::cast#0`
- [x] `dart:core::_GrowableList::cast#0`
- [x] `dart:core::Map::cast#0`
- [x] `dart:core::Set::cast#0`
- [x] `dart:_compact_hash::_Set::cast#0`
- [x] `dart:core::Iterable::cast#0`
- [x] 测试通过

---

## Batch B：Rectangle + MutableRectangle

### Task B.1：Rectangle 缺失方法 — ✅

- [x] `dart:math::Rectangle::containsPoint#1`
- [x] `dart:math::Rectangle::intersects#1`
- [x] `dart:math::Rectangle::intersection#1`
- [x] `dart:math::Rectangle::boundingBox#1`
- [x] 测试通过

### Task B.2：Rectangle.fromPoints — ✅

- [x] `dart:math::Rectangle::fromPoints#2`
- [x] 测试通过

### Task B.3：MutableRectangle 完整绑定 — ✅

- [x] 构造函数：`MutableRectangle::#4`、`MutableRectangle::fromPoints#2`
- [x] Getter（6）：left, top, width, height, right, bottom
- [x] Setter（4）：left=, top=, width=, height=
- [x] 继承方法：containsPoint, intersects, intersection, boundingBox
- [x] Object 方法：toString, hashCode, ==
- [x] 测试通过

---

## Batch C：Zone 补全 + UnmodifiableSetView

### Task C.1：Zone.bindBinaryCallback + handleUncaughtError — ✅

- [x] `dart:async::Zone::bindBinaryCallback#1`
- [x] `dart:async::Zone::handleUncaughtError#2`
- [x] 测试通过

### Task C.2：Zone.fork 完整参数 + ZoneSpecification — ✅

- [x] `dart:async::Zone::fork#2` 更新为支持 specification + zoneValues
- [x] `dart:async::Zone::[]#1` zone values 访问
- [x] `dart:async::ZoneSpecification::#13` 构造函数（handleUncaughtError + print）
- [x] 测试通过

### Task C.3：UnmodifiableSetView — ✅

- [x] `dart:collection::UnmodifiableSetView::#1`
- [x] length, contains, iterator, lookup, toSet
- [x] 测试通过

---

## Batch D：Comparator + 文档 + E2E

### Task D.1：Comparator 支持修复 — ✅

- [x] `SplayTreeMap::#2` 转发 compare + isValidKey
- [x] `SplayTreeSet::#2` 转发 compare + isValidKey
- [x] `HashMap::#3` 转发 equals + hashCode + isValidKey
- [x] `HashSet::#3` 转发 equals + hashCode + isValidKey
- [x] 测试通过

### Task D.2：更新文档 — ✅

- [x] 创建 `docs/tasks/phase6/batch-6.3-binding-gaps.md`
- [x] 更新 `docs/tasks/overview.md`

### Task D.3：E2E 验证测试 — ✅

- [x] Completer.sync compile+run
- [x] future.asStream().toList()
- [x] Rectangle.fromPoints + containsPoint
- [x] Map.fromEntries
- [x] Zone.fork(zoneValues) + zone value 读取
- [x] 全量 bridge 回归测试通过

---

## 决策记录

| 问题 | 决策 | 理由 |
|------|------|------|
| `cast<T>()` 实现方式 | 无参 passthrough | 解释器集合为 `List<dynamic>`，cast 返回视图等效透传 |
| `whereType<T>()` | 跳过 | CALL_HOST 无法传递具化类型参数 |
| MutableRectangle 继承方法 | 同时注册 Rectangle:: 和 MutableRectangle:: | CFE 可能解析到任一 |
| Rectangle 内部基类 | 同时注册 `_RectangleBase::` | E2E 验证发现 CFE 解析到 `_RectangleBase` |
| Map.fromEntries 双绑定 | 同时注册 `Map::fromEntries#1` 和 `LinkedHashMap::_fromEntries#1` | CFE 在不同上下文可能解析到不同名称 |
| ZoneSpecification 支持范围 | 仅 handleUncaughtError + print | 其余 handler 按需追加 |
| SplayTree isValidKey | 位置参数 | SDK API 中为 positional optional 非 named |

## 变更文件汇总

| 文件 | 变更 |
|------|------|
| `lib/src/bridge/bindings/future_bindings.dart` | +asStream, +ignore |
| `lib/src/bridge/bindings/completer_bindings.dart` | +Completer.sync |
| `lib/src/bridge/bindings/collection_bindings.dart` | +_fromEntries, +UnmodifiableSetView, comparator 修复 |
| `lib/src/bridge/bindings/set_bindings.dart` | +symmetricDifference, +cast |
| `lib/src/bridge/bindings/list_bindings.dart` | +cast |
| `lib/src/bridge/bindings/map_bindings.dart` | +cast |
| `lib/src/bridge/bindings/iterable_bindings.dart` | +cast |
| `lib/src/bridge/bindings/math_bindings.dart` | +Rectangle 方法, +MutableRectangle 全套 |
| `lib/src/bridge/bindings/zone_bindings.dart` | +bindBinaryCallback, +handleUncaughtError, fork 完整参数, +Zone.[], +ZoneSpecification |
| `test/bridge/async_bindings_test.dart` | 新测试组 |
| `test/bridge/math_bindings_test.dart` | 新测试组 |
| `test/bridge/collection_bindings_test.dart` | 新测试组 |
