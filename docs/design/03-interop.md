# Chapter 3: 跨边界互调

## 设计决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 内部表示 | 统一 InterpreterObject | 单一表示，简化实现 |
| 跨边界缓存 | Expando（对象 → 代理） | 弱引用，GC 友好，保证 identical 一致性 |
| 继承宿主类 | 预生成 Bridge 类 | Dart 无法运行时创建类，必须编译期生成 |
| Bridge 生成 | 预生成库（build_runner） | 先 dart:core/collection/math/async/convert，后 Flutter |
| VM 对象进入解释器 | 直接存引用栈，通过 Bridge 方法表操作 | 零拷贝，无包装 |
| 基本类型 | 直接传递（int/double/String/bool） | 不可变值类型，无需身份缓存 |

## 架构总览

```
解释器内部                    边界层                     宿主 VM
┌──────────────┐         ┌───────────────┐         ┌──────────────┐
│ Interpreter  │ ──────► │ ProxyManager  │ ──────► │ VM 代码       │
│ Object       │         │ (Expando 缓存) │         │              │
│              │ ◄────── │               │ ◄────── │              │
└──────────────┘         └───────────────┘         └──────────────┘
                              │
                         ┌────┴────┐
                         │ Bridge  │  (extends 宿主类时)
                         │ 实例    │
                         └─────────┘
```

## 方向一：解释器 → VM（外调）

### 宿主函数注册表

Bridge 预生成库提供绑定注册表，将宿主函数/方法映射为符号名 → 整数 ID：

```dart
class HostBindings {
  final List<Function> _functions = [];
  final Map<String, int> _nameToId = {};

  int register(String name, Function fn) {
    final id = _functions.length;
    _functions.add(fn);
    _nameToId[name] = id;
    return id;
  }

  /// 按名称查找运行时 ID（加载 .darticb 时符号解析用）
  int? lookupByName(String name) => _nameToId[name];

  Object? invoke(int id, List<Object?> args) {
    return Function.apply(_functions[id], args);
  }
}
```

编译器将 `list.add(item)` 编译为 `CALL_HOST A, Bx`（A=baseReg, Bx=本地绑定索引，16-bit）。Bx 指向 .darticb 绑定名称表中的条目，每个条目包含符号名和参数数量（argCount）。同一宿主方法因可选参数在不同调用点参数数量不同时，编译器生成不同的绑定表条目。运行时加载 .darticb 时通过符号解析将本地索引映射为运行时 ID（详见 Chapter 4 加载时符号解析）。

### 包装器类（结构化访问）

预生成库为每个需要交互的宿主类提供包装器，通过属性名/方法名分发：

```dart
/// 预生成的 List 包装器
class $List extends HostClassWrapper {
  @override
  Object? getProperty(Object host, String name) => switch (name) {
    'length' => (host as List).length,
    'isEmpty' => (host as List).isEmpty,
    'first' => (host as List).first,
    _ => throw DarticError('Unknown property: List.$name'),
  };

  @override
  Object? invokeMethod(Object host, String name, List<Object?> args) => switch (name) {
    'add' => (host as List).add(args[0]),
    'removeAt' => (host as List).removeAt(args[0] as int),
    'contains' => (host as List).contains(args[0]),
    'map' => (host as List).map(_toFunction1(args[0])),
    'where' => (host as List).where(_toPredicate(args[0])),
    _ => throw DarticError('Unknown method: List.$name'),
  };
}
```

运行时维护 `classId → HostClassWrapper` 的映射表。`GET_FIELD_DYN` / `SET_FIELD_DYN` 指令通过此表路由属性访问。

### InterpreterObject 跨边界传递

当 InterpreterObject 需要传给 VM 代码时（如作为宿主方法的参数），通过 ProxyManager 包装：

