# Chapter 3: 跨边界互调

## 模块定位

跨边界互调层管理 dartic 解释器与宿主 Dart VM 之间的双向调用。它解决三个核心问题：类型映射（解释器类型与 VM 类型的对应）、身份一致性（同一对象跨边界传递多次必须保持 `identical` 关系）、双向调用管理（解释器调用 VM API 和 VM 回调解释器函数）。在架构分层中，本层位于运行时（Ch2）之上，为编译器（Ch4）的符号解析和泛型系统（Ch5）的跨边界类型检查提供基础设施。

## 与其他模块的关系

| 方向 | 模块 | 接口 |
|------|------|------|
| 依赖 | Ch2 运行时 | 使用 InterpreterObject、引用栈、分发循环的 `CALL_HOST` / `GET_FIELD_DYN` 指令 |
| 依赖 | Ch1 字节码 ISA | `CALL_HOST`、`GET_FIELD_DYN`、`SET_FIELD_DYN`、`NEW_INSTANCE` 指令编码 |
| 被依赖 | Ch4 编译器 | 编译器生成 .darticb 绑定名称表，运行时加载时通过 HostBindings 做符号解析 |
| 被依赖 | Ch5 泛型 | 跨边界泛型类型检查依赖 Bridge 的类型信息（详见 Ch5） |
| 被依赖 | Ch6 异步 | async 帧的 `Completer` 桥接依赖异常传播契约（详见 Ch6） |
| 契约 | Ch7 沙箱 | `CALL_HOST` 调用计入沙箱的调用深度限制 |

## 设计决策

| 决策项 | 选择 | 备选方案与拒绝理由 | 理由 |
|--------|------|-------------------|------|
| 内部表示 | 统一 InterpreterObject | 每个类生成独立 Dart class：类数量爆炸，无法运行时创建 | 单一表示，所有解释器对象共享同一 Dart 类型 |
| 跨边界缓存 | Expando（对象 → 代理） | WeakHashMap：Dart 无标准 WeakHashMap；自建 Map 会阻止 GC 回收 | ephemeron 语义，键不可达时值也被 GC，零泄漏 |
| 继承宿主类 | 预生成 Bridge 类 | noSuchMethod 动态代理：无法通过 `is` 类型检查，且 Dart 禁止 abstract class 的 noSuchMethod 转发 | Dart 无法运行时创建类，必须编译期生成真实子类 |
| Bridge 生成工具 | build_runner + package:analyzer | 手写 Bridge：不可扩展；dart:mirrors：运行时不可用（AOT） | 静态分析 + 代码生成，可覆盖任意宿主库 |
| VM 对象进入解释器 | 直接存引用栈，通过 HostClassWrapper 路由 | 包装为 InterpreterObject：额外分配 + 身份问题 | 零拷贝，无包装开销 |
| 基本类型传递 | 直接传值（int/double/String/bool） | 统一走 ProxyManager：不可变值类型无需身份缓存，额外包装浪费 | 值类型语义，`identical(1, 1)` 在 Dart 中天然成立 |

## 核心概念

### 组件关系

```
解释器内部                      边界层                          宿主 VM
┌───────────────┐         ┌──────────────────┐          ┌───────────────┐
│ Interpreter   │         │  HostBindings    │  invoke   │               │
│ Object        │ ──ref──►│  (符号→ID 注册表) │ ────────► │  VM 函数/方法  │
│               │         ├──────────────────┤          │               │
│               │  wrap   │  ProxyManager    │          │               │
│               │ ──────► │  (Expando 双向缓存)│          │               │
│               │         ├──────────────────┤          │               │
│               │         │  GenericProxy    │ ────────► │  VM 消费侧    │
│               │         │  (通用属性/方法转发)│          │  (无类型保证)  │
│               │         ├──────────────────┤          │               │
│               │         │  CallbackProxy   │ ◄──call── │  VM 回调触发   │
│               │         │  (闭包→Dart Function)│        │  (如 list.map) │
│               │         ├──────────────────┤          │               │
│               │         │  Bridge 实例      │ ◄──call── │  VM 类型系统   │
│               │ ◄─委托── │  (extends 宿主类) │          │  (is 检查通过) │
│               │         └──────────────────┘          └───────────────┘
└───────────────┘                 │
                           ┌──────┴───────┐
                           │ BridgeGenerator│
                           │ (编译期代码生成) │
                           └──────────────┘
```

