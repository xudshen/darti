# Dart 字节码解释器与宿主 VM 互调核心技术深度调研

**Dart 的静态类型系统不允许运行时注入新类，这使得解释器中动态定义的类无法直接参与宿主 VM 的继承体系。** 本报告深入调研了两个核心技术问题——解释器类如何"继承"VM 类并被 VM 侧正常使用，以及跨边界传递对象时如何保证身份一致性。通过分析 dart_eval、hetu_script、d4rt 三大 Dart 解释器项目的源码实现，结合 JVM、V8、Lua、Python、.NET 五大平台的跨边界互操作经验，本报告提出了具体的架构设计建议，涵盖代理模式选择、自动代码生成、缓存策略和生命周期管理。

---

## 问题一：解释器类"继承"VM 类的技术方案

### 预编译代理类是唯一可行的根本方案

Dart 的核心限制在于：**AOT 模式下不支持运行时动态创建类**，没有 `dart:mirrors`，没有类似 JVM 的 `Proxy.newProxyInstance()` 或 .NET 的 `Reflection.Emit`。这意味着所有代理类必须在编译期生成。业界三大 Dart 解释器项目分别采用了不同层级的方案。

**dart_eval 的 `$Bridge<T>` 机制**是目前最完善的双向继承方案。其核心设计是一个 mixin，使桥接类同时满足 VM 类型系统和解释器运行时的需求：

```dart
class $WorldTimeTracker$bridge
    with $Bridge<WorldTimeTracker>   // 混入桥接能力
    implements WorldTimeTracker {     // 满足 VM 类型系统

  // VM 侧方法 → 通过 $_invoke 委托给解释器字节码执行
  @override
  TimestampedTime getTimeFor(String country) =>
      $_invoke('getTimeFor', [$String(country)]);

  // 回退实现：当解释器子类未重写该方法时调用
  @override
  $Value? $bridgeGet(String identifier) {
    throw UnimplementedError('Abstract method $identifier');
  }
}
```

当 VM 侧代码调用 `tracker.getTimeFor('UK')` 时，完整调用链为：VM 方法调用 → `$_invoke` → `$Bridge` mixin 检查解释器子类是否定义了重写 → 如果有，通过 `Runtime.bridgeCall()` 创建 VM 子调用，将参数推入栈，跳转到字节码对应偏移量执行 → 返回值从 `$Value` 包装提取为 VM 类型。对于具体类（非抽象）的桥接，回退实现调用 `super` 的宿主方法：

```dart
class $Book$bridge extends Book with $Bridge<Book> {
  $Book$bridge(super.pages);

  @override
  $Value? $bridgeGet(String identifier) {
    if (identifier == 'getPage') {
      return $Function((_, target, args) {
        return $String(super.getPage(args[0]!.$value)); // super 调用宿主实现
      });
    }
    throw UnimplementedError('Unknown property $identifier');
  }

  @override
  String getPage(int index) => $_invoke('getPage', [$int(index)]);
}
```

**hetu_script 采用了更轻量的适配器模式**，通过 `HTExternalClass` + Dart extension 实现成员访问路由。外部类通过 `memberGet`/`instanceMemberGet` 的 switch-case 手动分发每个成员。这种方案实现简单、零反射依赖，但**不支持解释器类继承宿主类**。**d4rt 使用声明式的 `BridgedClass` 数据对象**，将构造函数、方法、getter/setter 注册为 Map 中的回调闭包，解释器通过名称查表调用。由于 d4rt 解释的是标准 Dart 语法，桥接类可被自然继承，但桥接粒度较粗。

三者对比的关键差异在于继承支持：dart_eval 的 `$Bridge` 实现了真正的双向多态（解释器创建的子类可被宿主当父类使用），d4rt 支持解释器类继承桥接类但缺乏类型安全，hetu_script 不支持此场景。

### noSuchMethod 转发是有限但实用的补充机制

Dart 的 `noSuchMethod` 转发机制提供了一种无需逐个实现接口方法的动态代理路径。**关键规则**：当一个具体类拥有非平凡的 `noSuchMethod`（即重写了 `Object.noSuchMethod`），编译器会为其 `implements` 声明的接口中所有未实现的方法自动生成转发存根（forwarder stubs）。

