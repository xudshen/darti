# Chapter 7: 安全与沙箱

## 设计决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 安全模型 | 最小安全 | 字节码验证 + 指令计数 + 调用深度限制，不做能力模型 |
| 验证时机 | 加载时静态验证 | 一次验证，运行时零开销 |
| 资源限制 | fuel 计数 + 调用栈深度 | 防无限循环和无限递归，复用运行时已有机制 |
| 不实现 | 能力模型 / 权限沙箱 | 过度设计，当前目标是热更新和插件，不是不可信代码执行 |

## 安全目标

dartic 的安全目标是**保护宿主应用不因解释器代码的错误而崩溃**，而非隔离不可信代码。具体保障：

1. **不因格式错误的字节码崩溃**：加载时验证确保所有字节码结构合法
2. **不因无限循环卡死**：fuel 计数机制确保解释器定期让出控制权
3. **不因无限递归栈溢出**：调用深度限制防止栈溢出
4. **不因越界访问内存损坏**：常量池、寄存器索引在加载时验证

**不在目标内**：
- 阻止解释器代码调用任意宿主 API（由 Bridge 注册表控制暴露范围）
- 文件系统/网络等 OS 级隔离（需要 isolate 级沙箱，不在 dartic 范围内）
- 防御恶意字节码的信息泄漏或侧信道攻击

## 加载时字节码验证

### 验证器架构

```dart
class BytecodeVerifier {
  final List<String> errors = [];

  bool verify(DarticModule module) {
    _verifyHeader(module);
    _verifyConstantPool(module.constantPool);
    for (final func in module.functions) {
      _verifyFunction(func, module);
    }
    _verifyClassTable(module);
    _verifyEntryPoint(module);
    return errors.isEmpty;
  }
}
```

### 验证项

#### 1. 文件头验证

```dart
void _verifyHeader(DarticModule module) {
  if (module.magic != 0xDART1B00) {
    errors.add('Invalid magic number');
  }
  if (module.version > currentVersion) {
    errors.add('Unsupported version: ${module.version}');
  }
  if (module.checksum != _computeCRC32(module.payload)) {
    errors.add('Checksum mismatch');
  }
}
```

#### 2. 常量池边界验证

```dart
void _verifyConstantPool(ConstantPool pool) {
  // 每个引用常量池条目不引用越界索引
  for (int i = 0; i < pool.refs.length; i++) {
    final entry = pool.refs[i];
    if (entry is ConstantPoolReference && entry.index >= pool.refs.length) {
      errors.add('Constant pool ref[$i] references out-of-bounds index ${entry.index}');
    }
  }
}
```

#### 3. 函数字节码验证

每个函数的字节码逐指令扫描：

```dart
void _verifyFunction(FuncProto func, DarticModule module) {
  final codeLength = func.bytecode.length;

  for (int pc = 0; pc < codeLength; pc++) {
    final instr = func.bytecode[pc];
    final op = instr & 0xFF;

    // a) 操作码合法性
    if (!OpCode.isValid(op)) {
      errors.add('${func.name}@$pc: invalid opcode 0x${op.toRadixString(16)}');
      continue;
    }

    // b) 跳转目标验证
    if (OpCode.isJump(op)) {
      final target = _decodeJumpTarget(instr, pc);
      if (target < 0 || target >= codeLength) {
        errors.add('${func.name}@$pc: jump target $target out of bounds [0, $codeLength)');
      }
    }

    // c) 寄存器索引验证
    _verifyRegisterBounds(func, instr, op, pc);

    // d) 常量池索引验证
    if (OpCode.usesConstantPool(op)) {
      final cpIndex = _decodeConstantIndex(instr);
      if (cpIndex >= module.constantPool.length(op)) {
        errors.add('${func.name}@$pc: constant pool index $cpIndex out of bounds');
      }
    }

    // e) WIDE 前缀验证
    if (op == OpCode.WIDE) {
      if (pc + 1 >= codeLength) {
        errors.add('${func.name}@$pc: WIDE at end of bytecode, missing next instruction');
      } else {
        final nextInstr = func.bytecode[pc + 1];
        final nextOp = nextInstr & 0xFF;
        if (!OpCode.isWideCompatible(nextOp)) {
          errors.add('${func.name}@$pc: WIDE before non-compatible opcode 0x${nextOp.toRadixString(16)}');
        }
      }
      pc++;  // 跳过 WIDE 后的扩展字
      continue;
    }

    // f) 方法/函数引用验证
    if (OpCode.isCall(op)) {
      final funcId = _decodeFuncId(instr);
      if (funcId >= module.functions.length && !_isHostBinding(funcId)) {
        errors.add('${func.name}@$pc: function reference $funcId out of bounds');
      }
    }
  }

  // g) 异常处理器表验证
  _verifyExceptionTable(func);
}
```

#### 4. 寄存器边界验证

