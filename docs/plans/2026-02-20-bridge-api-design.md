# Bridge API 设计 — dartic 嵌入式脚本引擎公开 API

**日期：** 2026-02-20
**状态：** 待审阅

## 背景与目标

dartic 定位为**嵌入式 Dart 脚本引擎**（类似 Lua 之于 C），运行真正的 Dart 代码（通过 Kernel AST 编译为自定义字节码）。核心使用场景：
1. **Flutter 热更新**：服务器编译 .darb 字节码 → 设备端解释执行 → 无需应用商店审核
2. **通用嵌入式脚本**：宿主应用加载第三方 Dart 脚本，控制执行权限

本设计定义 dartic 面向宿主开发者的公开 API，包括引擎生命周期、绑定注册、代码生成注解和数据交换协议。

## 调研基础

对比了 5 个嵌入式脚本引擎的 API 设计：

| 引擎 | 语言 | 通信模型 | 类型安全 | 脚本可继承宿主类 | 代码生成 |
|------|------|---------|---------|-----------------|---------|
| Lua | C | 虚拟栈 push/pop | 运行时 | 否 | 无 |
| QuickJS | C | JSValue 直传 | 运行时 | 否（原型链） | 无 |
| Wren | C | Slot 数组 | 运行时 | 否（foreign 不透明） | 无 |
| hetu_script | Dart | 直传 Dart 对象 | 字符串匹配 | 否（外部不透明） | 可选（autobinding） |
| dart_eval | Dart | $Value 包装 | 中等（包装类型） | **是**（Bridge 模式） | 是（@Bind + codegen） |

**dartic 的独特优势**：
- 运行**真正的 Dart**（非自定义语言），开发者零学习成本
- Bridge 模式允许脚本继承宿主类（与 dart_eval 类似）
- **零包装开销**：原生 Dart 值直接跨边界（无需 `$String('hi')`），因为双栈架构内部处理类型映射

## 设计决策

| 决策项 | 选择 | 备选方案与拒绝理由 | 理由 |
|--------|------|-------------------|------|
| API 风格 | Config + Engine（Flutter 风格） | Flat Engine（过于简单）、Runtime + Script 分离（概念过多） | Dart/Flutter 开发者熟悉 config 模式，渐进式复杂度 |
| 绑定注册 | 声明式注解 @DarticExport + build_runner | 手写 HostClassWrapper（冗长）、运行时反射（AOT 不可用） | 类型安全、可扩展、IDE 友好 |
| 执行模型 | 预编译 .darb 字节码 | JIT / 源码解释 | 设备端零编译开销，支持热更新分发 |
| 值传递 | 原生 Dart 值直接跨边界 | $Value 包装（dart_eval 风格） | 零包装开销，API 更自然 |
| 错误模型 | 标准 Dart 异常 + 可选 onError 回调 | Result 类型 | 与 Dart 生态一致 |
| 包结构 | 分包（annotation / generator / bridges） | 单包 | 最小化依赖，用户只需引入所需部分 |

## 公开 API

### 1. DarticEngine — 引擎入口

```dart
class DarticEngine {
  /// 创建引擎，可选传入插件和配置。
  DarticEngine({
    List<DarticPlugin> plugins = const [],
    DarticConfig config = const DarticConfig(),
  });

  /// 加载编译后的 .darb 字节码。
  void loadBytecode(Uint8List bytes);

  /// 调用脚本中的顶层函数。返回函数返回值，void 返回 null。
  Object? call(String function, [List<Object?> args = const []]);

  /// 快速注册一个宿主函数（无需代码生成，用于原型开发）。
  void addFunction(String name, Function fn);

  /// 注册一个插件（通常由 @DarticExport 生成）。
  void addPlugin(DarticPlugin plugin);

  /// 释放所有资源。调用后引擎不可再使用。
  void dispose();
}
```

**渐进式复杂度**：
```dart
// 最简：3 行运行脚本
final engine = DarticEngine();
engine.loadBytecode(bytes);
engine.call('main');

// 带 print 支持
final engine = DarticEngine(
  config: DarticConfig(onPrint: print),
);

// 完整配置
final engine = DarticEngine(
  plugins: [DarticCorePlugin(), MyAppPlugin()],
  config: DarticConfig(
    maxFuel: 5000000,
    maxCallDepth: 512,
    onPrint: (msg) => logger.info(msg),
    onError: (error, stack) => crashlytics.report(error, stack),
  ),
);
```

### 2. DarticConfig — 引擎配置