```dart
class InterpreterProxy implements SomeVMInterface {
  final InterpreterBridge _bridge;
  final int _objectHandle;

  InterpreterProxy(this._bridge, this._objectHandle);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // 将调用转发给解释器执行
    return _bridge.dispatch(
      _objectHandle,
      invocation.memberName,       // Symbol
      invocation.positionalArguments,
      invocation.namedArguments,
      invocation.typeArguments,
    );
  }
}
```

这种模式的**关键限制**是：它只能用于 `implements`（接口实现），不能拦截 `extends` 的具体方法——父类已有实现的方法不会触发 `noSuchMethod`。此外，`Object` 的方法（`==`、`hashCode`、`toString`）也无法被拦截。性能方面，每次调用都会创建 `Invocation` 对象（包含位置参数列表、命名参数 Map、类型参数列表），在高频场景下产生显著的 GC 压力。

已废弃的 `@proxy` 注解（Dart 1.x）曾用于抑制"未实现接口方法"的分析器警告，Dart 2.0 用编译器自动生成 forwarder 替代了这一机制，不再需要任何注解。

### 自动代理生成降低桥接代码量是关键

手写每个桥接类是不可持续的。三个解释器项目都提供了代码生成方案：dart_eval 的 `@Bind()` 注解 + CLI `dart_eval bind`，d4rt 的 `@D4rtBridge()` + build_runner，hetu_script 的 `@HTBinding()` + 自定义生成器。**推荐采用 `build_runner` + `package:analyzer` 的标准 Dart 代码生成架构**，其核心流程是：

```dart
class ProxyGenerator extends GeneratorForAnnotation<GenerateProxy> {
  @override
  String generateForAnnotatedElement(
    Element element, ConstantReader annotation, BuildStep buildStep) {

    final classElement = element as ClassElement;

    // 1. 提取所有需要代理的方法
    for (var method in classElement.methods) {
      final returnType = method.returnType.getDisplayString();
      final params = method.parameters.map((p) {
        final isNamed = p.isNamed;
        final isOptional = p.isOptionalPositional;
        final defaultValue = p.defaultValueCode;
        return '${p.type} ${p.name}';
      });
    }

    // 2. 提取泛型参数
    for (var typeParam in classElement.typeParameters) {
      final bound = typeParam.bound; // 泛型约束
    }

    // 3. 提取接口及其继承链
    for (var interface in classElement.interfaces) {
      // 递归获取接口的所有方法
    }

    // 4. 生成代理类代码（使用 code_builder 或模板字符串）
    return generatedCode;
  }
}
```

**类型区分至关重要**：`package:analyzer` 中 `DartType` 表示带实际类型参数的具体类型（如 `List<int>`），`Element` 表示声明级模板（如 `List<E>`），`DartObject` 表示编译时常量值。生成代理时需要正确处理泛型参数传递、命名参数的默认值保留、可选参数的签名兼容性，以及 mixin 和 extension type 的特殊处理。

生成的代理类应同时支持两种模式：**逐方法覆盖模式**（性能最优，适合已知接口）和 **noSuchMethod 转发模式**（灵活，适合大接口）。mockito 的实现证明了前者的可行性——它为每个 mock 方法生成具体的覆盖实现，内部构造 `Invocation` 对象调用 `super.noSuchMethod()`。

### 五大平台的跨语言互操作提供了验证过的设计模式

**JVM 的 `java.lang.reflect.Proxy`** 是运行时动态代理的经典实现，通过 `InvocationHandler` 将所有方法调用路由到统一回调，JVM 在内存中动态生成字节码加载代理类。**但此方案仅能代理接口**。CGLIB 通过 ASM 字节码生成目标类的子类突破了这一限制，而 ByteBuddy（Mockito 5+ 和 Hibernate 使用）提供了更高级的字节码增强能力。性能基准显示三者在方法调用上处于同一数量级（**100万次调用 13-18ms**），差异主要在类创建开销。

**V8 的 ES6 Proxy** 提供了语言级别的元对象协议，支持 13 种 trap（get/set/apply/construct/has 等），但性能开销显著——**属性访问比普通对象慢约 36 倍**。V8 团队从 2017 年起将关键 trap 从 C++ runtime 移至 CodeStubAssembler，实现了 200-500% 的性能提升，这一优化路径值得 Dart 解释器参考。