### HostBindings（宿主函数注册表）

HostBindings 将宿主 VM 的函数和方法映射为符号名到整数 ID 的注册表。Bridge 预生成库在初始化时批量注册绑定，运行时通过整数 ID 进行 O(1) 调用分发。编译器将宿主方法调用编译为 `CALL_HOST A, Bx`，其中 Bx 指向 .darticb 绑定名称表条目（含符号名和 argCount），加载时通过符号解析映射为运行时 ID（详见 Ch4）。

| 属性 | 类型 | 说明 |
|------|------|------|
| _functions | List\<Function\> | 按 ID 索引的宿主函数列表 |
| _nameToId | Map\<String, int\> | 符号名 → 运行时 ID 映射 |

**调用协议**：同一宿主方法因可选参数在不同调用点参数数量不同时，编译器生成不同的绑定表条目。`invoke(id, args)` 内部通过 `Function.apply` 执行宿主函数。

### HostClassWrapper（宿主类包装器）

HostClassWrapper 为每个需要交互的宿主类提供属性名/方法名到具体访问的分发路由。预生成库为每个宿主类生成一个 HostClassWrapper 子类（如 `$List`、`$Map`），运行时维护 `classId -> HostClassWrapper` 映射表。`GET_FIELD_DYN` / `SET_FIELD_DYN` 指令通过此表路由属性访问。

| 方法 | 签名 | 说明 |
|------|------|------|
| getProperty | (Object host, String name) -> Object? | 按名称读取宿主对象属性 |
| invokeMethod | (Object host, String name, List\<Object?\> args) -> Object? | 按名称调用宿主对象方法 |

HostClassWrapper 在转发回调参数时识别 InterpreterObject（闭包），自动通过 CallbackProxy 包装后传给宿主 API。

### ProxyManager（代理缓存管理器）

ProxyManager 通过双向 Expando 缓存维护解释器对象与 VM 代理之间的一对一映射，保证对象身份一致性。它提供两个方向的转换：`wrapForVM` 将 InterpreterObject 包装为 GenericProxy（或直接返回 Bridge 实例 / 基本类型），`unwrapForInterpreter` 将 GenericProxy 解包回 InterpreterObject（防止二次包装）。

| 属性 | 类型 | 说明 |
|------|------|------|
| _interpToProxy | Expando\<GenericProxy\> | 解释器对象 → 代理，ephemeron 语义 |
| _proxyToInterp | Expando\<InterpreterObject\> | 代理 → 解释器对象，反向查找 |

**解包规则**：

| VM 传入类型 | 处理 |
|-------------|------|
| GenericProxy | 取出内部 InterpreterObject → 存引用栈 |
| Bridge 实例 | 取出内部 InterpreterObject → 存引用栈 |
| VM 原生对象 | 直接存引用栈 |

### GenericProxy（通用代理）

GenericProxy 为没有预生成 Bridge 的解释器对象提供在 VM 侧的表示。它持有目标 InterpreterObject 的引用，通过运行时方法表转发属性访问和方法调用。`==` 运算符基于目标对象的 `identical` 比较实现，`hashCode` 使用 `identityHashCode(target)`。

| 属性 | 类型 | 说明 |
|------|------|------|
| target | InterpreterObject | 被代理的解释器对象 |
| _runtime | DarticRuntime | 用于转发方法/属性调用 |

**限制**：GenericProxy 无法通过 VM 侧的 `is` 类型检查。需要通过 `is SomeVMType` 检查的解释器类必须使用 Bridge。