```dart
class DarticConfig {
  const DarticConfig({
    this.maxFuel = 50000,
    this.maxCallDepth = 256,
    this.onPrint,
    this.onError,
  });

  /// 最大指令执行数，超出抛 FuelExhaustedError。0 = 无限制（生产环境慎用）。
  final int maxFuel;

  /// 最大调用栈深度，超出抛 CallDepthExceededError。
  final int maxCallDepth;

  /// 脚本 print() 的处理器。为 null 则静默丢弃输出。
  final void Function(String message)? onPrint;

  /// 未捕获的脚本错误处理器。为 null 则作为 DarticError 向宿主抛出。
  final void Function(Object error, StackTrace stackTrace)? onError;
}
```

### 3. DarticPlugin — 插件接口

```dart
/// 绑定插件接口。由 @DarticExport 代码生成器生成。
abstract class DarticPlugin {
  /// 插件名称（调试用）。
  String get name;

  /// 注册所有绑定到引擎。引擎初始化时调用一次。
  void register(DarticEngine engine);
}
```

**生成的插件示例**（@DarticExport codegen 输出）：
```dart
// GENERATED CODE — DO NOT MODIFY BY HAND
class MyAppPlugin extends DarticPlugin {
  @override
  String get name => 'my_app';

  @override
  void register(DarticEngine engine) {
    engine.registerClassWrapper('MyService', $MyServiceWrapper());
    engine.registerBinding('my_app::greet#1', _$greet);
    engine.registerBridgeFactory(classId, _$MyWidget$bridge$factory);
  }
}
```

### 4. 注解 API

```dart
/// 标记类或顶层函数导出给 dartic 脚本使用。
class DarticExport {
  const DarticExport({this.name, this.bridge = false});

  /// 自定义绑定名。默认使用 Dart 声明名。
  final String? name;

  /// 为 true 时生成 Bridge 类，允许脚本 extends 此类。
  /// 仅适用于非 final、非 sealed 类。默认 false（仅生成 HostClassWrapper）。
  final bool bridge;
}

/// 标记成员排除在导出之外。
class DarticHide {
  const DarticHide();
}
```

**使用**：
```dart
@DarticExport()
class MyService {
  String greet(String name) => 'Hello, $name!';

  @DarticHide()
  String _secret() => 'hidden';
}

@DarticExport(bridge: true)  // 脚本可 extends
class BaseWidget {
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@DarticExport()
int add(int a, int b) => a + b;
```

### 5. 数据交换规则

| 宿主侧 | 脚本侧 | 方向 | 包装方式 |
|---------|--------|------|----------|
| `int`, `double`, `bool`, `String` | 同类型 | 双向 | 无（直接传递） |
| `null` | `null` | 双向 | 无 |
| `List`, `Map`, `Set` | 同类型 | 双向 | 无（VM 原生对象） |
| @DarticExport 标注类 | 脚本使用 | 宿主→脚本 | HostClassWrapper 路由 |
| 脚本定义类 | 宿主接收 | 脚本→宿主 | DarticProxy（自动） |
| 宿主 Function | 脚本调用 | 宿主→脚本 | HostBindings 注册 |
| 脚本闭包 | 宿主调用 | 脚本→宿主 | DarticCallbackProxy（自动） |
| @DarticExport(bridge: true) | 脚本 extends | 双向 | Bridge 类（生成） |

### 6. 错误模型

```dart
/// dartic 错误基类。
class DarticError implements Exception {
  final String message;
  final StackTrace? darticStackTrace;
}

class FuelExhaustedError extends DarticError {}      // 指令预算耗尽
class CallDepthExceededError extends DarticError {}   // 调用栈溢出
class BytecodeError extends DarticError {}            // 字节码加载/校验失败
class BindingResolutionError extends DarticError {}   // 宿主绑定未找到
```

**传播规则**（遵循 Ch4 设计）：
- **脚本 throw** → 宿主 catch 到 DarticError（或未捕获 → onError 回调）
- **宿主函数 throw** → 脚本 catch 可捕获（VM 异常类型保留）
- **fuel 耗尽** → FuelExhaustedError 传播到宿主

### 7. 包结构

```
package:dartic                  — 核心引擎 + 运行时（现有包）
package:dartic_annotation       — @DarticExport, @DarticHide（纯注解，无依赖）
package:dartic_generator        — build_runner 代码生成器（dev_dependency）
package:dartic_bridges_core     — dart:core 生成绑定（List, Map, String, int 等）
package:dartic_bridges_flutter  — Flutter widget 生成绑定
```