```dart
class ProxyManager {
  final Expando<GenericProxy> _interpToProxy = Expando('i2p');
  final Expando<InterpreterObject> _proxyToInterp = Expando('p2i');
  final DarticRuntime _runtime;

  /// 解释器 → VM：按需包装
  Object wrapForVM(Object obj) {
    if (obj is InterpreterObject) {
      var proxy = _interpToProxy[obj];
      if (proxy != null) return proxy;  // 缓存命中，保证 identical

      proxy = GenericProxy(obj, _runtime);
      _interpToProxy[obj] = proxy;
      _proxyToInterp[proxy] = obj;
      return proxy;
    }
    // Bridge 实例或基本类型直接返回
    return obj;
  }

  /// VM → 解释器：解包（防止二次包装）
  Object unwrapForInterpreter(Object obj) {
    if (obj is GenericProxy) {
      return _proxyToInterp[obj] ?? obj.target;
    }
    if (obj is InterpreterObject) return obj;
    return obj;  // VM 原生对象直接存入引用栈
  }
}
```

### GenericProxy（通用代理）

对于没有预生成 Bridge 的解释器类，GenericProxy 提供基本的属性/方法访问：

```dart
class GenericProxy {
  final InterpreterObject target;
  final DarticRuntime _runtime;

  GenericProxy(this.target, this._runtime);

  /// 通过运行时方法表转发属性访问
  Object? getProperty(String name) =>
      _runtime.getField(target, name);

  Object? invokeMethod(String name, List<Object?> args) =>
      _runtime.invokeMethod(target, name, args);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is GenericProxy) return identical(target, other.target);
    if (other is InterpreterObject) return identical(target, other);
    return false;
  }

  @override
  int get hashCode => identityHashCode(target);
}
```

**限制**：GenericProxy 无法通过 VM 侧的 `is` 类型检查。这是已知限制——如果某个解释器类的实例需要通过 `is SomeVMType` 检查，该类必须使用 Bridge。

## 方向二：VM → 解释器（内调）

### VM 对象直接存引用栈

VM 对象传入解释器时不做任何包装，直接作为 `Object?` 存入引用栈：

```dart
// CALL_HOST 返回 VM 原生对象
case OpCode.CALL_HOST:
  final a = (instr >> 8) & 0xFF;     // baseReg
  final bx = (instr >> 16) & 0xFFFF; // 本地绑定索引 (16-bit)
  final entry = module.bindingTable[bx]; // 符号解析后的绑定条目
  final args = [for (int i = 0; i < entry.argCount; i++) _rs.slots[a + i]];
  final result = hostBindings.invoke(entry.runtimeId, args);
  _rs.slots[a] = result;
```

解释器通过 `GET_FIELD_DYN` / `CALL_VIRTUAL` 访问这些对象时，走 HostClassWrapper 路由。

### 回调代理：解释器函数传给 VM

当解释器的闭包/函数需要作为回调传给 VM API（如 `list.map(callback)`），需要包装为 VM 可调用的 Dart 闭包：

```dart
class CallbackProxy {
  final DarticRuntime _runtime;
  final InterpreterObject _closure;  // 解释器闭包对象

  CallbackProxy(this._runtime, this._closure);

  // 不同参数数量的代理闭包
  Object? Function() proxy0() =>
      () => _runtime.invokeClosure(_closure, []);

  Object? Function(Object?) proxy1() =>
      (a) => _runtime.invokeClosure(_closure, [a]);

  Object? Function(Object?, Object?) proxy2() =>
      (a, b) => _runtime.invokeClosure(_closure, [a, b]);

  Object? Function(Object?, Object?, Object?) proxy3() =>
      (a, b, c) => _runtime.invokeClosure(_closure, [a, b, c]);

  // 4+ 参数回调极为罕见（标准库中几乎不存在），需要时通过 Function.apply 处理
}
```

**已知局限：泛型签名丢失**。CallbackProxy 统一使用 `Object? Function(Object?, ...)` 签名，丢失了原始回调的参数和返回类型信息。在严格类型检查场景（如 `List<int>.map<String>((int x) => x.toString())` 中回调的 `int → String` 签名）可能触发运行时类型错误。

**Phase 1 Workaround**：宿主 API 的回调参数使用宽松类型（`dynamic`），避免在回调边界做严格类型检查。

> **Phase 2**：Bridge 生成器分析需要回调的宿主方法签名，为常见回调类型预生成特化 proxy 变体（如 `int Function(String)` → `(String s) => _runtime.invokeClosure(_closure, [s]) as int`），保留原始类型信息。

HostClassWrapper 在转发回调参数时识别 InterpreterObject（闭包），自动创建 CallbackProxy：