```dart
void _verifyRegisterBounds(FuncProto func, int instr, int op, int pc) {
  final format = OpCode.format(op);

  switch (format) {
    case InstrFormat.ABC:
      final a = (instr >> 8) & 0xFF;
      final b = (instr >> 16) & 0xFF;
      final c = (instr >> 24) & 0xFF;
      if (a >= func.regCount || b >= func.regCount || c >= func.regCount) {
        errors.add('${func.name}@$pc: register index exceeds regCount ${func.regCount}');
      }
    case InstrFormat.ABx:
      final a = (instr >> 8) & 0xFF;
      if (a >= func.regCount) {
        errors.add('${func.name}@$pc: register A=$a exceeds regCount ${func.regCount}');
      }
    // ... 其他格式
  }
}
```

#### 5. 异常处理器表验证

```dart
void _verifyExceptionTable(FuncProto func) {
  final codeLength = func.bytecode.length;

  for (final handler in func.exceptionTable) {
    if (handler.startPC >= codeLength || handler.endPC > codeLength) {
      errors.add('${func.name}: exception handler range [${handler.startPC}, ${handler.endPC}) out of bounds');
    }
    if (handler.startPC >= handler.endPC) {
      errors.add('${func.name}: exception handler has empty range');
    }
    if (handler.handlerPC >= codeLength) {
      errors.add('${func.name}: exception handler target ${handler.handlerPC} out of bounds');
    }
    if (handler.valueStackDepth < 0) {
      errors.add('${func.name}: exception handler has negative value stack depth');
    }
    if (handler.refStackDepth < 0) {
      errors.add('${func.name}: exception handler has negative ref stack depth');
    }
  }
}
```

#### 6. 类表验证

```dart
void _verifyClassTable(DarticModule module) {
  for (final cls in module.classes) {
    // 超类引用合法
    if (cls.superClassId >= 0 && cls.superClassId >= module.classes.length) {
      errors.add('Class ${cls.name}: superClassId ${cls.superClassId} out of bounds');
    }
    // 方法引用合法
    for (final entry in cls.methods.entries) {
      if (entry.value >= module.functions.length) {
        errors.add('Class ${cls.name}: method references invalid function ${entry.value}');
      }
    }
  }
}
```

### 验证时机与流程

```dart
DarticModule loadModule(Uint8List bytes) {
  // 1. 反序列化
  final module = DarticModuleDeserializer.deserialize(bytes);

  // 2. 验证
  final verifier = BytecodeVerifier();
  if (!verifier.verify(module)) {
    throw DarticLoadError(
      'Bytecode verification failed:\n${verifier.errors.join('\n')}'
    );
  }

  // 3. Bridge 依赖检查
  _checkBridgeDependencies(module);

  // 4. 返回已验证模块（运行时不再检查）
  return module;
}
```

验证通过后，运行时的分发循环**不执行任何边界检查**——所有安全保证由加载时验证提供。这确保了运行时零安全开销。

## 运行时资源限制

### Fuel 计数（防无限循环）

复用 Chapter 2 分发循环中已有的 fuel 机制：

```dart
static const int _fuelBudget = 50000;  // 根据 profiling 调优

void _driveInterpreter() {
  int fuel = _fuelBudget;

  while (fuel > 0 && _runQueue.isNotEmpty) {
    final frame = _runQueue.first;
    // ...
    innerLoop:
    while (fuel-- > 0) {
      // 执行指令
    }
  }

  if (_runQueue.isNotEmpty) {
    Timer.run(_driveInterpreter);  // 让出控制权，下一轮继续
  }
}
```

fuel 耗尽时通过 `Timer.run` 让出控制权，不会导致宿主事件循环饿死。这不是显式的安全机制，而是协作调度的自然结果——但它有效防止了无限循环卡死宿主应用。

### 回调重入的 Fuel 语义

当 `CALL_HOST` 触发 VM 回调（通过 CallbackProxy 重新进入解释器）时，回调执行的 fuel 规则：

- 回调执行**共享当前回合的 fuel budget**，不分配独立 fuel
- 回调中的指令消耗与普通指令相同的 fuel
- 如果回调中的代码耗尽 fuel（例如回调包含无限循环），分发循环正常让出控制权（`Timer.run`）
- 回调返回后，外层分发循环继续使用剩余 fuel

```dart
// CallbackProxy 重入示例：
// list.forEach((x) { /* 解释器代码 */ })
//
// 执行流：
//   解释器 → CALL_HOST(forEach) → VM forEach → CallbackProxy → 解释器（共享 fuel）
//                                                                    ↓
//                                                          fuel 耗尽 → Timer.run
```

这确保了通过回调重入的无限循环（如 `list.forEach((x) { while(true) {} })`）仍然受 fuel 机制保护，不会卡死宿主事件循环。

### 调用深度限制（防栈溢出）

```dart
class DarticRuntime {
  static const int maxCallDepth = 512;
  int _currentCallDepth = 0;

  void _pushFrame(InterpreterFrame frame) {
    _currentCallDepth++;
    if (_currentCallDepth > maxCallDepth) {
      _currentCallDepth--;
      throw DarticError('Stack overflow: call depth exceeded $maxCallDepth');
    }
    _runQueue.addFirst(frame);
  }

  void _popFrame() {
    _currentCallDepth--;
    _runQueue.removeFirst();
  }
}
```