### CallbackProxy（回调代理）

CallbackProxy 将解释器闭包包装为 VM 可调用的 Dart Function。它为 0-3 个参数预生成 `proxyN()` 方法，每个返回对应参数数量的 Dart 闭包（如 `proxy1()` 返回 `Object? Function(Object?)`），闭包内部通过 `_runtime.invokeClosure` 回调解释器。

| 属性 | 类型 | 说明 |
|------|------|------|
| _runtime | DarticRuntime | 用于回调解释器 |
| _closure | InterpreterObject | 解释器闭包对象 |

**参数数量覆盖**：proxy0 ~ proxy3 覆盖标准库绝大多数回调场景。4+ 参数回调极为罕见，需要时通过 `Function.apply` 处理。

**泛型签名丢失**：CallbackProxy 统一使用 `Object? Function(Object?, ...)` 签名，丢失原始回调的参数和返回类型信息。Phase 1 中宿主 API 的回调参数使用宽松类型（`dynamic`）规避。

### Bridge 类与 $BridgeMixin

Bridge 类是预生成的宿主类子类，用于解释器类 `extends` 或 `implements` 宿主类型的场景。Dart 无法在运行时动态创建类，因此需要编译期预生成。所有 Bridge 类混入 `$BridgeMixin`，通过它委托方法调用、属性读写给解释器运行时。

**$BridgeMixin 提供的委托方法**：

| 方法 | 说明 |
|------|------|
| $_invoke(method, args) | 委托方法调用给解释器 |
| $_get(name) | 委托属性读取 |
| $_set(name, value) | 委托属性写入 |

**Bridge 命名规范**：`$<宿主类名>$bridge`，如 `$StatelessWidget$bridge`。Bridge 实例持有 `DarticRuntime` 和 `InterpreterObject`（存储字段值），每个重写方法内部调用 `_runtime.invokeMethod(_target, methodName, args)` 委托给解释器。

## 工作流程

### 解释器 -> VM 调用流程（外调）

1. 编译器将宿主方法调用编译为 `CALL_HOST A, Bx` 指令，Bx 为 .darticb 绑定名称表中的本地索引
2. 运行时加载 .darticb 时，通过 `HostBindings.lookupByName` 将符号名解析为运行时 ID（详见 Ch4）
3. 分发循环执行 `CALL_HOST` 时，从引用栈取参数，调用 `HostBindings.invoke(runtimeId, args)`
4. 返回值（VM 原生对象）直接存入引用栈，后续通过 HostClassWrapper 路由访问

### VM -> 解释器回调流程（内调）

1. HostClassWrapper 在转发方法参数时检测到 InterpreterObject（闭包）
2. 创建 CallbackProxy，根据宿主方法签名的参数数量选择 `proxyN()` 生成 Dart 闭包
3. 将生成的 Dart 闭包传给宿主 API（如 `list.map(proxy.proxy1())`）
4. 宿主 API 调用闭包时，CallbackProxy 内部通过 `_runtime.invokeClosure` 回调解释器：
   a. 在 CallStack 上压入 HOST_BOUNDARY 哨兵帧（详见 Ch2）
   b. 在值栈/引用栈栈顶为回调分配新帧空间
   c. 将参数写入新帧的寄存器
   d. 调用 `drive()` 执行回调（嵌套 drive，共享 fuel 预算，详见 Ch7）
   e. 回调的 RETURN 遇到 HOST_BOUNDARY → 退出 `drive()`，控制权交还 VM
   f. 从值栈/引用栈读取返回值，恢复栈指针到回调入口前的状态

### Bridge 实例创建流程

当解释器执行 `NEW_INSTANCE` 创建一个继承宿主类的对象时：