```dart
// $List 包装器中的 map 方法
case 'map':
  final closure = args[0] as InterpreterObject;
  final proxy = CallbackProxy(_runtime, closure);
  return (host as List).map(proxy.proxy1());
```

## Bridge 类（extends/implements 宿主类）

### 何时需要 Bridge

解释器类 `extends` 或 `implements` 宿主 VM 类时，必须有对应的 Bridge 类。这是因为 Dart 无法在运行时动态创建类——VM 需要在编译时知道具体类型。

```dart
// 解释器代码
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) { ... }
}

// 必须有预生成的 Bridge
class $StatelessWidget$bridge extends StatelessWidget with $BridgeMixin {
  final DarticRuntime _runtime;
  final InterpreterObject _target;

  $StatelessWidget$bridge(this._runtime, this._target);

  @override
  Widget build(BuildContext context) {
    return _runtime.invokeMethod(
      _target, 'build', [context]
    ) as Widget;
  }
}
```

### $BridgeMixin

所有 Bridge 类共享的 mixin，提供通用的解释器委托能力：

```dart
mixin $BridgeMixin {
  DarticRuntime get _runtime;
  InterpreterObject get _target;

  /// 委托方法调用给解释器
  Object? $_invoke(String method, List<Object?> args) =>
      _runtime.invokeMethod(_target, method, args);

  /// 委托属性读取
  Object? $_get(String name) =>
      _runtime.getField(_target, name);

  /// 委托属性写入
  void $_set(String name, Object? value) =>
      _runtime.setField(_target, name, value);
}
```

### Bridge 实例的创建

当解释器执行 `NEW_INSTANCE` 创建一个继承宿主类的对象时：

1. 先创建 InterpreterObject（存储字段值）
2. 查找对应的 Bridge 工厂
3. 创建 Bridge 实例，持有 InterpreterObject 引用
4. **引用栈中存储 Bridge 实例**（而非 InterpreterObject）

```dart
// 运行时的创建逻辑
Object createInstance(int classId, RuntimeType type) {
  final interp = InterpreterObject(
    classId: classId,
    runtimeType: type,
    refFieldCount: classInfo.refFieldCount,
    valueFieldCount: classInfo.valueFieldCount,
  );

  // 检查是否需要 Bridge
  final bridgeFactory = _bridgeFactories[classId];
  if (bridgeFactory != null) {
    return bridgeFactory(this, interp);  // 返回 Bridge 实例
  }
  return interp;  // 纯内部类，返回 InterpreterObject
}
```

### noSuchMethod 转发（接口代理）

对于 implements 宿主接口但不 extends 具体类的场景，未来可通过 noSuchMethod 转发实现轻量级代理。

### Mixin 组合的 Bridge 支持

> **Phase 2**：当前 Bridge 生成覆盖 `extends` 和 `implements` 场景，但未处理 mixin 组合模式。Flutter 中大量使用 mixin（如 `SingleTickerProviderStateMixin`、`AutomaticKeepAliveClientMixin`）。
>
> 需要解决：
> 1. Bridge 类如何 `with` 宿主 mixin（如 `class $State$bridge<T> extends State<T> with SingleTickerProviderStateMixin`）
> 2. mixin 方法的委托转发——mixin 中调用 `super.xxx` 时的分发路径
> 3. 多 mixin 组合的线性化顺序与解释器虚方法表的一致性
>
> Phase 1 中需要 mixin 的解释器类必须手写 Bridge 或重构为不使用 mixin。

## 异常跨边界传播契约

解释器与宿主 VM 之间异常传播遵循以下规则：

### 解释器 → VM（解释器代码抛出异常）

| 场景 | VM 侧行为 |
|------|-----------|
| async 函数未捕获异常 | `completer.completeError(error, trace)` → VM 的 `await` 收到原始异常对象 |
| Bridge 方法中抛出 | 异常自然传播到 VM 调用者（Bridge 方法是 VM 级别的方法） |
| CallbackProxy 执行中抛出 | 异常自然传播到触发回调的 VM 代码（如 `list.forEach` 内部） |

**异常类型保留**：解释器抛出的 `throw MyException()` 创建的是 `InterpreterObject`。跨边界时通过 `ProxyManager.wrapForVM()` 包装为 `GenericProxy`。VM 侧 `catch (e)` 捕获到的是 `GenericProxy` 实例，**不是** `MyException` 类型——因此 `on MyException catch (e)` 无法匹配。