深度限制值 512 足以覆盖正常递归场景，同时防止恶意或错误的无限递归耗尽宿主内存。

### 执行超时（可选）

fuel 机制保证单回合不超时，但无法限制累计执行时间。宿主应用可配置以下可选限制：

```dart
class DarticRuntime {
  int? maxTotalFuel;         // 跨回合累计指令数上限（null = 不限）
  Duration? executionTimeout; // 执行超时（null = 不限）

  int _totalFuelConsumed = 0;
  Stopwatch? _executionTimer;

  void _driveInterpreter() {
    if (executionTimeout != null) {
      _executionTimer ??= Stopwatch()..start();
      if (_executionTimer!.elapsed >= executionTimeout!) {
        _runQueue.clear();
        throw DarticError('Execution timeout exceeded');
      }
    }

    int fuel = _fuelBudget;
    // ... 正常分发循环 ...
    _totalFuelConsumed += _fuelBudget - fuel;

    if (maxTotalFuel != null && _totalFuelConsumed >= maxTotalFuel!) {
      _runQueue.clear();
      throw DarticError('Total fuel budget exceeded');
    }
  }
}
```

这些限制是可选的——默认不启用，由宿主应用根据需要配置。

### 内存保护

不实现显式的内存上限。依赖宿主 Dart VM 的 GC 和 OS 级内存限制：

- 栈空间在初始化时预分配固定大小（ValueStack、RefStack、CallStack），不会无限增长
- 堆对象（InterpreterObject）由 VM GC 管理，与宿主应用共享内存压力
- 如果需要内存限制，宿主应用可通过 Dart 的 `--old-gen-heap-size` 等 VM 参数控制

## Bridge 注册表作为 API 边界

虽然 dartic 不实现能力模型，但 Bridge 注册表天然形成了 API 边界——解释器代码只能访问已注册的宿主 API：

```dart
final runtime = DarticRuntime();

// 仅注册核心库，不注册 dart:io
registerCoreBridges(runtime.hostBindings);
// 不调用 registerIoBridges → 解释器无法访问文件/网络

runtime.loadAndRun('plugin.darticb');
```

这不是安全沙箱（解释器可以通过已注册的 API 间接访问 IO），但提供了基本的 API 表面控制。宿主应用的开发者决定暴露哪些能力给解释器代码。

## 错误隔离

解释器运行时的错误不应导致宿主应用崩溃：

```dart
Future<void> runPlugin(DarticRuntime runtime, String path) async {
  try {
    final module = runtime.loadModule(File(path).readAsBytesSync());
    await runtime.execute(module);
  } on DarticLoadError catch (e) {
    // 字节码验证失败 → 拒绝加载
    log.warning('Plugin load failed: $e');
  } on DarticError catch (e) {
    // 运行时错误（栈溢出、未捕获异常等） → 隔离处理
    log.warning('Plugin execution error: $e');
  }
  // 宿主应用继续运行
}
```

### 异常分类

```dart
/// 加载时错误：字节码格式/验证失败
class DarticLoadError implements Exception {
  final String message;
  DarticLoadError(this.message);
}

/// 运行时错误：解释器执行中的可恢复错误
class DarticError implements Exception {
  final String message;
  DarticError(this.message);
}

/// 内部错误：解释器实现 bug（不应发生）
class DarticInternalError implements Exception {
  final String message;
  DarticInternalError(this.message);
}
```

`DarticError` 和 `DarticLoadError` 是预期的、可恢复的。`DarticInternalError` 表示解释器自身的 bug，应当记录并上报。

## 未来扩展点

当前的最小安全模型为未来扩展预留了空间，但不预先实现：

| 扩展方向 | 触发条件 | 复杂度 |
|----------|----------|--------|
| 内存上限 | 需要多租户资源隔离 | 低：追踪 InterpreterObject 分配计数 |
| API 白名单 | 需要细粒度权限控制 | 中：在 HostBindings 层添加权限检查 |
| 执行超时 | 需要硬时间限制 | 低：已设计 `executionTimeout` + `maxTotalFuel`，默认不启用 |
| 字节码签名 | 需要防篡改 | 低：在文件头添加 HMAC/Ed25519 签名 |

这些扩展都可以在不改变核心架构的前提下增量添加。

### 业务层面关注点（不在核心设计范围内）

以下属于部署/业务层面，由上层应用自行决策和实现，不纳入解释器核心设计：

- **字节码签名验证**（Ed25519 / HMAC）：热更新场景的防篡改需求，属于分发管线的职责
- **API 权限白/黑名单**：细粒度的宿主 API 访问控制，由 Bridge 注册策略承载
- **热更新版本管理**：字节码版本兼容性检查、灰度发布、回滚策略等
- **CDN 分发与缓存策略**：字节码的传输和存储优化