1. 创建 InterpreterObject，分配 `classId`、`RuntimeType`、引用字段和值字段存储空间
2. 以 `classId` 查找 Bridge 工厂（`_bridgeFactories[classId]`）
3. 若工厂存在，调用工厂创建 Bridge 实例（持有 InterpreterObject 引用），返回 Bridge 实例
4. 若工厂不存在（纯内部类），直接返回 InterpreterObject。**引用栈中存储的是 Bridge 实例**（而非内部的 InterpreterObject），使 VM 侧 `is` 类型检查成立

### BridgeGenerator 生成策略

BridgeGenerator 基于 build_runner + package:analyzer，扫描目标库 API 并为每个宿主类生成三部分代码：

1. **HostClassWrapper**：为类的所有公开属性和方法生成名称分发路由
2. **Bridge 类**（仅限可继承类）：跳过 `final` 和 `sealed` 类，为可继承类生成 `extends` 子类 + `$BridgeMixin`
3. **注册代码**：生成将所有绑定 ID 写入 HostBindings 注册表的初始化函数

**分阶段覆盖计划**：

| 阶段 | 覆盖范围 |
|------|---------|
| 阶段 1（机制验证） | dart:core（List, Map, Set, String, int, double 等） |
| 阶段 2（基础库） | dart:collection, dart:math, dart:async, dart:convert, dart:typed_data |
| 阶段 3（Flutter） | widgets, material, painting, rendering 等 |

**输出目录结构**：

```
package:dartic_bridges_core/
  lib/
    src/
      dart_core/
        $list.dart        // List 的 HostClassWrapper + Bridge
        $map.dart
        $string.dart
      dart_async/
        $future.dart
        $stream.dart
    dartic_bridges_core.dart  // 统一导出 + 注册入口

package:dartic_bridges_flutter/
  lib/
    src/
      widgets/
        $stateless_widget.dart
        $stateful_widget.dart
    dartic_bridges_flutter.dart
```

## 异常跨边界传播契约

### 解释器 -> VM（解释器代码抛出异常）

| 场景 | VM 侧行为 |
|------|-----------|
| async 函数未捕获异常 | `completer.completeError(error, trace)` → VM 的 `await` 收到原始异常对象 |
| Bridge 方法中抛出 | 异常自然传播到 VM 调用者（Bridge 方法是 VM 级别的方法） |
| CallbackProxy 执行中抛出 | 异常自然传播到触发回调的 VM 代码（如 `list.forEach` 内部） |

**异常类型保留**：解释器抛出的 `throw MyException()` 创建的是 InterpreterObject。跨边界时通过 `ProxyManager.wrapForVM()` 包装为 GenericProxy。VM 侧 `catch (e)` 捕获到的是 GenericProxy 实例，**不是** `MyException` 类型——因此 `on MyException catch (e)` 无法匹配。

**规避方式**：如果需要 VM 侧按类型捕获，解释器代码应抛出宿主 VM 已知的异常类型（通过 `CALL_HOST` 创建 VM 异常对象后 `THROW`）。

### VM -> 解释器（VM 代码抛出异常）

| 场景 | 解释器侧行为 |
|------|-------------|
| `CALL_HOST` 执行中 VM 抛异常 | 分发循环捕获异常，查找当前帧的异常处理器表 |
| `await` 的 VM Future 带异常完成 | `errorCallback` 将异常存入 `frame.resumeException`，帧恢复后查处理器（详见 Ch6） |

**异常类型保留**：VM 异常直接存入引用栈，解释器的 `catch (e)` 可正常捕获。`on FormatException catch (e)` 通过 `INSTANCEOF` 检查 VM 对象类型，**可以正常匹配**（VM 对象支持 `is` 检查）。

### 栈追踪拼接

跨边界异常的栈追踪通过 `CombinedStackTrace` 拼接解释器帧和 VM 帧信息，提供完整的调用链追踪。

## 对象身份一致性

### 核心不变式

同一个 InterpreterObject 跨边界传递多次，VM 侧必须收到同一个代理实例。否则 `identical(proxy1, proxy2)` 返回 false，破坏 switch 模式匹配和 Zone 错误处理。

### 身份规则