**规避方式**：如果需要 VM 侧按类型捕获，解释器代码应抛出宿主 VM 已知的异常类型（通过 `CALL_HOST` 创建 VM 异常对象后 `THROW`）。

### VM → 解释器（VM 代码抛出异常）

| 场景 | 解释器侧行为 |
|------|-------------|
| `CALL_HOST` 执行中 VM 抛异常 | 分发循环捕获异常，查找当前帧的异常处理器表 |
| `await` 的 VM Future 带异常完成 | `errorCallback` 将异常存入 `frame.resumeException`，帧恢复后查处理器 |

**异常类型保留**：VM 异常直接存入引用栈，解释器的 `catch (e)` 可正常捕获。`on FormatException catch (e)` 通过 `INSTANCEOF` 检查 VM 对象类型，**可以正常匹配**（VM 对象支持 `is` 检查）。

### 栈追踪拼接

跨边界异常的栈追踪通过 `CombinedStackTrace` 拼接解释器帧和 VM 帧信息，提供完整的调用链追踪。

## 对象身份一致性

### 核心不变式

同一个 InterpreterObject 跨边界传递多次，VM 侧必须收到同一个代理实例。否则 `identical(proxy1, proxy2)` 返回 false，破坏 switch 模式匹配和 Zone 错误处理。

### Expando 保证

Expando 内部使用 ephemeron 语义——键不可达时值也被 GC。不会内存泄漏：

```dart
// 同一对象两次传递
var obj = InterpreterObject(...);
var proxy1 = proxyManager.wrapForVM(obj);  // 创建并缓存
var proxy2 = proxyManager.wrapForVM(obj);  // 缓存命中
identical(proxy1, proxy2);  // true ✓
```

### 基本类型不缓存

`int`, `double`, `String`, `bool` 直接传递值，不经过 ProxyManager：
- 不可变值类型，无身份问题
- `identical(1, 1)` 在 Dart 中为 true（小整数缓存）
- String 有驻留机制

### 防止二次包装

ProxyManager.unwrapForInterpreter 在每个 VM→解释器 传递点执行，识别 GenericProxy 并解包：

```
VM 传入 GenericProxy → unwrap → 取出 InterpreterObject → 存引用栈
VM 传入 Bridge 实例 → 取出内部的 InterpreterObject → 存引用栈
VM 传入原生对象 → 直接存引用栈
```

## Bridge 预生成库

### 分阶段覆盖

```
阶段 1（机制验证）: dart:core（List, Map, Set, String, int, double 等）
阶段 2（基础库）:   dart:collection, dart:math, dart:async, dart:convert, dart:typed_data
阶段 3（Flutter）:  widgets, material, painting, rendering 等
```

### 生成器架构

基于 build_runner + package:analyzer，扫描目标库的 API：

```dart
class BridgeGenerator extends GeneratorForAnnotation<GenerateBridge> {
  @override
  String generateForAnnotatedElement(Element element, ...) {
    final cls = element as ClassElement;

    // 生成 HostClassWrapper（属性/方法路由）
    _generateWrapper(cls);

    // 如果类可被继承，生成 Bridge 类
    if (!cls.isFinal && !cls.isSealed) {
      _generateBridge(cls);
    }

    // 生成注册代码（将绑定 ID 写入注册表）
    _generateRegistration(cls);
  }
}
```

### 输出结构

```
package:dartic_bridges_core/
  lib/
    src/
      dart_core/
        $list.dart        // List 的 HostClassWrapper + Bridge
        $map.dart
        $string.dart
        ...
      dart_async/
        $future.dart
        $stream.dart
        ...
    dartic_bridges_core.dart  // 统一导出 + 注册入口

package:dartic_bridges_flutter/
  lib/
    src/
      widgets/
        $stateless_widget.dart
        $stateful_widget.dart
        ...
    dartic_bridges_flutter.dart
```

宿主应用在初始化 DarticRuntime 时注册所需的 Bridge 库：

```dart
final runtime = DarticRuntime();
registerCoreBridges(runtime.hostBindings);      // dart:core 等
registerFlutterBridges(runtime.hostBindings);   // Flutter（可选）
runtime.loadAndRun('app.darticb');
```