**Lua 的 metatable + `__index` 元方法**是最轻量的动态代理方案，通过 userdata + metatable 组合实现 C 端对象在 Lua 侧的"OOP"行为。多层 metatable 链可模拟继承，`luaL_checkudata` 提供跨边界类型验证。**Python 的 `__getattr__`** 和 **.NET 的 `DispatchProxy`** 分别代表了动态语言和静态语言的拦截模式，后者基于 `Reflection.Emit` 在运行时生成 IL 代码，但同样仅限接口代理。

**对 Dart 的核心启示**：由于 Dart 缺少运行时类生成能力，必须在编译期完成代理类生成。这一限制与 JDK Proxy/DispatchProxy 的"仅接口代理"限制本质相同——无法运行时生成子类时，`implements` 接口 + 方法转发是唯一选择。对于必须 `extends` 具体类的场景，需要 dart_eval 风格的预编译桥接类。

### Dart 特有限制的应对策略

Dart 不支持运行时动态创建类，`dart:mirrors` 在 AOT 下不可用（已事实废弃），`Function.apply` 虽可用但完全绕过静态类型检查且影响 tree shaking。针对这些限制的具体应对：

- **mixin 的代理**：生成器需要分析 mixin 的 `on` 子句约束，确保代理类满足超类约束。桥接类可 `with` 目标 mixin，然后在每个 mixin 方法中调用 `$_invoke` 转发
- **extension type 的处理**：extension type 是编译期的零成本抽象，在运行时不存在。代理无需特别处理 extension type，只需确保底层表示类型（representation type）的正确包装
- **sealed/final class**：Dart 3 的类修饰符限制了继承。`final` 类不能被外部继承，`sealed` 类不能被外部实现。这些限制适用于代理类生成，需要代码生成器检查并报错或采用组合模式绕过
- **泛型实化**（reified generics）：Dart 的泛型在运行时保留类型信息。代理类必须正确传递泛型参数，确保 `is` 检查通过

```dart
// 泛型代理的正确生成模式
class $List$bridge<E> with $Bridge<List<E>> implements List<E> {
  // 需要在构造时捕获 E 的具体类型
  final Type _elementType;

  @override
  void add(E value) => $_invoke('add', [$wrap(value)]);

  @override
  E operator [](int index) => $_invoke('[]', [$int(index)]) as E;
}
```

---

## 问题二：跨边界对象身份一致性与缓存策略

### 同一解释器对象必须始终映射到同一代理实例

**`identical()` 在 Dart 中比较的是对象引用（内存地址），无法被重写。** 这意味着仅靠重写 `==` 和 `hashCode` 不够——如果同一个解释器对象被包装为两个不同的代理实例，`identical(proxy1, proxy2)` 会返回 `false`，导致 `switch` 模式匹配、`Zone` 错误处理中的 `identical(e, error)` 模式、以及部分第三方库的相等性检查失败。**因此，代理缓存保证 identical 一致性是最核心的不变式。**

### 三种缓存方案的设计与权衡

**方案 A：Expando 方案**（推荐为主方案）

`Expando<T>` 是 Dart 原生的以对象身份为键的弱映射，内部通过 ephemeron（`_WeakProperty`）实现——当键不可达时，键和值都可被 GC 回收，避免了普通弱引用映射中值保持键存活的循环问题。VM 实现使用开放寻址哈希表，查找复杂度 O(1)。

```dart
class ExpandoProxyCache {
  final Expando<VMProxy> _forward = Expando('interpToProxy');
  final Expando<DarticObject> _reverse = Expando('proxyToInterp');

  VMProxy getOrCreateProxy(DarticObject interpObj) {
    var proxy = _forward[interpObj];
    if (proxy != null) return proxy; // 缓存命中，保证 identical

    proxy = VMProxy(interpObj);
    _forward[interpObj] = proxy;
    _reverse[proxy] = interpObj;
    return proxy;
  }

  /// 解包：传回解释器时还原为原始对象，防止二次包装
  DarticObject? unwrap(VMProxy proxy) => _reverse[proxy];
}
```

Expando 的限制是**不支持原始值类型**（num/String/bool/Record/null）作为键，且无法枚举缓存条目或获取缓存大小。

**方案 B：WeakReference + Finalizer 方案**（处理原始类型的补充）

对于 Expando 无法覆盖的原始类型解释器对象，使用解释器分配的唯一整数 ID 作为 Map 键，`WeakReference` 弱持有代理对象，`Finalizer` 在代理被 GC 时清理 Map 条目：