| 对象类型 | 跨边界行为 | 身份保证机制 |
|---------|-----------|------------|
| InterpreterObject | 通过 ProxyManager 包装为 GenericProxy | Expando 缓存，ephemeron 语义 |
| Bridge 实例 | 直接传递（已是 VM 类型） | 对象本身即 VM 实例 |
| 基本类型（int/double/String/bool） | 直接传值，不经过 ProxyManager | 不可变值类型，Dart 小整数缓存 + String 驻留 |
| VM 原生对象 | 直接存引用栈，不包装 | 对象本身即 VM 实例 |

Expando 内部使用 ephemeron 语义——键不可达时值也被 GC，不会内存泄漏。

## 关键约束与边界条件

| 约束 | 值 | 来源 |
|------|-----|------|
| CALL_HOST 绑定索引宽度 | 16 位（Bx），最多 65536 个绑定 | Ch1 ABx 编码格式 |
| CallbackProxy 参数上限 | 0-3 个（proxy0 ~ proxy3） | 标准库回调分析；4+ 参数走 Function.apply |
| Bridge 覆盖限制 | 仅 extends / implements，不含 mixin | Phase 1 范围限制 |
| GenericProxy 类型检查 | 无法通过 VM 侧 `is` 检查 | Dart 类型系统限制，需 Bridge 才能通过 |
| 异常类型跨边界 | 解释器异常到 VM 侧变为 GenericProxy，`on Type catch` 失效 | InterpreterObject 非 VM 类型 |
| Expando 缓存容量 | 无固定上限，随 GC 自动回收 | ephemeron 语义 |

## 已知局限与演进路径

> **Phase 2**：回调类型特化。BridgeGenerator 分析宿主方法签名，为常见回调类型预生成特化 proxy 变体（如 `int Function(String)` -> 保留原始类型信息的闭包），消除泛型签名丢失问题。触发条件：回调边界因类型不匹配导致运行时错误。

> **Phase 2**：Mixin 组合 Bridge 支持。生成 `class $State$bridge<T> extends State<T> with SingleTickerProviderStateMixin` 形式的 Bridge，处理 mixin 方法的委托转发和 `super.xxx` 分发路径，保证多 mixin 线性化顺序与解释器虚方法表一致。触发条件：Flutter 应用需要 `SingleTickerProviderStateMixin`、`AutomaticKeepAliveClientMixin` 等常用 mixin。

> **Phase 2**：noSuchMethod 接口代理。对于 implements 宿主接口但不 extends 具体类的场景，通过 noSuchMethod 转发实现轻量级代理，减少预生成 Bridge 的数量。触发条件：Bridge 数量膨胀导致包体积过大。

> **Phase 2**：跨边界异常类型保留。研究将解释器异常包装为 VM 可识别类型的方案，使 `on MyException catch (e)` 在 VM 侧可匹配。触发条件：跨边界异常处理成为实际开发痛点。

## 附录：参考实现

<details>
<summary>ProxyManager.wrapForVM 核心逻辑</summary>

```dart
Object wrapForVM(Object obj) {
  if (obj is InterpreterObject) {
    var proxy = _interpToProxy[obj];
    if (proxy != null) return proxy;  // 缓存命中，保证 identical
    proxy = GenericProxy(obj, _runtime);
    _interpToProxy[obj] = proxy;
    _proxyToInterp[proxy] = obj;
    return proxy;
  }
  return obj;  // Bridge 实例或基本类型直接返回
}
```

</details>

<details>
<summary>Bridge 实例创建伪代码</summary>

```dart
Object createInstance(int classId, RuntimeType type) {
  final interp = InterpreterObject(
    classId: classId, runtimeType: type,
    refFieldCount: classInfo.refFieldCount,
    valueFieldCount: classInfo.valueFieldCount,
  );
  final bridgeFactory = _bridgeFactories[classId];
  if (bridgeFactory != null) return bridgeFactory(this, interp);
  return interp;
}
```

</details>