用户 pubspec.yaml：
```yaml
dependencies:
  dartic: ^1.0.0
  dartic_annotation: ^1.0.0
  dartic_bridges_core: ^1.0.0

dev_dependencies:
  dartic_generator: ^1.0.0
  build_runner: ^2.4.0
```

## 与 Ch4 内部架构的映射

| 公开 API | Ch4 内部组件 | 说明 |
|---------|-------------|------|
| `DarticEngine` | `DarticInterpreter` + `HostBindings` + `DarticProxyManager` | 引擎封装内部执行引擎和绑定基础设施 |
| `DarticPlugin.register()` | `HostBindings.register()` + `HostClassWrapper` 注册 | 插件填充内部注册表 |
| `engine.call()` | `DarticInterpreter.execute()` → `DarticFrame` 创建 | 入口函数调用 |
| `engine.addFunction()` | `HostBindings._functions` 添加 typed wrapper | 手动注册快捷方式 |
| `@DarticExport` codegen | `BridgeGenerator` 的 3 部分输出 | HostClassWrapper + Bridge + 注册代码 |
| `DarticConfig.onPrint` | `HostBindings` 注册的 `print` 绑定 | print 桥接 |
| `DarticProxy`（自动） | `DarticProxyManager.wrapForVM()` | 脚本对象跨边界的通用代理 |
| `DarticCallbackProxy`（自动） | `DarticCallbackProxy.proxyN()` | 脚本闭包跨边界的回调代理 |

## 完整示例 — Flutter 热更新

### 宿主应用

```dart
// lib/services/navigation_service.dart
@DarticExport()
class NavigationService {
  final GlobalKey<NavigatorState> navigatorKey;
  NavigationService(this.navigatorKey);

  void pushRoute(String route) =>
      navigatorKey.currentState?.pushNamed(route);
}

// lib/screens/screen_builder.dart
@DarticExport(bridge: true)
class ScreenBuilder {
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// lib/main.dart
void main() async {
  final engine = DarticEngine(
    plugins: [DarticCorePlugin(), DarticFlutterPlugin(), MyAppPlugin()],
    config: DarticConfig(
      maxFuel: 10000000,
      onPrint: (msg) => debugPrint('[dartic] $msg'),
    ),
  );

  final bytes = await http.get('https://cdn.example.com/update.darb');
  engine.loadBytecode(bytes);

  final builder = engine.call('createHomeScreen') as ScreenBuilder;
  runApp(MaterialApp(home: builder.build(navigatorKey.currentContext!)));
}
```

### 脚本（服务器编译为 .darb）

```dart
class HomeScreen extends ScreenBuilder {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Hot Update v2.1')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => NavigationService.instance.pushRoute('/settings'),
          child: Text('Open Settings'),
        ),
      ),
    );
  }
}

ScreenBuilder createHomeScreen() => HomeScreen();
```

## 实现路径

本设计跨 Phase 5/6/7 三个阶段逐步实现：

| Phase | Batch | 内容 | 实现组件 |
|-------|-------|------|---------|
| **5** | 5.1 | Bridge 内部基础设施 + CALL_HOST 管线 | HostBindings、CALL_HOST 指令、DarticProxy |
| **5** | 5.2 | dart:core 手写桥接 | int/String/List/Map 等 HostClassWrapper（手写，发现模式） |
| **5** | 5.3 | 集合字面量、字符串插值与回调 | DarticCallbackProxy、DarticProxyManager |
| **5** | 5.4 | co19 harness v3 验证 | 端到端测试、回归检测 |
| **6** | 6.1 | async/await（生产环境必需） | 帧快照续体、Completer 桥接 |
| **6** | 6.4 | 沙箱（DarticConfig.maxFuel 依赖） | 字节码验证、fuel 计数、调用深度限制 |
| **7** | 7.1 | DarticEngine 公开 API 封装 | DarticEngine、DarticConfig、DarticPlugin 接口 |
| **7** | 7.2 | @DarticExport 代码生成 | dartic_annotation + dartic_generator（BridgeGenerator） |
| **7** | 7.3 | Flutter Bridge + 热更新 Demo | dartic_bridges_flutter 包、端到端 demo |

**设计原则**：Phase 5 手写 Bridge 发现真实模式 → Phase 6 补全 async/sandbox 运行时能力 → Phase 7 基于稳定内部实现封装公开 API + codegen。