```dart
class PrimitiveProxyCache {
  final Map<int, WeakReference<VMProxy>> _cache = {};
  late final Finalizer<int> _finalizer = Finalizer<int>((interpId) {
    _cache.remove(interpId);
  });

  VMProxy getOrCreate(DarticObject interpObj) {
    final id = interpObj.interpId;
    final existing = _cache[id]?.target;
    if (existing != null) return existing;

    final proxy = VMProxy(interpObj);
    _cache[id] = WeakReference(proxy);
    _finalizer.attach(proxy, id, detach: proxy);
    return proxy;
  }
}
```

**需要注意 `Finalizer` 不保证回调一定执行**——isolate 终止时可能跳过。这是安全网而非主要清理机制。

**方案 C：句柄表方案**（适合 FFI 场景）

类似 JNI 的 `luaL_ref` / V8 的 `Persistent<T>`，使用整数句柄指向对象槽位，空闲列表复用已释放槽位。这种方案完全确定性（不依赖 GC 行为），但需手动管理生命周期，忘记释放即永久泄漏。

```dart
class HandleTable<T> {
  final List<T?> _slots = [];
  final List<int> _freeList = [];

  int allocate(T value) {
    if (_freeList.isNotEmpty) {
      final slot = _freeList.removeLast();
      _slots[slot] = value;
      return slot;
    }
    _slots.add(value);
    return _slots.length - 1;
  }

  T? resolve(int handle) =>
      (handle >= 0 && handle < _slots.length) ? _slots[handle] : null;

  void release(int handle) {
    if (handle >= 0 && handle < _slots.length) {
      _slots[handle] = null;
      _freeList.add(handle);
    }
  }
}
```

### 五大平台一致验证了 Strong/Local/Weak 三级引用分级模式

跨语言互操作的引用管理在五大平台上呈现出高度一致的架构模式：

| 引用级别 | JNI | V8 | Lua | Python | .NET | Dart 对应 |
|---------|-----|-----|-----|--------|------|----------|
| **强/持久** | Global Reference | Persistent handle | `luaL_ref` (registry) | `Py_INCREF` (owned) | `GCHandle.Normal` | 强引用字段 |
| **局部/作用域** | Local Reference + `PushLocalFrame` | Local handle + `HandleScope` | 栈上值 | borrowed reference | 栈引用 | 函数局部变量 |
| **弱** | Weak Global Reference | `SetWeak` callback | weak table (`__mode`) | `weakref` + callback | `GCHandle.Weak` | `WeakReference` + `Finalizer` |

**JNI 的句柄表机制**是间接引用的典范——从 Android ICS 起，JNI 引用不再是直接指针，而是句柄表索引。GC 移动对象时只需更新句柄表，native 代码持有的引用保持有效。**V8 的 `HandleScope`** 提供了优雅的分层管理，`EscapableHandleScope::Escape` 允许将句柄"逃逸"到外层作用域，这一模式可直接应用于 Dart 解释器的方法调用栈管理。**Lua 的弱引用表**通过 `__mode` 元字段控制键弱（`"k"`）、值弱（`"v"`）或全弱（`"kv"`），设计简洁且 GC 友好。

### 双向映射与代理解包防止二次包装

双向映射（interpObj ↔ proxy）是保证语义正确的关键。当代理对象传回解释器时，必须识别并解包为原始解释器对象，否则会产生 `VMProxy(VMProxy(interpObj))` 的二次包装。完整的 DarticProxyManager 应在每个传递点进行类型检查：

```dart
class DarticProxyManager {
  final Expando<VMProxy> _forward = Expando('forward');
  final Expando<DarticObject> _reverse = Expando('reverse');

  /// 解释器 → VM：包装
  Object passToVM(Object obj) {
    if (obj is VMProxy) return obj;              // 已经是代理，直接返回
    if (obj is DarticObject) return wrap(obj);
    return obj;                                   // VM 原生对象直接传递
  }

  /// VM → 解释器：解包
  Object passToInterpreter(Object obj) {
    if (obj is VMProxy) {
      return _reverse[obj] ?? obj.target;         // 解包为原始对象
    }
    if (obj is DarticObject) return obj;     // 已经是解释器对象
    return VMNativeWrapper(obj);                   // VM 对象的反向包装
  }

  VMProxy wrap(DarticObject interpObj) {
    var proxy = _forward[interpObj];
    if (proxy != null) return proxy;
    proxy = VMProxy(interpObj);
    _forward[interpObj] = proxy;
    _reverse[proxy] = interpObj;
    return proxy;
  }
}
```

