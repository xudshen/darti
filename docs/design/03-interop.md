# Chapter 3: 跨边界互调

## 模块定位

跨边界互调层管理 dartic 解释器与宿主 Dart VM 之间的双向调用。它解决三个核心问题：类型映射（解释器类型与 VM 类型的对应）、身份一致性（同一对象跨边界传递多次必须保持 `identical` 关系）、双向调用管理（解释器调用 VM API 和 VM 回调解释器函数）。在架构分层中，本层位于运行时（Ch2）之上，为编译器（Ch4）的符号解析和泛型系统（Ch5）的跨边界类型检查提供基础设施。

## 与其他模块的关系

| 方向 | 模块 | 接口 |
|------|------|------|
| 依赖 | Ch2 运行时 | 使用 DarticObject、引用栈、分发循环的 `CALL_HOST` / `GET_FIELD_DYN` 指令 |
| 依赖 | Ch1 字节码 ISA | `CALL_HOST`、`GET_FIELD_DYN`、`SET_FIELD_DYN`、`NEW_INSTANCE` 指令编码 |
| 被依赖 | Ch4 编译器 | 编译器生成 .darticb 绑定名称表，运行时加载时通过 HostBindings 做符号解析 |
| 被依赖 | Ch5 泛型 | 跨边界泛型类型检查依赖 Bridge 的类型信息（详见 Ch5） |
| 被依赖 | Ch6 异步 | async 帧的 `Completer` 桥接依赖异常传播契约（详见 Ch6） |
| 契约 | Ch7 沙箱 | `CALL_HOST` 调用计入沙箱的调用深度限制 |

## 设计决策

| 决策项 | 选择 | 备选方案与拒绝理由 | 理由 |
|--------|------|-------------------|------|
| 内部表示 | 统一 DarticObject | 每个类生成独立 Dart class：类数量爆炸，无法运行时创建 | 单一表示，所有解释器对象共享同一 Dart 类型 |
| 跨边界缓存 | Expando（对象 → 代理） | WeakHashMap：Dart 无标准 WeakHashMap；自建 Map 会阻止 GC 回收 | ephemeron 语义，键不可达时值也被 GC，零泄漏 |
| 继承宿主类 | 预生成 Bridge 类 | noSuchMethod 动态代理：无法通过 `is` 类型检查，且 Dart 禁止 abstract class 的 noSuchMethod 转发 | Dart 无法运行时创建类，必须编译期生成真实子类 |
| Bridge 生成工具 | build_runner + package:analyzer | 手写 Bridge：不可扩展；dart:mirrors：运行时不可用（AOT） | 静态分析 + 代码生成，可覆盖任意宿主库 |
| VM 对象进入解释器 | 直接存引用栈，通过 HostClassWrapper 路由 | 包装为 DarticObject：额外分配 + 身份问题 | 零拷贝，无包装开销 |
| 基本类型传递 | 直接传值（int/double/String/bool） | 统一走 DarticProxyManager：不可变值类型无需身份缓存，额外包装浪费 | 值类型语义，`identical(1, 1)` 在 Dart 中天然成立 |
| Bridge super 调用 | 预生成 super 转发器方法 | 运行时沿 super 链查找：Bridge 的 super 方法在 VM 侧，无法通过 DarticFuncProto 索引访问 | 编译期生成 `$super$methodName()` 调用 `super.methodName()`，注册到 HostBindings，编译器对 VM super 目标生成 `CALL_HOST` |
| 操作符路由命名 | Dart 标准操作符名（`+`、`[]`、`==` 等） | 自定义前缀（如 `op_plus`）：增加命名转换复杂度，与 Kernel 的 `Name.text` 不一致 | HostClassWrapper 和 HostBindings 统一使用 Dart 的规范操作符名，与 Kernel `InstanceInvocation.name.text` 一致 |
| 宿主函数调用方式 | BridgeGenerator 生成 typed wrapper 闭包 | `Function.apply` 动态调用：Dart AOT 走反射式慢路径，无法内联，是框架交互密集场景的主要性能瓶颈 | 宿主调用是热路径，BridgeGenerator 编译期已知每个绑定的精确签名，可生成统一类型 `Object? Function(List<Object?>)` 的 wrapper 闭包，运行时直接类型化调用 |

## 核心概念

### 组件关系

```
解释器内部                      边界层                          宿主 VM
┌───────────────┐         ┌──────────────────┐          ┌───────────────┐
│ Interpreter   │         │  HostBindings    │  invoke   │               │
│ Object        │ ──ref──►│  (符号→ID 注册表) │ ────────► │  VM 函数/方法  │
│               │         ├──────────────────┤          │               │
│               │  wrap   │  DarticProxyManager    │          │               │
│               │ ──────► │  (Expando 双向缓存)│          │               │
│               │         ├──────────────────┤          │               │
│               │         │  DarticProxy    │ ────────► │  VM 消费侧    │
│               │         │  (通用属性/方法转发)│          │  (无类型保证)  │
│               │         ├──────────────────┤          │               │
│               │         │  DarticCallbackProxy   │ ◄──call── │  VM 回调触发   │
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
| _functions | List\<Object? Function(List\<Object?\>)\> | 按 ID 索引的 typed wrapper 闭包列表（BridgeGenerator 生成） |
| _nameToId | Map\<String, int\> | 符号名 → 运行时 ID 映射 |

**调用协议**：同一宿主方法因可选参数在不同调用点参数数量不同时，编译器生成不同的绑定表条目。BridgeGenerator 为每个绑定生成统一签名 `Object? Function(List<Object?>)` 的 typed wrapper 闭包——闭包内部将参数列表解构后直接调用宿主函数（编译期已知精确签名，无需反射）。`invoke(id, args)` 直接调用 typed wrapper，避免 `Function.apply` 的反射开销。

### HostClassWrapper（宿主类包装器）

HostClassWrapper 为每个需要交互的宿主类提供属性名/方法名到具体访问的分发路由。预生成库为每个宿主类生成一个 HostClassWrapper 子类（如 `$List`、`$Map`），运行时维护 `classId -> HostClassWrapper` 映射表。`GET_FIELD_DYN` / `SET_FIELD_DYN` 指令通过此表路由属性访问。

| 方法 | 签名 | 说明 |
|------|------|------|
| getProperty | (Object host, String name) -> Object? | 按名称读取宿主对象属性 |
| invokeMethod | (Object host, String name, List\<Object?\> args) -> Object? | 按名称调用宿主对象方法 |

HostClassWrapper 在转发回调参数时识别 DarticClosure，自动通过 DarticCallbackProxy 包装后传给宿主 API（包装与参数转换流程详见下方 DarticCallbackProxy 节）。

**操作符路由**：操作符调用通过 `invokeMethod` 统一路由，使用 Dart 的规范操作符名作为 `name` 参数（如 `+`、`-`、`[]`、`[]=`、`==`、`<`、`>`、`unary-`）。命名与 Kernel `InstanceInvocation.name.text` 一致，无需转换。BridgeGenerator 扫描 `ProcedureKind.Operator` 的方法时，按相同命名注册到 HostClassWrapper 分发表。

### DarticProxyManager（代理缓存管理器）

DarticProxyManager 通过双向 Expando 缓存维护解释器对象与 VM 代理之间的一对一映射，保证对象身份一致性。它提供两个方向的转换：`wrapForVM` 将 DarticObject 包装为 DarticProxy（或直接返回 Bridge 实例 / 基本类型），`unwrapForInterpreter` 将 DarticProxy 解包回 DarticObject（防止二次包装）。

| 属性 | 类型 | 说明 |
|------|------|------|
| _interpToProxy | Expando\<DarticProxy\> | 解释器对象 → 代理，ephemeron 语义 |
| _proxyToInterp | Expando\<DarticObject\> | 代理 → 解释器对象，反向查找 |

**解包规则**：

| VM 传入类型 | 处理 |
|-------------|------|
| DarticProxy | 取出内部 DarticObject → 存引用栈 |
| Bridge 实例 | 取出内部 DarticObject → 存引用栈 |
| VM 原生对象 | 直接存引用栈 |

### DarticProxy（通用代理）

DarticProxy 为没有预生成 Bridge 的解释器对象提供在 VM 侧的表示。它持有目标 DarticObject 的引用，通过运行时方法表转发属性访问和方法调用。

| 属性 | 类型 | 说明 |
|------|------|------|
| target | DarticObject | 被代理的解释器对象 |
| _runtime | DarticRuntime | 用于转发方法/属性调用 |

**Object 方法委托**：DarticProxy 重写三个 Object 基础方法，保证 VM 侧获得有意义的行为：

| 方法 | 实现 | 说明 |
|------|------|------|
| `operator ==` | `identical(target, other.target)` | 基于目标对象身份比较 |
| `hashCode` | `identityHashCode(target)` | 与 `==` 一致 |
| `toString()` | `_runtime.invokeMethod(target, 'toString', [])` | 委托给解释器的 toString() 方法 |

`toString()` 必须委托而非返回默认值——`print()`、Flutter 错误信息、日志输出、`debugFillProperties` 等大量 VM 侧代码会隐式调用 `toString()`，若返回 `'Instance of DarticProxy'` 则完全丧失调试信息。

**限制**：DarticProxy 无法通过 VM 侧的 `is` 类型检查。需要通过 `is SomeVMType` 检查的解释器类必须使用 Bridge。操作符重载（`+`、`[]` 等）无法通过 DarticProxy 转发给解释器——VM 侧 `proxy + other` 会因 DarticProxy 未定义 `operator +` 而报错。此限制在实际中影响较小：操作符调用主要发生在解释器内部（通过 `ADD_GENERIC` 等指令分发），VM 侧直接对 DarticProxy 做算术的场景极少。

### DarticCallbackProxy（回调代理）

DarticCallbackProxy 将解释器闭包包装为 VM 可调用的 Dart Function。它为 0-3 个参数预生成 `proxyN()` 方法，每个返回对应参数数量的 Dart 闭包（如 `proxy1()` 返回 `Object? Function(Object?)`），闭包内部通过 `_runtime.invokeClosure` 回调解释器。

| 属性 | 类型 | 说明 |
|------|------|------|
| _runtime | DarticRuntime | 用于回调解释器 |
| _closure | DarticClosure | 解释器闭包对象 |

**参数数量覆盖**：proxy0 ~ proxy3 覆盖标准库绝大多数回调场景。4+ 参数回调极为罕见，需要时通过 `Function.apply` 处理。

**参数与返回值转换**：DarticCallbackProxy 在调用链两端执行跨边界转换。VM 调用 `proxyN()` 生成的闭包时，闭包内部先对每个 VM 参数调用 `DarticProxyManager.unwrapForInterpreter()` 解包（DarticProxy → DarticObject，VM 原生对象直接传递），再调用 `_runtime.invokeClosure`。回调返回后，对返回值调用 `DarticProxyManager.wrapForVM()` 包装（DarticObject → DarticProxy，Bridge/基本类型直接传递），再返回给 VM 调用者。

**泛型签名丢失**：DarticCallbackProxy 统一使用 `Object? Function(Object?, ...)` 签名，丢失原始回调的参数和返回类型信息。Phase 1 中宿主 API 的回调参数使用宽松类型（`dynamic`）规避。

### Bridge 类与 $BridgeMixin

Bridge 类是预生成的宿主类子类，用于解释器类 `extends` 或 `implements` 宿主类型的场景。Dart 无法在运行时动态创建类，因此需要编译期预生成。所有 Bridge 类混入 `$BridgeMixin`，通过它委托方法调用、属性读写给解释器运行时。

**$BridgeMixin 提供的委托方法**：

| 方法 | 说明 |
|------|------|
| $_invoke(method, args) | 委托方法调用给解释器 |
| $_get(name) | 委托属性读取 |
| $_set(name, value) | 委托属性写入 |

**Bridge 命名规范**：`$<宿主类名>$bridge`，如 `$StatelessWidget$bridge`。Bridge 实例持有 `DarticRuntime` 和 `DarticObject`（存储字段值），每个重写方法内部调用 `_runtime.invokeMethod(_target, methodName, args)` 委托给解释器。

**Super 转发器**：Bridge 类为父类的每个非抽象可重写方法（包括操作符）预生成 super 转发器方法 `$super$<methodName>()`，内部直接调用 `super.<methodName>(args)` 并返回结果。super 转发器注册到 HostBindings（符号名格式：`"库URI::类名::$super$方法名#参数数量"`）。编译器在编译 `SuperMethodInvocation` / `SuperPropertyGet` / `SuperPropertySet` 时，若 `interfaceTarget` 指向宿主类方法，生成 `CALL_HOST` 指向对应的 super 转发器绑定（而非 `CALL_SUPER`）。

**操作符委托**：Bridge 类为父类可重写的操作符和解释器重写的操作符均生成委托。对于解释器重写的操作符（如 `operator ==`），Bridge 生成对应的 `operator ==` 重写方法，内部调用 `$_invoke('==', [other])` 委托给解释器。对于需要 super 调用的操作符，生成 super 转发器（如 `$super$==`）。操作符命名与 HostClassWrapper 操作符路由使用相同的 Dart 规范名。

### BridgeFactory（Bridge 工厂）

BridgeFactory 是 Bridge 实例的创建入口，由 BridgeGenerator 为每个可继承宿主类的每个可用构造函数生成一个变体。运行时通过 `classId` 查找 BridgeFactory，协调 DarticObject 创建与 VM 超类构造函数调用。

| 属性 | 类型 | 说明 |
|------|------|------|
| 签名 | (DarticRuntime, DarticObject, List\<Object?\>) -> Object | 接收运行时引用、解释器对象和已求值的 super 参数 |
| 注册方式 | _bridgeFactories[classId] | 按 classId 索引，初始化时由预生成库批量注册 |
| 变体规则 | 每个可用 VM 超类构造函数对应一个变体 | 参数签名匹配 super 构造函数 |

**与 Bridge 的关系**：BridgeFactory 闭包内部创建 Bridge 实例，Bridge 构造函数在初始化列表中调用 `super(superArgs)`。创建完成后，BridgeFactory 返回 Bridge 实例（而非内部 DarticObject），使 VM 侧 `is` 类型检查成立。

### BridgeGenerator（编译期代码生成器）

BridgeGenerator 基于 build_runner + package:analyzer，扫描目标库 API 并为每个宿主类生成三部分代码：

1. **HostClassWrapper**：为类的所有公开属性、方法和操作符生成名称分发路由（操作符使用 Dart 规范名注册）
2. **Bridge 类**（仅限可继承类）：跳过 `final` 和 `sealed` 类，为可继承类生成 `extends` 子类 + `$BridgeMixin`，包含：
   - 每个可重写方法的委托重写（内部调用 `$_invoke`）
   - 每个可重写操作符的委托重写（内部调用 `$_invoke('操作符名', args)`）
   - 每个非抽象可重写方法/操作符的 super 转发器（`$super$methodName()` 调用 `super.methodName()`）
   - 每个可用构造函数对应的 BridgeFactory 变体
3. **注册代码**：生成将所有绑定 ID 写入 HostBindings 注册表的初始化函数（包括 super 转发器的绑定注册）

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

## 工作流程

### 解释器 -> VM 调用流程（外调）

1. 编译器将宿主方法调用编译为 `CALL_HOST A, Bx` 指令，Bx 为 .darticb 绑定名称表中的本地索引
2. 运行时加载 .darticb 时，通过 `HostBindings.lookupByName` 将符号名解析为运行时 ID（详见 Ch4）
3. 分发循环执行 `CALL_HOST` 时，从引用栈取参数，调用 `HostBindings.invoke(runtimeId, args)`
4. 返回值（VM 原生对象）直接存入引用栈，后续通过 HostClassWrapper 路由访问

### VM -> 解释器回调流程（内调）

1. HostClassWrapper 在转发方法参数时检测到 DarticClosure
2. 创建 DarticCallbackProxy，根据宿主方法签名的参数数量选择 `proxyN()` 生成 Dart 闭包
3. 将生成的 Dart 闭包传给宿主 API（如 `list.map(proxy.proxy1())`）
4. 宿主 API 调用闭包时，DarticCallbackProxy 内部通过 `_runtime.invokeClosure` 回调解释器：
   a. 在 CallStack 上压入 HOST_BOUNDARY 哨兵帧（详见 Ch2）
   b. 在值栈/引用栈栈顶为回调分配新帧空间
   c. 将参数写入新帧的寄存器
   d. 调用 `drive()` 执行回调（嵌套 drive，共享 fuel 预算，详见 Ch7）
   e. 回调的 RETURN 遇到 HOST_BOUNDARY → 退出 `drive()`，控制权交还 VM
   f. 从值栈/引用栈读取返回值，恢复栈指针到回调入口前的状态

### Bridge 实例创建流程

当解释器执行 `NEW_INSTANCE` 创建一个继承宿主类的对象时：

1. 创建 DarticObject，分配 `classId`、`DarticType`、引用字段和值字段存储空间
2. 以 `classId` 查找 Bridge 工厂（`_bridgeFactories[classId]`）
3. 若工厂不存在（纯内部类），直接返回 DarticObject
4. 若工厂存在（解释器类 extends/implements 宿主类），进入 Bridge 构造流程

**Bridge 构造流程**（步骤 4 展开）：

Bridge 的创建需要与 VM 超类构造函数协调——Dart 要求 `super()` 在构造函数初始化列表中调用，无法延迟到对象创建之后。编译器和运行时通过以下流程配合：

1. 编译器将 `SuperInitializer` 的参数求值指令**提前**到 `NEW_INSTANCE` 之前发射
2. `NEW_INSTANCE` 指令执行时，运行时从引用栈取出已求值的 super 参数
3. BridgeFactory（详见上方核心概念）接收 super 参数，创建 Bridge 实例——Bridge 构造函数在初始化列表中调用 `super(superArgs)`
4. 返回 Bridge 实例。**引用栈中存储的是 Bridge 实例**（而非内部的 DarticObject），使 VM 侧 `is` 类型检查成立
5. 后续的构造函数体字节码（字段初始化器、构造函数体语句）正常执行，通过 `SET_FIELD_REF` / `SET_FIELD_VAL` 设置 DarticObject 的字段

**不变式**：Bridge 创建完成后，DarticObject 的 `classId` 和 Bridge 实例的 Dart 类型保持一致——同一个解释器类始终使用同一个 Bridge 类。

## 异常跨边界传播契约

### 解释器 -> VM（解释器代码抛出异常）

| 场景 | VM 侧行为 |
|------|-----------|
| async 函数未捕获异常 | `completer.completeError(error, trace)` → VM 的 `await` 收到原始异常对象 |
| Bridge 方法中抛出 | 异常自然传播到 VM 调用者（Bridge 方法是 VM 级别的方法） |
| DarticCallbackProxy 执行中抛出 | 异常自然传播到触发回调的 VM 代码（如 `list.forEach` 内部） |

**异常类型保留**：解释器抛出的 `throw MyException()` 创建的是 DarticObject。跨边界时通过 `DarticProxyManager.wrapForVM()` 包装为 DarticProxy。VM 侧 `catch (e)` 捕获到的是 DarticProxy 实例，**不是** `MyException` 类型——因此 `on MyException catch (e)` 无法匹配。

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

同一个 DarticObject 跨边界传递多次，VM 侧必须收到同一个代理实例。否则 `identical(proxy1, proxy2)` 返回 false，破坏 switch 模式匹配和 Zone 错误处理。

### 身份规则

| 对象类型 | 跨边界行为 | 身份保证机制 |
|---------|-----------|------------|
| DarticObject | 通过 DarticProxyManager 包装为 DarticProxy | Expando 缓存，ephemeron 语义 |
| Bridge 实例 | 直接传递（已是 VM 类型） | 对象本身即 VM 实例 |
| DarticClosure | 通过 DarticCallbackProxy 包装为 Dart Function | 每次包装创建新闭包（无身份缓存） |
| 基本类型（int/double/String/bool） | 直接传值，不经过 DarticProxyManager | 不可变值类型，Dart 小整数缓存 + String 驻留 |
| null | 直接传值 | Dart 语言保证 `identical(null, null)` |
| VM 原生集合（List/Map/Set） | 直接存引用栈，不包装 | `CREATE_LIST` 等指令创建的是 VM 原生对象（详见 Ch2） |
| Record | 直接传值（VM 原生对象） | `CREATE_RECORD` 创建 VM 原生 Record（详见 Ch1） |
| 常量（Constant 物化后） | 直接传值（VM 原生对象） | 常量池物化为 VM 对象后直接引用（详见 Ch2 常量池物化策略） |
| VM 原生对象（其他） | 直接存引用栈，不包装 | 对象本身即 VM 实例 |

Expando 内部使用 ephemeron 语义——键不可达时值也被 GC，不会内存泄漏。

**DarticClosure 身份说明**：DarticCallbackProxy 每次 `proxyN()` 调用创建新的 Dart 闭包，不保证身份一致性（同一 DarticClosure 两次包装产生不同的 Dart Function）。实际影响有限——VM 侧对回调做 `identical` 比较的场景极少（如 `removeListener` 需要传入同一 Function 实例），此类场景需要用户侧缓存 proxy 结果。

## 关键约束与边界条件

| 约束 | 值 | 来源 |
|------|-----|------|
| CALL_HOST 绑定索引宽度 | 16 位（Bx），最多 65536 个绑定 | Ch1 ABx 编码格式 |
| DarticCallbackProxy 参数上限 | 0-3 个（proxy0 ~ proxy3） | 标准库回调分析；4+ 参数走 Function.apply |
| Bridge 覆盖限制 | 仅 extends / implements，不含 mixin | Phase 1 范围限制 |
| DarticProxy 类型检查 | 无法通过 VM 侧 `is` 检查 | Dart 类型系统限制，需 Bridge 才能通过 |
| 异常类型跨边界 | 解释器异常到 VM 侧变为 DarticProxy，`on Type catch` 失效 | DarticObject 非 VM 类型 |
| Expando 缓存容量 | 无固定上限，随 GC 自动回收 | ephemeron 语义 |
| 操作符命名 | 使用 Dart 规范名（`+`、`[]`、`==` 等），与 Kernel `Name.text` 一致 | HostClassWrapper / HostBindings / BridgeGenerator 统一约定 |
| Super 转发器命名 | `$super$<方法名>` + HostBindings 符号格式 `"库URI::类名::$super$方法名#N"` | BridgeGenerator 生成，编译器引用 |
| Bridge 构造函数变体 | 每个可用的 VM 超类构造函数对应一个 BridgeFactory | BridgeGenerator 按超类构造函数签名生成 |

## 已知局限与演进路径

> **Phase 2**：回调类型特化。BridgeGenerator 分析宿主方法签名，为常见回调类型预生成特化 proxy 变体（如 `int Function(String)` -> 保留原始类型信息的闭包），消除泛型签名丢失问题。触发条件：回调边界因类型不匹配导致运行时错误。

> **Phase 2**：Mixin 组合 Bridge 支持。生成 `class $State$bridge<T> extends State<T> with SingleTickerProviderStateMixin` 形式的 Bridge，处理 mixin 方法的委托转发和 `super.xxx` 分发路径，保证多 mixin 线性化顺序与解释器虚方法表一致。触发条件：Flutter 应用需要 `SingleTickerProviderStateMixin`、`AutomaticKeepAliveClientMixin` 等常用 mixin。

> **Phase 2**：noSuchMethod 接口代理。对于 implements 宿主接口但不 extends 具体类的场景，通过 noSuchMethod 转发实现轻量级代理，减少预生成 Bridge 的数量。触发条件：Bridge 数量膨胀导致包体积过大。

> **Phase 2**：跨边界异常类型保留。研究将解释器异常包装为 VM 可识别类型的方案，使 `on MyException catch (e)` 在 VM 侧可匹配。触发条件：跨边界异常处理成为实际开发痛点。

> **Phase 2**：DarticProxy 操作符转发。为 DarticProxy 预生成常用操作符重载（`+`、`-`、`[]`、`[]=` 等），内部委托给 `_runtime.invokeMethod(target, 'operator+', args)`。触发条件：VM 侧需要对 DarticProxy 执行算术或索引操作。

> **Phase 2**：Bridge noSuchMethod 兜底。Bridge 预生成的方法覆盖有限，VM 侧调用未预生成的方法时当前会报 `NoSuchMethodError`。可在 `$BridgeMixin` 中添加 `noSuchMethod` 重写，将未知方法转发给解释器的方法表查找。触发条件：Bridge 覆盖不全导致运行时错误。

> **Phase 2**：DarticCallbackProxy 身份缓存。当前每次 `proxyN()` 创建新 Dart 闭包，`removeListener` 等需要同一 Function 实例的 API 无法正常工作。可在 DarticProxyManager 中为 DarticClosure → Dart Function 维护 Expando 缓存，保证同一 DarticClosure 的同参数数量包装产生同一 Dart Function 实例。触发条件：Flutter `addListener`/`removeListener` 场景因闭包身份不一致导致监听器泄漏。

## 附录：参考实现

<details>
<summary>DarticProxyManager.wrapForVM 核心逻辑</summary>

```dart
Object wrapForVM(Object obj) {
  if (obj is DarticObject) {
    var proxy = _interpToProxy[obj];
    if (proxy != null) return proxy;  // 缓存命中，保证 identical
    proxy = DarticProxy(obj, _runtime);
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
Object createInstance(int classId, DarticType type, List<Object?> superArgs) {
  final interp = DarticObject(
    classId: classId, runtimeType: type,
    refFieldCount: classInfo.refFieldCount,
    valueFieldCount: classInfo.valueFieldCount,
  );
  final bridgeFactory = _bridgeFactories[classId];
  if (bridgeFactory != null) return bridgeFactory(this, interp, superArgs);
  return interp;
}
```

</details>