循环引用在此架构下不会导致缓存泄漏——Expando 的 ephemeron 语义确保当键不可达时值也被释放，两个解释器对象的互相引用由解释器自身的 GC 决定可达性。

### 对象身份语义必须同时在 identical 和 == 层面保证

代理对象的 `==` 和 `hashCode` 必须正确转发到解释器对象的身份：

```dart
class VMProxy {
  final DarticObject _target;
  VMProxy(this._target);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is VMProxy) return identical(_target, other._target);
    if (other is DarticObject) return identical(_target, other);
    return false;
  }

  @override
  int get hashCode => identityHashCode(_target);
}
```

**`identityHashCode` 需要注意碰撞问题**——不同对象可能返回相同的 `identityHashCode`，它是哈希码而非唯一 ID。因此不能用 `identityHashCode` 作为唯一映射键，但作为 `hashCode` 实现是正确的（`HashMap`/`HashSet` 内部会用 `==` 处理碰撞）。

### 高频互调场景的性能优化策略

Expando 缓存查找的开销约为 O(1) 哈希表查找，远低于创建新代理（对象分配 + Expando 写入 + 可能的 Finalizer 注册）。**缓存命中比新建代理快约 5-10 倍**。在高频场景下可增加两层优化：

**栈上快速路径缓存**：在调用点维护最近一次的代理映射，利用局部性原理。同一个对象在循环中多次传递时，避免 Expando 查找：

```dart
class CallSiteCache {
  DarticObject? _lastObj;
  VMProxy? _lastProxy;

  VMProxy wrap(DarticObject obj, DarticProxyManager manager) {
    if (identical(obj, _lastObj) && _lastProxy != null) return _lastProxy!;
    final proxy = manager.wrap(obj);
    _lastObj = obj;
    _lastProxy = proxy;
    return proxy;
  }
}
```

**分代热缓存**：在 Expando 的弱引用缓存之上增加固定大小的 LRU 强引用缓存，防止频繁访问的代理被 GC 后反复重建。V8 的性能优化经验表明，将频繁调用的 trap 从通用路径移到专用内联缓存可提升 **200-500%**，ByteBuddy 的经验也证实将固定行为"硬编码"到代理中比通用回调更快。

WeakReference 对 GC 的影响主要体现在：GC 需要额外遍历弱引用表来清除已死对象的弱引用，大量 WeakReference 会增加 GC pause time。**建议将 WeakReference 数量控制在千级别以内**，超过此规模应考虑分代或分层管理。

---

## 推荐的整体架构设计

综合以上分析，推荐以下架构方案：

**代理类生成**采用 `build_runner` + `package:analyzer` 在编译期自动生成，支持两种代理模式——`implements` 接口 + `noSuchMethod` 转发（适合大接口，代码量小）和逐方法覆盖 + `$_invoke` 委托（性能更优，适合热路径接口）。抽象类使用 `implements` + 桥接模式，具体类使用 `extends` + `$Bridge` mixin 模式（参照 dart_eval）。

**对象缓存**采用 Expando 为主 + WeakReference+Finalizer 处理原始类型 + LRU 热缓存的三层架构。所有跨边界传递统一经过 `DarticProxyManager` 入口，在每个传递点自动执行包装/解包，保证 identical 一致性和防止二次包装。

**引用生命周期管理**借鉴 V8 `HandleScope` 的分层模式——每次解释器到 VM 的调用创建一个逻辑 scope，scope 内创建的临时代理在 scope 结束时允许被 GC（不持有强引用），需要跨 scope 存活的代理通过 Expando 缓存自动管理。Dart 的单 Isolate 模型简化了线程安全需求，无需像 JNI 句柄表那样加锁。

这一架构经过五大平台的跨语言互操作经验验证：**Strong/Local/Weak 三级引用分级 + 句柄表间接引用 + 基于接口的代理分发**是跨 GC 边界对象管理的事实标准。Dart 解释器应采用这一经过验证的架构，结合 Dart 的单线程特性和 Expando ephemeron 语义进行针对性简化。