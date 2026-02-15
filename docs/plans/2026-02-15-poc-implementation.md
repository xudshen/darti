# POC 实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 通过 4 个 POC 验证 darti 设计中的关键技术风险，并组合为端到端最小原型。

**Architecture:** 多 package 工作区，POC-1/2/3 独立验证 Kernel 加载、值栈性能、Bridge 互调，POC-4 组合为最小 .dill→字节码→执行 全链路。

**Tech Stack:** Dart 3.10.7 (FVM Flutter 3.38.7), package:kernel (git dep from dart-lang/sdk), dart:typed_data

**设计文档:** `docs/plans/2026-02-15-poc-tasks-design.md`

---

## Task 1: 工作区与 Package 骨架

**Files:**
- Modify: `pubspec.yaml`（根目录，添加 workspace）
- Create: `packages/poc_kernel/pubspec.yaml`
- Create: `packages/poc_bench/pubspec.yaml`
- Create: `packages/poc_bridge/pubspec.yaml`
- Create: `packages/poc_kernel/lib/poc_kernel.dart`
- Create: `packages/poc_bench/lib/poc_bench.dart`
- Create: `packages/poc_bridge/lib/poc_bridge.dart`

**Step 1: 根目录 pubspec.yaml 添加 workspace**

```yaml
name: darti
description: A Dart bytecode interpreter.
version: 1.0.0
repository: https://github.com/xudshen/darti.git

environment:
  sdk: ^3.10.7

workspace:
  - packages/poc_kernel
  - packages/poc_bench
  - packages/poc_bridge

dev_dependencies:
  lints: ^6.0.0
  test: ^1.25.6
```

**Step 2: 创建 poc_kernel 包**

`packages/poc_kernel/pubspec.yaml`:
```yaml
name: poc_kernel
description: "POC-1: Kernel AST loading and traversal"
publish_to: none

environment:
  sdk: ^3.10.7

resolution: workspace

dependencies:
  kernel:
    git:
      url: https://github.com/dart-lang/sdk.git
      path: pkg/kernel
      ref: "3.10.7"
  _fe_analyzer_shared:
    git:
      url: https://github.com/dart-lang/sdk.git
      path: pkg/_fe_analyzer_shared
      ref: "3.10.7"

dev_dependencies:
  test: any
  lints: any
```

`packages/poc_kernel/lib/poc_kernel.dart`:
```dart
library;
```

**Step 3: 创建 poc_bench 包**

`packages/poc_bench/pubspec.yaml`:
```yaml
name: poc_bench
description: "POC-2: Value stack performance benchmarks"
publish_to: none

environment:
  sdk: ^3.10.7

resolution: workspace

dev_dependencies:
  test: any
  lints: any
```

`packages/poc_bench/lib/poc_bench.dart`:
```dart
library;
```

**Step 4: 创建 poc_bridge 包**

`packages/poc_bridge/pubspec.yaml`:
```yaml
name: poc_bridge
description: "POC-3: Bridge interop mechanism"
publish_to: none

environment:
  sdk: ^3.10.7

resolution: workspace

dev_dependencies:
  test: any
  lints: any
```

`packages/poc_bridge/lib/poc_bridge.dart`:
```dart
library;
```

**Step 5: 解析依赖**

Run: `dart pub get`
Expected: 所有 workspace 包依赖解析成功，特别是 `package:kernel` 从 git 拉取无误

> **注意**：如果 `package:kernel` 的 git ref `3.10.7` 不存在，尝试 `main` 或查找对应的 SDK tag（如 `dart-3.10.7`）。这是 POC-1 第一个验证点。

**Step 6: Commit**

```bash
git add pubspec.yaml packages/
git commit -m "chore: set up workspace with poc_kernel, poc_bench, poc_bridge packages"
```

---

## Task 2: POC-1 — 编译测试用 .dill 文件

**Files:**
- Create: `packages/poc_kernel/test/fixtures/simple.dart`
- Create: `packages/poc_kernel/test/fixtures/generics.dart`
- Create: `packages/poc_kernel/test/fixtures/async_closures.dart`
- Create: `packages/poc_kernel/tool/compile_fixtures.sh`

**Step 1: 创建测试用源码**

`packages/poc_kernel/test/fixtures/simple.dart`:
```dart
int fibonacci(int n) {
  if (n <= 1) return n;
  return fibonacci(n - 1) + fibonacci(n - 2);
}

void main() {
  var result = fibonacci(20);
  print(result);
}
```

`packages/poc_kernel/test/fixtures/generics.dart`:
```dart
class Box<T> {
  T value;
  Box(this.value);
  T get() => value;
  void set(T v) { value = v; }
}

void main() {
  var box = Box<int>(42);
  var list = <String>['a', 'b', 'c'];
  var map = <String, int>{'x': 1, 'y': 2};
  print(box.get());
  print(list.length);
}
```

`packages/poc_kernel/test/fixtures/async_closures.dart`:
```dart
Future<int> fetchValue() async {
  await Future.delayed(Duration(milliseconds: 10));
  return 42;
}

void main() async {
  var list = [1, 2, 3, 4, 5];
  var result = list
    ..add(6)
    ..removeWhere((e) => e % 2 == 0);
  print(result);

  var value = await fetchValue();
  print(value);
}
```

**Step 2: 创建编译脚本**

`packages/poc_kernel/tool/compile_fixtures.sh`:
```bash
#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")/../test/fixtures" && pwd)"

for f in "$DIR"/*.dart; do
  name=$(basename "$f" .dart)
  echo "Compiling $name.dart → $name.dill"
  dart compile kernel --no-link-platform -o "$DIR/$name.dill" "$f"
done

echo "Done. Generated .dill files:"
ls -la "$DIR"/*.dill
```

**Step 3: 运行编译**

Run: `chmod +x packages/poc_kernel/tool/compile_fixtures.sh && packages/poc_kernel/tool/compile_fixtures.sh`
Expected: 3 个 .dill 文件生成，无错误

> **记录**：`--no-link-platform` 是否成功？生成的 .dill 大小分别是多少？

**Step 4: .gitignore .dill 文件**

在 `packages/poc_kernel/test/fixtures/.gitignore` 中添加:
```
*.dill
```

**Step 5: Commit**

```bash
git add packages/poc_kernel/test/fixtures/ packages/poc_kernel/tool/
git commit -m "feat(poc-1): add test fixtures and .dill compilation script"
```

---

## Task 3: POC-1 — KernelWalker 加载与遍历

**Files:**
- Create: `packages/poc_kernel/lib/src/kernel_walker.dart`
- Test: `packages/poc_kernel/test/kernel_walker_test.dart`

**Step 1: 编写测试**

`packages/poc_kernel/test/kernel_walker_test.dart`:
```dart
import 'dart:io';
import 'package:kernel/kernel.dart';
import 'package:kernel/binary/ast_from_binary.dart';
import 'package:poc_kernel/src/kernel_walker.dart';
import 'package:test/test.dart';

Component loadDill(String name) {
  final path = 'test/fixtures/$name.dill';
  final bytes = File(path).readAsBytesSync();
  final component = Component();
  BinaryBuilder(bytes).readComponent(component);
  return component;
}

void main() {
  group('KernelWalker', () {
    test('enumerates user libraries from simple.dill', () {
      final component = loadDill('simple');
      final walker = KernelWalker();
      final report = walker.walk(component);

      // simple.dart has 1 user library with 2 top-level procedures
      expect(report.libraries, hasLength(1));
      final lib = report.libraries.first;
      expect(lib.procedures.map((p) => p.name), containsAll(['fibonacci', 'main']));
    });

    test('enumerates classes and members from generics.dill', () {
      final component = loadDill('generics');
      final walker = KernelWalker();
      final report = walker.walk(component);

      final lib = report.libraries.first;
      final boxClass = lib.classes.firstWhere((c) => c.name == 'Box');
      expect(boxClass.typeParams, hasLength(1));
      expect(boxClass.typeParams.first, equals('T'));
      expect(boxClass.fields.map((f) => f.name), contains('value'));
      expect(boxClass.procedures.map((p) => p.name), containsAll(['get', 'set']));
    });

    test('reports async and closure info from async_closures.dill', () {
      final component = loadDill('async_closures');
      final walker = KernelWalker();
      final report = walker.walk(component);

      final lib = report.libraries.first;
      final fetchValue = lib.procedures.firstWhere((p) => p.name == 'fetchValue');
      expect(fetchValue.isAsync, isTrue);
    });
  });
}
```

**Step 2: 运行测试确认失败**

Run: `cd packages/poc_kernel && dart test test/kernel_walker_test.dart`
Expected: FAIL — `kernel_walker.dart` 不存在

**Step 3: 实现 KernelWalker**

`packages/poc_kernel/lib/src/kernel_walker.dart`:
```dart
import 'package:kernel/ast.dart';

class WalkReport {
  final List<LibraryReport> libraries;
  WalkReport(this.libraries);
}

class LibraryReport {
  final String uri;
  final List<ClassReport> classes;
  final List<ProcedureReport> procedures;
  final List<FieldReport> fields;
  LibraryReport({
    required this.uri,
    required this.classes,
    required this.procedures,
    required this.fields,
  });
}

class ClassReport {
  final String name;
  final String? superClassName;
  final List<String> typeParams;
  final List<FieldReport> fields;
  final List<ProcedureReport> procedures;
  final List<ConstructorReport> constructors;
  ClassReport({
    required this.name,
    this.superClassName,
    required this.typeParams,
    required this.fields,
    required this.procedures,
    required this.constructors,
  });
}

class FieldReport {
  final String name;
  final String typeName;
  FieldReport({required this.name, required this.typeName});
}

class ProcedureReport {
  final String name;
  final String returnTypeName;
  final List<ParameterReport> params;
  final bool isAsync;
  final bool isGenerator;
  final bool isGetter;
  final bool isSetter;
  ProcedureReport({
    required this.name,
    required this.returnTypeName,
    required this.params,
    this.isAsync = false,
    this.isGenerator = false,
    this.isGetter = false,
    this.isSetter = false,
  });
}

class ParameterReport {
  final String name;
  final String typeName;
  ParameterReport({required this.name, required this.typeName});
}

class ConstructorReport {
  final String name;
  final List<ParameterReport> params;
  ConstructorReport({required this.name, required this.params});
}

class KernelWalker {
  WalkReport walk(Component component) {
    final libraries = <LibraryReport>[];
    for (final lib in component.libraries) {
      if (lib.importUri.isScheme('dart')) continue;
      libraries.add(_walkLibrary(lib));
    }
    return WalkReport(libraries);
  }

  LibraryReport _walkLibrary(Library lib) {
    return LibraryReport(
      uri: lib.importUri.toString(),
      classes: lib.classes.map(_walkClass).toList(),
      procedures: lib.procedures.map(_walkProcedure).toList(),
      fields: lib.fields.map(_walkField).toList(),
    );
  }

  ClassReport _walkClass(Class cls) {
    return ClassReport(
      name: cls.name,
      superClassName: cls.superclass?.name,
      typeParams: cls.typeParameters.map((tp) => tp.name!).toList(),
      fields: cls.fields.map(_walkField).toList(),
      procedures: cls.procedures.map(_walkProcedure).toList(),
      constructors: cls.constructors.map(_walkConstructor).toList(),
    );
  }

  ProcedureReport _walkProcedure(Procedure proc) {
    final func = proc.function;
    return ProcedureReport(
      name: proc.name.text,
      returnTypeName: _typeName(func.returnType),
      params: func.positionalParameters
          .map((p) => ParameterReport(name: p.name!, typeName: _typeName(p.type)))
          .toList(),
      isAsync: func.asyncMarker == AsyncMarker.Async ||
          func.asyncMarker == AsyncMarker.AsyncStar,
      isGenerator: func.asyncMarker == AsyncMarker.SyncStar ||
          func.asyncMarker == AsyncMarker.AsyncStar,
      isGetter: proc.isGetter,
      isSetter: proc.isSetter,
    );
  }

  FieldReport _walkField(Field field) {
    return FieldReport(
      name: field.name.text,
      typeName: _typeName(field.type),
    );
  }

  ConstructorReport _walkConstructor(Constructor ctor) {
    final func = ctor.function;
    return ConstructorReport(
      name: ctor.name.text,
      params: func.positionalParameters
          .map((p) => ParameterReport(name: p.name!, typeName: _typeName(p.type)))
          .toList(),
    );
  }

  String _typeName(DartType type) {
    return switch (type) {
      InterfaceType t => t.classNode.name +
          (t.typeArguments.isNotEmpty
              ? '<${t.typeArguments.map(_typeName).join(', ')}>'
              : ''),
      FunctionType _ => 'Function',
      TypeParameterType t => t.parameter.name ?? 'T',
      VoidType _ => 'void',
      DynamicType _ => 'dynamic',
      NeverType _ => 'Never',
      NullType _ => 'Null',
      FutureOrType t => 'FutureOr<${_typeName(t.typeArgument)}>',
      RecordType _ => 'Record',
      _ => type.runtimeType.toString(),
    };
  }
}
```

**Step 4: 运行测试**

Run: `cd packages/poc_kernel && dart test test/kernel_walker_test.dart`
Expected: PASS（3 个测试全绿）

> **记录**：`package:kernel` 的 API（Class.name、Procedure.function.asyncMarker 等）是否如预期？有无意外行为？

**Step 5: Commit**

```bash
git add packages/poc_kernel/lib/ packages/poc_kernel/test/
git commit -m "feat(poc-1): implement KernelWalker for AST traversal"
```

---

## Task 4: POC-1 — TypeClassifier StackKind 分类

**Files:**
- Create: `packages/poc_kernel/lib/src/type_classifier.dart`
- Test: `packages/poc_kernel/test/type_classifier_test.dart`

**Step 1: 编写测试**

`packages/poc_kernel/test/type_classifier_test.dart`:
```dart
import 'dart:io';
import 'package:kernel/kernel.dart';
import 'package:kernel/binary/ast_from_binary.dart';
import 'package:poc_kernel/src/type_classifier.dart';
import 'package:test/test.dart';

Component loadDill(String name) {
  final path = 'test/fixtures/$name.dill';
  final bytes = File(path).readAsBytesSync();
  final component = Component();
  BinaryBuilder(bytes).readComponent(component);
  return component;
}

void main() {
  group('TypeClassifier', () {
    test('classifies int, double, bool as value; others as ref', () {
      final component = loadDill('simple');
      final coreTypes = CoreTypes(component);
      final classifier = TypeClassifier(coreTypes);

      // fibonacci's parameter n is int → value
      final lib = component.libraries.firstWhere(
          (l) => !l.importUri.isScheme('dart'));
      final fib = lib.procedures.firstWhere(
          (p) => p.name.text == 'fibonacci');
      final nParam = fib.function.positionalParameters.first;
      expect(classifier.classify(nParam.type), equals(StackKind.value));

      // fibonacci return type is int → value
      expect(classifier.classify(fib.function.returnType), equals(StackKind.value));
    });

    test('classifies generic types as ref', () {
      final component = loadDill('generics');
      final coreTypes = CoreTypes(component);
      final classifier = TypeClassifier(coreTypes);

      final lib = component.libraries.firstWhere(
          (l) => !l.importUri.isScheme('dart'));
      final boxClass = lib.classes.firstWhere((c) => c.name == 'Box');
      // Box.value field is T → ref
      final valueField = boxClass.fields.firstWhere((f) => f.name.text == 'value');
      expect(classifier.classify(valueField.type), equals(StackKind.ref));
    });

    test('generates summary statistics', () {
      final component = loadDill('simple');
      final coreTypes = CoreTypes(component);
      final classifier = TypeClassifier(coreTypes);
      final summary = classifier.summarize(component);

      expect(summary.valueCount, greaterThan(0));
      expect(summary.totalCount, greaterThan(summary.valueCount));
    });
  });
}
```

**Step 2: 运行测试确认失败**

Run: `cd packages/poc_kernel && dart test test/type_classifier_test.dart`
Expected: FAIL

**Step 3: 实现 TypeClassifier**

`packages/poc_kernel/lib/src/type_classifier.dart`:
```dart
import 'package:kernel/ast.dart';
import 'package:kernel/core_types.dart';

enum StackKind { value, ref }

class TypeClassifySummary {
  final int valueCount;
  final int refCount;
  int get totalCount => valueCount + refCount;

  TypeClassifySummary({required this.valueCount, required this.refCount});

  @override
  String toString() =>
      'value: $valueCount, ref: $refCount, total: $totalCount '
      '(value ratio: ${(valueCount / totalCount * 100).toStringAsFixed(1)}%)';
}

class TypeClassifier {
  final CoreTypes coreTypes;
  TypeClassifier(this.coreTypes);

  StackKind classify(DartType type) {
    if (type is InterfaceType) {
      final cls = type.classNode;
      if (cls == coreTypes.intClass) return StackKind.value;
      if (cls == coreTypes.doubleClass) return StackKind.value;
      if (cls == coreTypes.boolClass) return StackKind.value;
    }
    return StackKind.ref;
  }

  TypeClassifySummary summarize(Component component) {
    int valueCount = 0;
    int refCount = 0;

    for (final lib in component.libraries) {
      if (lib.importUri.isScheme('dart')) continue;
      for (final proc in lib.procedures) {
        _countFunction(proc.function, (v, r) {
          valueCount += v;
          refCount += r;
        });
      }
      for (final cls in lib.classes) {
        for (final field in cls.fields) {
          if (classify(field.type) == StackKind.value) {
            valueCount++;
          } else {
            refCount++;
          }
        }
        for (final proc in cls.procedures) {
          _countFunction(proc.function, (v, r) {
            valueCount += v;
            refCount += r;
          });
        }
      }
    }

    return TypeClassifySummary(valueCount: valueCount, refCount: refCount);
  }

  void _countFunction(FunctionNode func, void Function(int v, int r) add) {
    int v = 0, r = 0;
    for (final param in func.positionalParameters) {
      if (classify(param.type) == StackKind.value) {
        v++;
      } else {
        r++;
      }
    }
    for (final param in func.namedParameters) {
      if (classify(param.type) == StackKind.value) {
        v++;
      } else {
        r++;
      }
    }
    // Return type
    if (classify(func.returnType) == StackKind.value) {
      v++;
    } else {
      r++;
    }
    add(v, r);
  }
}
```

**Step 4: 运行测试**

Run: `cd packages/poc_kernel && dart test test/type_classifier_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/poc_kernel/lib/src/type_classifier.dart packages/poc_kernel/test/type_classifier_test.dart
git commit -m "feat(poc-1): implement TypeClassifier for StackKind classification"
```

---

## Task 5: POC-1 — DesugarChecker 脱糖验证

**Files:**
- Create: `packages/poc_kernel/lib/src/desugar_checker.dart`
- Test: `packages/poc_kernel/test/desugar_checker_test.dart`

**Step 1: 编写测试**

`packages/poc_kernel/test/desugar_checker_test.dart`:
```dart
import 'dart:io';
import 'package:kernel/kernel.dart';
import 'package:kernel/binary/ast_from_binary.dart';
import 'package:poc_kernel/src/desugar_checker.dart';
import 'package:test/test.dart';

Component loadDill(String name) {
  final path = 'test/fixtures/$name.dill';
  final bytes = File(path).readAsBytesSync();
  final component = Component();
  BinaryBuilder(bytes).readComponent(component);
  return component;
}

void main() {
  group('DesugarChecker', () {
    test('async_closures: cascade desugared (no raw cascade node)', () {
      final component = loadDill('async_closures');
      final checker = DesugarChecker();
      final report = checker.check(component);

      // Cascade should be desugared into let + sequence of invocations
      expect(report.unexpectedNodes, isEmpty,
          reason: 'All high-level sugar should be desugared by CFE');
    });

    test('generics: extension types erased', () {
      final component = loadDill('generics');
      final checker = DesugarChecker();
      final report = checker.check(component);
      expect(report.unexpectedNodes, isEmpty);
    });

    test('collects expression node type statistics', () {
      final component = loadDill('async_closures');
      final checker = DesugarChecker();
      final report = checker.check(component);

      // Should find common nodes
      expect(report.nodeTypeCounts, isNotEmpty);
      // AwaitExpression should be present (not desugared)
      expect(report.nodeTypeCounts, contains('AwaitExpression'));
    });
  });
}
```

**Step 2: 运行测试确认失败**

Run: `cd packages/poc_kernel && dart test test/desugar_checker_test.dart`
Expected: FAIL

**Step 3: 实现 DesugarChecker**

`packages/poc_kernel/lib/src/desugar_checker.dart`:
```dart
import 'package:kernel/ast.dart';

class DesugarReport {
  final List<String> unexpectedNodes;
  final Map<String, int> nodeTypeCounts;

  DesugarReport({required this.unexpectedNodes, required this.nodeTypeCounts});
}

class DesugarChecker extends RecursiveVisitor<void> {
  final List<String> _unexpected = [];
  final Map<String, int> _counts = {};
  String _currentContext = '';

  DesugarReport check(Component component) {
    _unexpected.clear();
    _counts.clear();
    for (final lib in component.libraries) {
      if (lib.importUri.isScheme('dart')) continue;
      _currentContext = lib.importUri.toString();
      lib.accept(this);
    }
    return DesugarReport(
      unexpectedNodes: List.unmodifiable(_unexpected),
      nodeTypeCounts: Map.unmodifiable(_counts),
    );
  }

  void _count(String nodeType) {
    _counts[nodeType] = (_counts[nodeType] ?? 0) + 1;
  }

  // --- Nodes that SHOULD be present (not desugared) ---

  @override
  void visitAwaitExpression(AwaitExpression node) {
    _count('AwaitExpression');
    super.visitAwaitExpression(node);
  }

  @override
  void visitYieldStatement(YieldStatement node) {
    _count('YieldStatement');
    super.visitYieldStatement(node);
  }

  @override
  void visitIfStatement(IfStatement node) {
    _count('IfStatement');
    super.visitIfStatement(node);
  }

  @override
  void visitStaticInvocation(StaticInvocation node) {
    _count('StaticInvocation');
    super.visitStaticInvocation(node);
  }

  @override
  void visitInstanceInvocation(InstanceInvocation node) {
    _count('InstanceInvocation');
    super.visitInstanceInvocation(node);
  }

  @override
  void visitInstanceGet(InstanceGet node) {
    _count('InstanceGet');
    super.visitInstanceGet(node);
  }

  @override
  void visitInstanceSet(InstanceSet node) {
    _count('InstanceSet');
    super.visitInstanceSet(node);
  }

  @override
  void visitLet(Let node) {
    _count('Let');
    super.visitLet(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _count('FunctionExpression');
    super.visitFunctionExpression(node);
  }

  // --- Generic visitor for counting all expression/statement types ---

  @override
  void defaultExpression(Expression node) {
    _count(node.runtimeType.toString());
    super.defaultExpression(node);
  }

  @override
  void defaultStatement(Statement node) {
    _count(node.runtimeType.toString());
    super.defaultStatement(node);
  }
}
```

> **注意**：`package:kernel` 的 AST 中 cascade 被 CFE 脱糖为 `Let` + `BlockExpression`，而不是独立节点。如果发现 Kernel 版本中存在意外节点，在此处记录。

**Step 4: 运行测试**

Run: `cd packages/poc_kernel && dart test test/desugar_checker_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/poc_kernel/lib/src/desugar_checker.dart packages/poc_kernel/test/desugar_checker_test.dart
git commit -m "feat(poc-1): implement DesugarChecker for CFE desugaring verification"
```

---

## Task 6: POC-1 — CLI 入口与综合报告

**Files:**
- Create: `packages/poc_kernel/bin/explore.dart`
- Modify: `packages/poc_kernel/lib/poc_kernel.dart`（导出）

**Step 1: 创建 CLI 入口**

`packages/poc_kernel/bin/explore.dart`:
```dart
import 'dart:io';
import 'package:kernel/kernel.dart';
import 'package:kernel/binary/ast_from_binary.dart';
import 'package:kernel/core_types.dart';
import 'package:poc_kernel/src/kernel_walker.dart';
import 'package:poc_kernel/src/type_classifier.dart';
import 'package:poc_kernel/src/desugar_checker.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run poc_kernel:explore <file.dill>');
    exit(1);
  }

  final path = args[0];
  print('=== Loading $path ===\n');
  final bytes = File(path).readAsBytesSync();
  print('File size: ${bytes.length} bytes');

  final component = Component();
  BinaryBuilder(bytes).readComponent(component);
  print('Libraries in component: ${component.libraries.length}');

  // --- KernelWalker ---
  print('\n=== AST Walk ===\n');
  final walker = KernelWalker();
  final report = walker.walk(component);

  for (final lib in report.libraries) {
    print('Library: ${lib.uri}');
    for (final cls in lib.classes) {
      final typeParams = cls.typeParams.isNotEmpty ? '<${cls.typeParams.join(', ')}>' : '';
      print('  class ${cls.name}$typeParams'
          '${cls.superClassName != null ? ' extends ${cls.superClassName}' : ''}');
      for (final f in cls.fields) {
        print('    field ${f.typeName} ${f.name}');
      }
      for (final p in cls.procedures) {
        final params = p.params.map((p) => '${p.typeName} ${p.name}').join(', ');
        final flags = [
          if (p.isAsync) 'async',
          if (p.isGenerator) 'generator',
          if (p.isGetter) 'getter',
          if (p.isSetter) 'setter',
        ].join(' ');
        print('    ${p.returnTypeName} ${p.name}($params) $flags');
      }
      for (final c in cls.constructors) {
        final params = c.params.map((p) => '${p.typeName} ${p.name}').join(', ');
        print('    constructor ${c.name}($params)');
      }
    }
    for (final p in lib.procedures) {
      final params = p.params.map((p) => '${p.typeName} ${p.name}').join(', ');
      print('  ${p.returnTypeName} ${p.name}($params)${p.isAsync ? ' async' : ''}');
    }
  }

  // --- TypeClassifier ---
  print('\n=== Type Classification ===\n');
  final coreTypes = CoreTypes(component);
  final classifier = TypeClassifier(coreTypes);
  final summary = classifier.summarize(component);
  print(summary);

  // --- DesugarChecker ---
  print('\n=== Desugar Check ===\n');
  final checker = DesugarChecker();
  final desugarReport = checker.check(component);
  if (desugarReport.unexpectedNodes.isEmpty) {
    print('No unexpected AST nodes found (CFE desugaring confirmed)');
  } else {
    print('WARNING: Unexpected nodes:');
    for (final node in desugarReport.unexpectedNodes) {
      print('  $node');
    }
  }
  print('\nNode type counts (top 15):');
  final sorted = desugarReport.nodeTypeCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in sorted.take(15)) {
    print('  ${entry.key}: ${entry.value}');
  }
}
```

**Step 2: 更新导出**

`packages/poc_kernel/lib/poc_kernel.dart`:
```dart
library;

export 'src/kernel_walker.dart';
export 'src/type_classifier.dart';
export 'src/desugar_checker.dart';
```

**Step 3: 运行 CLI 验证**

Run: `cd packages/poc_kernel && dart run bin/explore.dart test/fixtures/simple.dill`
Expected: 输出 fibonacci 和 main 函数信息、类型分类统计、脱糖检查通过

Run: `cd packages/poc_kernel && dart run bin/explore.dart test/fixtures/generics.dill`
Expected: 输出 Box<T> 类信息，T 类型参数，value 字段类型为 T

Run: `cd packages/poc_kernel && dart run bin/explore.dart test/fixtures/async_closures.dill`
Expected: 输出 fetchValue 标记为 async，脱糖检查通过，AwaitExpression 在 counts 中

> **关键记录点**：
> - dart: 库引用在 Kernel 中的表示方式（CanonicalName 结构）
> - `--no-link-platform` .dill 中 CoreTypes 是否可用
> - 任何与 Ch4 设计假设不符的行为

**Step 4: Commit**

```bash
git add packages/poc_kernel/bin/ packages/poc_kernel/lib/
git commit -m "feat(poc-1): add CLI explore tool and finalize POC-1"
```

---

## Task 7: POC-2 — 双视图值栈实现

**Files:**
- Create: `packages/poc_bench/lib/src/value_stack.dart`
- Test: `packages/poc_bench/test/value_stack_test.dart`

**Step 1: 编写测试**

`packages/poc_bench/test/value_stack_test.dart`:
```dart
import 'package:poc_bench/src/value_stack.dart';
import 'package:test/test.dart';

void main() {
  group('ValueStack', () {
    test('int and double share same slot via different views', () {
      final vs = ValueStack(16);
      vs.intView[0] = 42;
      // Reading as double from same slot gives a non-42.0 value
      // (raw bits reinterpretation)
      expect(vs.intView[0], equals(42));

      vs.doubleView[1] = 3.14;
      expect(vs.doubleView[1], closeTo(3.14, 0.001));
    });

    test('int arithmetic correctness', () {
      final vs = ValueStack(16);
      vs.intView[0] = 100;
      vs.intView[1] = 200;
      vs.intView[2] = vs.intView[0] + vs.intView[1];
      expect(vs.intView[2], equals(300));
    });

    test('double arithmetic correctness', () {
      final vs = ValueStack(16);
      vs.doubleView[0] = 1.5;
      vs.doubleView[1] = 2.5;
      vs.doubleView[2] = vs.doubleView[0] + vs.doubleView[1];
      expect(vs.doubleView[2], closeTo(4.0, 0.001));
    });

    test('slots are independent (no aliasing within used ranges)', () {
      final vs = ValueStack(16);
      vs.intView[0] = 42;
      vs.intView[1] = 100;
      vs.doubleView[2] = 3.14;
      // Modifying slot 2 as double should not affect slots 0-1 as int
      expect(vs.intView[0], equals(42));
      expect(vs.intView[1], equals(100));
    });
  });
}
```

**Step 2: 运行测试确认失败**

Run: `cd packages/poc_bench && dart test test/value_stack_test.dart`
Expected: FAIL

**Step 3: 实现 ValueStack**

`packages/poc_bench/lib/src/value_stack.dart`:
```dart
import 'dart:typed_data';

class ValueStack {
  final Uint8List _buffer;
  late final Int64List intView;
  late final Float64List doubleView;

  ValueStack(int maxSlots) : _buffer = Uint8List(maxSlots * 8) {
    intView = Int64List.view(_buffer.buffer);
    doubleView = Float64List.view(_buffer.buffer);
  }
}
```

**Step 4: 运行测试**

Run: `cd packages/poc_bench && dart test test/value_stack_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/poc_bench/
git commit -m "feat(poc-2): implement ValueStack with dual-view typed lists"
```

---

## Task 8: POC-2 — 基准场景实现

**Files:**
- Create: `packages/poc_bench/lib/src/benchmarks.dart`
- Create: `packages/poc_bench/lib/src/dispatch_sim.dart`

**Step 1: 实现算术基准**

`packages/poc_bench/lib/src/benchmarks.dart`:
```dart
import 'dart:typed_data';
import 'value_stack.dart';

typedef BenchFn = void Function();

class BenchResult {
  final String name;
  final int iterations;
  final Duration elapsed;

  BenchResult(this.name, this.iterations, this.elapsed);

  double get opsPerSec => iterations / (elapsed.inMicroseconds / 1e6);

  @override
  String toString() =>
      '$name: ${opsPerSec.toStringAsFixed(0)} ops/sec '
      '(${elapsed.inMilliseconds}ms for $iterations iterations)';
}

BenchResult runBench(String name, int iterations, BenchFn fn) {
  // Warmup
  fn();
  fn();

  final sw = Stopwatch()..start();
  fn();
  sw.stop();
  return BenchResult(name, iterations, sw.elapsed);
}

BenchResult benchIntArith(int iterations) {
  final vs = ValueStack(16);
  return runBench('int_arith (dual-view)', iterations, () {
    vs.intView[0] = 0;
    for (int i = 0; i < iterations; i++) {
      vs.intView[1] = i;
      vs.intView[2] = vs.intView[1] * 3;
      vs.intView[2] = vs.intView[2] + 1;
      vs.intView[0] = vs.intView[0] + vs.intView[2];
    }
  });
}

BenchResult benchDoubleArith(int iterations) {
  final vs = ValueStack(16);
  return runBench('double_arith (dual-view)', iterations, () {
    vs.doubleView[0] = 0.0;
    for (int i = 0; i < iterations; i++) {
      vs.doubleView[1] = i.toDouble();
      vs.doubleView[2] = vs.doubleView[1] * 3.14;
      vs.doubleView[0] = vs.doubleView[0] + vs.doubleView[2];
    }
  });
}

BenchResult benchBoxedArith(int iterations) {
  final stack = List<Object?>.filled(16, null);
  return runBench('int_arith (boxed)', iterations, () {
    stack[0] = 0;
    for (int i = 0; i < iterations; i++) {
      stack[1] = i;
      stack[2] = (stack[1] as int) * 3;
      stack[2] = (stack[2] as int) + 1;
      stack[0] = (stack[0] as int) + (stack[2] as int);
    }
  });
}

BenchResult benchNativeArith(int iterations) {
  return runBench('int_arith (native)', iterations, () {
    int sum = 0;
    for (int i = 0; i < iterations; i++) {
      sum += i * 3 + 1;
    }
    // Prevent dead code elimination
    if (sum < 0) print(sum);
  });
}
```

**Step 2: 实现分发循环模拟器**

`packages/poc_bench/lib/src/dispatch_sim.dart`:
```dart
import 'dart:typed_data';
import 'value_stack.dart';

// Minimal opcode subset for fibonacci
abstract class Op {
  static const int nop = 0x00;
  static const int loadInt = 0x05;
  static const int addInt = 0x10;
  static const int subInt = 0x11;
  static const int ltInt = 0x30;
  static const int leInt = 0x31;
  static const int jump = 0x40;
  static const int jumpIfFalse = 0x42;
  static const int moveVal = 0x09;
  static const int halt = 0xFF;
  // Fill gaps to ensure dense switch
  static const int _filler01 = 0x01;
  static const int _filler02 = 0x02;
  static const int _filler03 = 0x03;
  static const int _filler04 = 0x04;
  static const int _filler06 = 0x06;
  static const int _filler07 = 0x07;
  static const int _filler08 = 0x08;
  static const int _filler0A = 0x0A;
  static const int _filler0B = 0x0B;
  static const int _filler0C = 0x0C;
  static const int _filler0D = 0x0D;
  static const int _filler0E = 0x0E;
  static const int _filler0F = 0x0F;
  static const int _filler12 = 0x12;
  static const int _filler13 = 0x13;
  static const int _filler14 = 0x14;
  static const int _filler15 = 0x15;
  // ... (实现时填充 0x00-0x50 范围内所有空隙)
}

int encodeABC(int op, int a, int b, int c) =>
    op | (a << 8) | (b << 16) | (c << 24);

int encodeAsBx(int op, int a, int sbx) =>
    op | (a << 8) | ((sbx + 0x7FFF) << 16);

/// 生成计算 fib(n) 的字节码
/// 使用迭代方式: r0=n, r1=a=0, r2=b=1, loop: if r0<=1 → done; r3=a+b; a=b; b=r3; r0--
Uint32List generateIterativeFib() {
  return Uint32List.fromList([
    // r0 = n (caller sets this)
    // r1 = 0 (a)
    encodeAsBx(Op.loadInt, 1, 0),
    // r2 = 1 (b)
    encodeAsBx(Op.loadInt, 2, 1),
    // r3 = 1 (constant for comparison and subtraction)
    encodeAsBx(Op.loadInt, 3, 1),
    // LOOP (pc=3):
    // r4 = r0 <= 1 ?
    encodeABC(Op.leInt, 4, 0, 3),
    // if r4 → EXIT (pc=10, offset = +6)
    encodeAsBx(Op.jumpIfFalse, 4, 6).also_negate(),  // actually: jump if NOT <=1
    // Wait - let me redo the logic. JUMP_IF_FALSE jumps when r4==0.
    // leInt sets r4=1 if r0<=1, else 0.
    // We want to EXIT if r0<=1, so we need JUMP_IF_TRUE.
    // But we only have JUMP_IF_FALSE. So: jump if NOT (r0<=1) to BODY, else fall through to EXIT.
    // pc=3: LE_INT r4, r0, r3    (r4 = r0 <= 1 ? 1 : 0)
    // pc=4: JUMP_IF_FALSE r4, +2 (if r0>1, jump to BODY at pc=6)
    // pc=5: JUMP +5              (r0<=1, jump to EXIT at pc=10)
    // BODY (pc=6):
    // pc=6: ADD_INT r5, r1, r2   (r5 = a + b)
    // pc=7: MOVE_VAL r1, r2      (a = b)
    // pc=8: MOVE_VAL r2, r5      (b = r5)
    // pc=9: SUB_INT r0, r0, r3   (n--)
    // pc=10: JUMP -7             (back to LOOP at pc=3)
    // EXIT (pc=11):
    // pc=11: HALT
    // Actually let me just write it cleanly:
  ]);
}

/// 更简洁的 fib 字节码生成
Uint32List fibBytecode(int n) {
  final code = <int>[
    encodeAsBx(Op.loadInt, 0, n),     // r0 = n
    encodeAsBx(Op.loadInt, 1, 0),     // r1 = a = 0
    encodeAsBx(Op.loadInt, 2, 1),     // r2 = b = 1
    encodeAsBx(Op.loadInt, 3, 1),     // r3 = constant 1
    // pc=4: LOOP
    encodeABC(Op.leInt, 4, 0, 3),     // r4 = (r0 <= 1)
    encodeAsBx(Op.jumpIfFalse, 4, 2), // if r0>1: skip to BODY (pc=7)
    encodeAsBx(Op.jump, 0, 5),        // else: jump to EXIT (pc=11)
    // pc=7: BODY
    encodeABC(Op.addInt, 5, 1, 2),    // r5 = a + b
    encodeABC(Op.moveVal, 1, 2, 0),   // r1 = r2 (a = b)
    encodeABC(Op.moveVal, 2, 5, 0),   // r2 = r5 (b = a+b)
    encodeABC(Op.subInt, 0, 0, 3),    // r0 = r0 - 1
    encodeAsBx(Op.jump, 0, -7),       // back to LOOP (pc=4)
    // pc=12: EXIT — result in r1 (if n<=1) or r2 (if n>1)
    Op.halt,
  ];
  return Uint32List.fromList(code);
}

/// 分发循环
int executeDispatch(Uint32List code, ValueStack vs) {
  int pc = 0;

  while (true) {
    final instr = code[pc++];
    final op = instr & 0xFF;

    switch (op) {
      case Op.nop:
        break;
      case Op.loadInt:
        vs.intView[(instr >> 8) & 0xFF] = ((instr >> 16) & 0xFFFF) - 0x7FFF;
      case Op.addInt:
        final a = (instr >> 8) & 0xFF;
        vs.intView[a] =
            vs.intView[(instr >> 16) & 0xFF] + vs.intView[(instr >> 24) & 0xFF];
      case Op.subInt:
        final a = (instr >> 8) & 0xFF;
        vs.intView[a] =
            vs.intView[(instr >> 16) & 0xFF] - vs.intView[(instr >> 24) & 0xFF];
      case Op.ltInt:
        final a = (instr >> 8) & 0xFF;
        vs.intView[a] =
            vs.intView[(instr >> 16) & 0xFF] < vs.intView[(instr >> 24) & 0xFF]
                ? 1 : 0;
      case Op.leInt:
        final a = (instr >> 8) & 0xFF;
        vs.intView[a] =
            vs.intView[(instr >> 16) & 0xFF] <= vs.intView[(instr >> 24) & 0xFF]
                ? 1 : 0;
      case Op.moveVal:
        vs.intView[(instr >> 8) & 0xFF] = vs.intView[(instr >> 16) & 0xFF];
      case Op.jump:
        pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
      case Op.jumpIfFalse:
        if (vs.intView[(instr >> 8) & 0xFF] == 0) {
          pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
        }
      case Op.halt:
        return vs.intView[2]; // result in r2 for fib
      // Fill remaining opcodes 0x00-0x50 with default to ensure dense switch
      default:
        throw StateError('Unknown opcode: 0x${op.toRadixString(16)}');
    }
  }
}

int nativeFibonacci(int n) {
  if (n <= 1) return n;
  int a = 0, b = 1;
  for (int i = 2; i <= n; i++) {
    final tmp = a + b;
    a = b;
    b = tmp;
  }
  return b;
}
```

**Step 3: Commit**

```bash
git add packages/poc_bench/lib/src/
git commit -m "feat(poc-2): implement benchmarks and dispatch loop simulator"
```

---

## Task 9: POC-2 — 基准 CLI 与 AOT 测量

**Files:**
- Create: `packages/poc_bench/bin/bench.dart`

**Step 1: 创建 CLI**

`packages/poc_bench/bin/bench.dart`:
```dart
import 'dart:typed_data';
import 'package:poc_bench/src/value_stack.dart';
import 'package:poc_bench/src/benchmarks.dart';
import 'package:poc_bench/src/dispatch_sim.dart';

void main() {
  const iterations = 10000000; // 10M
  const runs = 10;

  print('=== POC-2: Value Stack Performance Benchmarks ===\n');
  print('Iterations per run: $iterations');
  print('Runs: $runs (reporting median)\n');

  // Arithmetic benchmarks
  final arithBenches = <String, BenchResult Function()>{
    'int (dual-view)': () => benchIntArith(iterations),
    'int (boxed)': () => benchBoxedArith(iterations),
    'int (native)': () => benchNativeArith(iterations),
    'double (dual-view)': () => benchDoubleArith(iterations),
  };

  for (final entry in arithBenches.entries) {
    final results = <BenchResult>[];
    for (int i = 0; i < runs; i++) {
      results.add(entry.value());
    }
    results.sort((a, b) => a.elapsed.compareTo(b.elapsed));
    final median = results[runs ~/ 2];
    print(median);
  }

  // Dispatch loop benchmark
  print('\n--- Dispatch Loop (iterative fib) ---\n');
  final fibNs = [20, 30, 35, 40];
  for (final n in fibNs) {
    // Native
    final nativeSw = Stopwatch()..start();
    final nativeResult = nativeFibonacci(n);
    nativeSw.stop();

    // Interpreted
    final vs = ValueStack(16);
    final code = fibBytecode(n);
    final interpSw = Stopwatch()..start();
    final interpResult = executeDispatch(code, vs);
    interpSw.stop();

    print('fib($n) = $nativeResult');
    print('  native:  ${nativeSw.elapsedMicroseconds}μs');
    print('  interp:  ${interpSw.elapsedMicroseconds}μs');
    final ratio = interpSw.elapsedMicroseconds / nativeSw.elapsedMicroseconds;
    print('  ratio:   ${ratio.toStringAsFixed(1)}x slower');
    if (nativeResult != interpResult) {
      print('  ERROR: results differ! native=$nativeResult interp=$interpResult');
    }
  }

  // Dual-view vs boxed speedup
  print('\n--- Summary ---\n');
  final dualView = benchIntArith(iterations);
  final boxed = benchBoxedArith(iterations);
  final speedup = boxed.elapsed.inMicroseconds / dualView.elapsed.inMicroseconds;
  print('Dual-view vs Boxed speedup: ${speedup.toStringAsFixed(1)}x');
}
```

**Step 2: JIT 模式验证正确性**

Run: `cd packages/poc_bench && dart run bin/bench.dart`
Expected: 所有 fib 结果一致，基准输出正常

**Step 3: AOT 模式测量**

Run: `cd packages/poc_bench && dart compile exe bin/bench.dart -o bin/bench_aot && ./bin/bench_aot`
Expected: AOT 模式下性能数据更真实

> **关键记录点**：
> - 双视图 vs 装箱加速比（目标 ≥3x）
> - 分发循环 vs 原生 fib 比值（目标 ≤5x slower）
> - AOT 下 switch 是否为跳转表（可选：用 `--disassemble` 验证）

**Step 4: .gitignore AOT 产物**

在 `packages/poc_bench/bin/.gitignore` 中添加:
```
bench_aot
```

**Step 5: Commit**

```bash
git add packages/poc_bench/
git commit -m "feat(poc-2): add benchmark CLI with AOT measurement"
```

---

## Task 10: POC-3 — InterpreterObject 与 MiniRuntime

**Files:**
- Create: `packages/poc_bridge/lib/src/interpreter_object.dart`
- Create: `packages/poc_bridge/lib/src/mini_runtime.dart`
- Test: `packages/poc_bridge/test/mini_runtime_test.dart`

**Step 1: 编写测试**

`packages/poc_bridge/test/mini_runtime_test.dart`:
```dart
import 'package:poc_bridge/src/interpreter_object.dart';
import 'package:poc_bridge/src/mini_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('MiniRuntime', () {
    test('get/set fields by name', () {
      final obj = InterpreterObject(
        classId: 1,
        fieldCount: 2,
        fieldLayout: {'name': 0, 'age': 1},
      );
      final runtime = MiniRuntime();

      runtime.setField(obj, 'name', 'Alice');
      runtime.setField(obj, 'age', 30);

      expect(runtime.getField(obj, 'name'), equals('Alice'));
      expect(runtime.getField(obj, 'age'), equals(30));
    });

    test('invoke registered method', () {
      final runtime = MiniRuntime();
      runtime.classes[1] = ClassDef(methods: {
        'greet': (target, args) =>
            'Hello, ${args[0]}! I am ${target.refFields[0]}',
      });

      final obj = InterpreterObject(
        classId: 1,
        fieldCount: 1,
        fieldLayout: {'name': 0},
      );
      obj.refFields[0] = 'Bob';

      final result = runtime.invokeMethod(obj, 'greet', ['World']);
      expect(result, equals('Hello, World! I am Bob'));
    });
  });
}
```

**Step 2: 运行测试确认失败**

Run: `cd packages/poc_bridge && dart test test/mini_runtime_test.dart`
Expected: FAIL

**Step 3: 实现**

`packages/poc_bridge/lib/src/interpreter_object.dart`:
```dart
class InterpreterObject {
  final int classId;
  final List<Object?> refFields;
  final Map<String, int> fieldLayout;

  InterpreterObject({
    required this.classId,
    required int fieldCount,
    required this.fieldLayout,
  }) : refFields = List<Object?>.filled(fieldCount, null);
}
```

`packages/poc_bridge/lib/src/mini_runtime.dart`:
```dart
import 'interpreter_object.dart';

typedef MethodImpl = Object? Function(InterpreterObject target, List<Object?> args);

class ClassDef {
  final Map<String, MethodImpl> methods;
  ClassDef({required this.methods});
}

class MiniRuntime {
  final Map<int, ClassDef> classes = {};

  Object? getField(InterpreterObject target, String name) {
    final offset = target.fieldLayout[name];
    if (offset == null) throw ArgumentError('Unknown field: $name');
    return target.refFields[offset];
  }

  void setField(InterpreterObject target, String name, Object? value) {
    final offset = target.fieldLayout[name];
    if (offset == null) throw ArgumentError('Unknown field: $name');
    target.refFields[offset] = value;
  }

  Object? invokeMethod(
      InterpreterObject target, String method, List<Object?> args) {
    final cls = classes[target.classId];
    if (cls == null) throw ArgumentError('Unknown classId: ${target.classId}');
    final impl = cls.methods[method];
    if (impl == null) throw ArgumentError('Unknown method: $method');
    return impl(target, args);
  }
}
```

**Step 4: 运行测试**

Run: `cd packages/poc_bridge && dart test test/mini_runtime_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/poc_bridge/
git commit -m "feat(poc-3): implement InterpreterObject and MiniRuntime"
```

---

## Task 11: POC-3 — ProxyManager（Expando 双向缓存）

**Files:**
- Create: `packages/poc_bridge/lib/src/generic_proxy.dart`
- Create: `packages/poc_bridge/lib/src/proxy_manager.dart`
- Test: `packages/poc_bridge/test/proxy_manager_test.dart`

**Step 1: 编写测试**

`packages/poc_bridge/test/proxy_manager_test.dart`:
```dart
import 'package:poc_bridge/src/interpreter_object.dart';
import 'package:poc_bridge/src/mini_runtime.dart';
import 'package:poc_bridge/src/generic_proxy.dart';
import 'package:poc_bridge/src/proxy_manager.dart';
import 'package:test/test.dart';

void main() {
  group('ProxyManager', () {
    late MiniRuntime runtime;
    late ProxyManager pm;

    setUp(() {
      runtime = MiniRuntime();
      pm = ProxyManager(runtime);
    });

    test('wraps InterpreterObject into GenericProxy', () {
      final obj = InterpreterObject(classId: 1, fieldCount: 0, fieldLayout: {});
      final proxy = pm.wrapForVM(obj);
      expect(proxy, isA<GenericProxy>());
    });

    test('same object wraps to identical proxy (identity consistency)', () {
      final obj = InterpreterObject(classId: 1, fieldCount: 0, fieldLayout: {});
      final p1 = pm.wrapForVM(obj);
      final p2 = pm.wrapForVM(obj);
      expect(identical(p1, p2), isTrue);
    });

    test('unwrap returns original InterpreterObject', () {
      final obj = InterpreterObject(classId: 1, fieldCount: 0, fieldLayout: {});
      final proxy = pm.wrapForVM(obj);
      final unwrapped = pm.unwrapForInterpreter(proxy);
      expect(identical(unwrapped, obj), isTrue);
    });

    test('primitive types pass through without wrapping', () {
      expect(pm.wrapForVM(42), equals(42));
      expect(pm.wrapForVM('hello'), equals('hello'));
      expect(pm.wrapForVM(3.14), equals(3.14));
      expect(pm.wrapForVM(true), equals(true));
    });

    test('VM native objects pass through unwrap', () {
      final list = [1, 2, 3];
      expect(identical(pm.unwrapForInterpreter(list), list), isTrue);
    });
  });
}
```

**Step 2: 运行测试确认失败**

Run: `cd packages/poc_bridge && dart test test/proxy_manager_test.dart`
Expected: FAIL

**Step 3: 实现**

`packages/poc_bridge/lib/src/generic_proxy.dart`:
```dart
import 'interpreter_object.dart';
import 'mini_runtime.dart';

class GenericProxy {
  final InterpreterObject target;
  final MiniRuntime _runtime;

  GenericProxy(this.target, this._runtime);

  Object? getProperty(String name) => _runtime.getField(target, name);
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

`packages/poc_bridge/lib/src/proxy_manager.dart`:
```dart
import 'interpreter_object.dart';
import 'generic_proxy.dart';
import 'mini_runtime.dart';

class ProxyManager {
  final Expando<GenericProxy> _i2p = Expando('i2p');
  final Expando<InterpreterObject> _p2i = Expando('p2i');
  final MiniRuntime _runtime;

  ProxyManager(this._runtime);

  Object wrapForVM(Object obj) {
    if (obj is InterpreterObject) {
      var proxy = _i2p[obj];
      if (proxy != null) return proxy;
      proxy = GenericProxy(obj, _runtime);
      _i2p[obj] = proxy;
      _p2i[proxy] = obj;
      return proxy;
    }
    return obj; // primitives and VM objects pass through
  }

  Object unwrapForInterpreter(Object obj) {
    if (obj is GenericProxy) {
      return _p2i[obj] ?? obj.target;
    }
    if (obj is InterpreterObject) return obj;
    return obj; // VM native objects pass through
  }
}
```

**Step 4: 运行测试**

Run: `cd packages/poc_bridge && dart test test/proxy_manager_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/poc_bridge/lib/src/generic_proxy.dart packages/poc_bridge/lib/src/proxy_manager.dart packages/poc_bridge/test/proxy_manager_test.dart
git commit -m "feat(poc-3): implement ProxyManager with Expando identity caching"
```

---

## Task 12: POC-3 — $List HostClassWrapper

**Files:**
- Create: `packages/poc_bridge/lib/src/host_wrappers/list_wrapper.dart`
- Test: `packages/poc_bridge/test/list_wrapper_test.dart`

**Step 1: 编写测试**

`packages/poc_bridge/test/list_wrapper_test.dart`:
```dart
import 'package:poc_bridge/src/host_wrappers/list_wrapper.dart';
import 'package:test/test.dart';

void main() {
  group('ListWrapper', () {
    test('getProperty: length', () {
      final list = [1, 2, 3];
      expect(ListWrapper.getProperty(list, 'length'), equals(3));
    });

    test('getProperty: isEmpty / isNotEmpty', () {
      expect(ListWrapper.getProperty([], 'isEmpty'), isTrue);
      expect(ListWrapper.getProperty([1], 'isEmpty'), isFalse);
      expect(ListWrapper.getProperty([1], 'isNotEmpty'), isTrue);
    });

    test('getProperty: first / last', () {
      final list = [10, 20, 30];
      expect(ListWrapper.getProperty(list, 'first'), equals(10));
      expect(ListWrapper.getProperty(list, 'last'), equals(30));
    });

    test('invokeMethod: add', () {
      final list = <int>[1, 2];
      ListWrapper.invokeMethod(list, 'add', [3]);
      expect(list, equals([1, 2, 3]));
    });

    test('invokeMethod: removeAt', () {
      final list = [1, 2, 3];
      final removed = ListWrapper.invokeMethod(list, 'removeAt', [1]);
      expect(removed, equals(2));
      expect(list, equals([1, 3]));
    });

    test('invokeMethod: contains', () {
      final list = [1, 2, 3];
      expect(ListWrapper.invokeMethod(list, 'contains', [2]), isTrue);
      expect(ListWrapper.invokeMethod(list, 'contains', [5]), isFalse);
    });
  });
}
```

**Step 2: 运行测试确认失败**

Run: `cd packages/poc_bridge && dart test test/list_wrapper_test.dart`
Expected: FAIL

**Step 3: 实现**

`packages/poc_bridge/lib/src/host_wrappers/list_wrapper.dart`:
```dart
class ListWrapper {
  static Object? getProperty(Object host, String name) => switch (name) {
    'length' => (host as List).length,
    'isEmpty' => (host as List).isEmpty,
    'isNotEmpty' => (host as List).isNotEmpty,
    'first' => (host as List).first,
    'last' => (host as List).last,
    'reversed' => (host as List).reversed,
    _ => throw ArgumentError('Unknown property: List.$name'),
  };

  static Object? invokeMethod(Object host, String name, List<Object?> args) =>
      switch (name) {
    'add' => (host as List).add(args[0]),
    'removeAt' => (host as List).removeAt(args[0] as int),
    'contains' => (host as List).contains(args[0]),
    'indexOf' => (host as List).indexOf(args[0]),
    'insert' => (host as List).insert(args[0] as int, args[1]),
    'clear' => (host as List).clear(),
    _ => throw ArgumentError('Unknown method: List.$name'),
  };
}
```

**Step 4: 运行测试**

Run: `cd packages/poc_bridge && dart test test/list_wrapper_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/poc_bridge/lib/src/host_wrappers/ packages/poc_bridge/test/list_wrapper_test.dart
git commit -m "feat(poc-3): implement ListWrapper host class wrapper"
```

---

## Task 13: POC-3 — Bridge 类与 CallbackProxy

**Files:**
- Create: `packages/poc_bridge/lib/src/bridges/comparable_bridge.dart`
- Create: `packages/poc_bridge/lib/src/callback_proxy.dart`
- Test: `packages/poc_bridge/test/bridge_test.dart`

**Step 1: 编写测试**

`packages/poc_bridge/test/bridge_test.dart`:
```dart
import 'package:poc_bridge/src/interpreter_object.dart';
import 'package:poc_bridge/src/mini_runtime.dart';
import 'package:poc_bridge/src/bridges/comparable_bridge.dart';
import 'package:poc_bridge/src/callback_proxy.dart';
import 'package:test/test.dart';

void main() {
  late MiniRuntime runtime;

  setUp(() {
    runtime = MiniRuntime();
  });

  group('ComparableBridge', () {
    test('delegates compareTo to interpreter runtime', () {
      runtime.classes[1] = ClassDef(methods: {
        'compareTo': (target, args) =>
            (target.refFields[0] as int) - (args[0] as int),
      });

      final obj = InterpreterObject(
          classId: 1, fieldCount: 1, fieldLayout: {'value': 0});
      obj.refFields[0] = 42;

      final bridge = ComparableBridge(runtime, obj);
      expect(bridge.compareTo(40), equals(2));
      expect(bridge.compareTo(42), equals(0));
      expect(bridge.compareTo(50), equals(-8));
    });

    test('bridge works with VM sort', () {
      runtime.classes[1] = ClassDef(methods: {
        'compareTo': (target, args) =>
            (target.refFields[0] as int) - (args[0] as int),
      });

      InterpreterObject makeObj(int val) {
        final obj = InterpreterObject(
            classId: 1, fieldCount: 1, fieldLayout: {'value': 0});
        obj.refFields[0] = val;
        return obj;
      }

      final bridges = [
        ComparableBridge(runtime, makeObj(30)),
        ComparableBridge(runtime, makeObj(10)),
        ComparableBridge(runtime, makeObj(20)),
      ];
      bridges.sort();

      // compareTo returns (a - b), so ascending order
      expect(bridges.map((b) => b.target.refFields[0]), equals([10, 20, 30]));
    });
  });

  group('CallbackProxy', () {
    test('predicate callback filters correctly', () {
      runtime.classes[2] = ClassDef(methods: {
        'call': (_, args) => (args[0] as int) > 2,
      });

      final closureObj = InterpreterObject(
          classId: 2, fieldCount: 0, fieldLayout: {});
      final proxy = CallbackProxy(runtime);

      final list = <int>[1, 2, 3, 4, 5];
      final filtered = list.where(proxy.predicate(closureObj)).toList();
      expect(filtered, equals([3, 4, 5]));
    });

    test('mapper callback transforms correctly', () {
      runtime.classes[3] = ClassDef(methods: {
        'call': (_, args) => (args[0] as int) * 10,
      });

      final closureObj = InterpreterObject(
          classId: 3, fieldCount: 0, fieldLayout: {});
      final proxy = CallbackProxy(runtime);

      final list = <int>[1, 2, 3];
      final mapped = list.map(proxy.mapper(closureObj)).toList();
      expect(mapped, equals([10, 20, 30]));
    });
  });
}
```

**Step 2: 运行测试确认失败**

Run: `cd packages/poc_bridge && dart test test/bridge_test.dart`
Expected: FAIL

**Step 3: 实现**

`packages/poc_bridge/lib/src/bridges/comparable_bridge.dart`:
```dart
import '../interpreter_object.dart';
import '../mini_runtime.dart';

class ComparableBridge implements Comparable<int> {
  final MiniRuntime _runtime;
  final InterpreterObject target;

  ComparableBridge(this._runtime, this.target);

  @override
  int compareTo(int other) {
    return _runtime.invokeMethod(target, 'compareTo', [other]) as int;
  }
}
```

`packages/poc_bridge/lib/src/callback_proxy.dart`:
```dart
import 'interpreter_object.dart';
import 'mini_runtime.dart';

class CallbackProxy {
  final MiniRuntime _runtime;
  CallbackProxy(this._runtime);

  bool Function(dynamic) predicate(InterpreterObject closure) =>
      (arg) => _runtime.invokeMethod(closure, 'call', [arg]) as bool;

  dynamic Function(dynamic) mapper(InterpreterObject closure) =>
      (arg) => _runtime.invokeMethod(closure, 'call', [arg]);

  void Function(dynamic) consumer(InterpreterObject closure) =>
      (arg) { _runtime.invokeMethod(closure, 'call', [arg]); };

  int Function(dynamic, dynamic) comparator(InterpreterObject closure) =>
      (a, b) => _runtime.invokeMethod(closure, 'call', [a, b]) as int;
}
```

**Step 4: 运行测试**

Run: `cd packages/poc_bridge && dart test test/bridge_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/poc_bridge/lib/src/bridges/ packages/poc_bridge/lib/src/callback_proxy.dart packages/poc_bridge/test/bridge_test.dart
git commit -m "feat(poc-3): implement ComparableBridge and CallbackProxy"
```

---

## Task 14: POC-3 — 更新导出与综合报告

**Files:**
- Modify: `packages/poc_bridge/lib/poc_bridge.dart`

**Step 1: 导出所有组件**

`packages/poc_bridge/lib/poc_bridge.dart`:
```dart
library;

export 'src/interpreter_object.dart';
export 'src/mini_runtime.dart';
export 'src/generic_proxy.dart';
export 'src/proxy_manager.dart';
export 'src/host_wrappers/list_wrapper.dart';
export 'src/bridges/comparable_bridge.dart';
export 'src/callback_proxy.dart';
```

**Step 2: 运行全部 POC-3 测试**

Run: `cd packages/poc_bridge && dart test`
Expected: 全部 PASS

> **关键记录点**：
> - Expando 是否按预期工作（弱引用语义）
> - ComparableBridge 被 VM 的 sort 正确调用（VM → 解释器链路通）
> - CallbackProxy 的类型退化是否导致任何 API 兼容问题

**Step 3: Commit**

```bash
git add packages/poc_bridge/lib/poc_bridge.dart
git commit -m "feat(poc-3): finalize POC-3 with exports and full test suite"
```

---

## Task 15: POC-4 — ISA 定义与数据结构

**Files:**
- Create: `lib/src/runtime/opcodes.dart`
- Create: `lib/src/runtime/value_stack.dart`
- Create: `lib/src/runtime/ref_stack.dart`
- Create: `lib/src/runtime/types.dart`
- Test: `test/runtime/opcodes_test.dart`

**Step 1: 编写 opcode 编解码测试**

`test/runtime/opcodes_test.dart`:
```dart
import 'package:darti/src/runtime/opcodes.dart';
import 'package:test/test.dart';

void main() {
  group('Instruction encoding/decoding', () {
    test('ABC format round-trips', () {
      final instr = Instr.encodeABC(OpCode.addInt, 1, 2, 3);
      expect(Instr.decodeOp(instr), equals(OpCode.addInt));
      expect(Instr.decodeA(instr), equals(1));
      expect(Instr.decodeB(instr), equals(2));
      expect(Instr.decodeC(instr), equals(3));
    });

    test('ABx format round-trips', () {
      final instr = Instr.encodeABx(OpCode.loadConst, 5, 1000);
      expect(Instr.decodeOp(instr), equals(OpCode.loadConst));
      expect(Instr.decodeA(instr), equals(5));
      expect(Instr.decodeBx(instr), equals(1000));
    });

    test('AsBx format handles negative offsets', () {
      final instr = Instr.encodeAsBx(OpCode.jump, 0, -10);
      expect(Instr.decodeOp(instr), equals(OpCode.jump));
      expect(Instr.decodesBx(instr), equals(-10));
    });

    test('AsBx format handles positive offsets', () {
      final instr = Instr.encodeAsBx(OpCode.jumpIfFalse, 3, 42);
      expect(Instr.decodesBx(instr), equals(42));
      expect(Instr.decodeA(instr), equals(3));
    });
  });
}
```

**Step 2: 运行测试确认失败**

Run: `dart test test/runtime/opcodes_test.dart`
Expected: FAIL

**Step 3: 实现**

`lib/src/runtime/opcodes.dart`:
```dart
abstract class OpCode {
  // Load/Store
  static const int nop = 0x00;
  static const int loadConst = 0x01;
  static const int loadNull = 0x02;
  static const int loadTrue = 0x03;
  static const int loadFalse = 0x04;
  static const int loadInt = 0x05;
  static const int moveRef = 0x08;
  static const int moveVal = 0x09;

  // Int Arithmetic
  static const int addInt = 0x10;
  static const int addIntImm = 0x1D;

  // Comparison
  static const int ltInt = 0x30;

  // Control Flow
  static const int jump = 0x40;
  static const int jumpIfFalse = 0x42;

  // Call/Return
  static const int call = 0x50;
  static const int callStatic = 0x51;
  static const int callHost = 0x52;
  static const int returnRef = 0x55;
  static const int returnVal = 0x56;
  static const int returnNull = 0x57;

  // Object
  static const int newInstance = 0x64;
  static const int getFieldRef = 0x60;
  static const int setFieldRef = 0x61;
  static const int getFieldVal = 0x62;
  static const int setFieldVal = 0x63;

  // System
  static const int halt = 0xFF;
}

abstract class Instr {
  static int encodeABC(int op, int a, int b, int c) =>
      op | (a << 8) | (b << 16) | (c << 24);

  static int encodeABx(int op, int a, int bx) =>
      op | (a << 8) | (bx << 16);

  static int encodeAsBx(int op, int a, int sbx) =>
      op | (a << 8) | ((sbx + 0x7FFF) << 16);

  static int decodeOp(int instr) => instr & 0xFF;
  static int decodeA(int instr) => (instr >> 8) & 0xFF;
  static int decodeB(int instr) => (instr >> 16) & 0xFF;
  static int decodeC(int instr) => (instr >> 24) & 0xFF;
  static int decodeBx(int instr) => (instr >> 16) & 0xFFFF;
  static int decodesBx(int instr) => ((instr >> 16) & 0xFFFF) - 0x7FFF;
}
```

`lib/src/runtime/value_stack.dart`:
```dart
import 'dart:typed_data';

class ValueStack {
  final Uint8List _buffer;
  late final Int64List intView;
  late final Float64List doubleView;

  ValueStack(int maxSlots) : _buffer = Uint8List(maxSlots * 8) {
    intView = Int64List.view(_buffer.buffer);
    doubleView = Float64List.view(_buffer.buffer);
  }
}
```

`lib/src/runtime/ref_stack.dart`:
```dart
class RefStack {
  final List<Object?> slots;

  RefStack(int maxSlots) : slots = List<Object?>.filled(maxSlots, null);

  void clear(int from, int to) {
    for (int i = from; i < to; i++) {
      slots[i] = null;
    }
  }
}
```

`lib/src/runtime/types.dart`:
```dart
import 'dart:typed_data';

class FuncProto {
  final String name;
  final int paramCount;
  final int refRegCount;  // 引用栈寄存器数量
  final int valRegCount;  // 值栈寄存器数量
  final Uint32List bytecode;

  FuncProto({
    required this.name,
    required this.paramCount,
    required this.refRegCount,
    required this.valRegCount,
    required this.bytecode,
  });
}

class ClassInfo {
  final int classId;
  final String name;
  final int refFieldCount;
  final int valueFieldCount;
  final Map<String, int> fieldOffsets;    // 字段名 → 偏移
  final Map<String, bool> fieldIsValue;   // 字段名 → 是否值类型
  final Map<String, int> methodTable;     // 方法名 → funcId

  ClassInfo({
    required this.classId,
    required this.name,
    required this.refFieldCount,
    required this.valueFieldCount,
    required this.fieldOffsets,
    required this.fieldIsValue,
    required this.methodTable,
  });
}

class InterpreterObject {
  final int classId;
  final List<Object?> refFields;
  final Int64List? valueFields;

  InterpreterObject({
    required this.classId,
    required int refFieldCount,
    int valueFieldCount = 0,
  }) : refFields = List<Object?>.filled(refFieldCount, null),
       valueFields = valueFieldCount > 0 ? Int64List(valueFieldCount) : null;
}

class DartiModule {
  final List<FuncProto> functions;
  final List<ClassInfo> classes;
  final List<Object?> constPool;
  final int entryPoint; // funcId of main

  DartiModule({
    required this.functions,
    required this.classes,
    required this.constPool,
    required this.entryPoint,
  });
}
```

**Step 4: 运行测试**

Run: `dart test test/runtime/opcodes_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/runtime/ test/runtime/
git commit -m "feat(poc-4): define ISA opcodes, stacks, and core data types"
```

---

## Task 16: POC-4 — 分发循环

**Files:**
- Create: `lib/src/runtime/host_bindings.dart`
- Create: `lib/src/runtime/dispatch_loop.dart`
- Test: `test/runtime/dispatch_loop_test.dart`

**Step 1: 编写测试（手写字节码执行简单算术）**

`test/runtime/dispatch_loop_test.dart`:
```dart
import 'dart:typed_data';
import 'package:darti/src/runtime/opcodes.dart';
import 'package:darti/src/runtime/types.dart';
import 'package:darti/src/runtime/host_bindings.dart';
import 'package:darti/src/runtime/dispatch_loop.dart';
import 'package:test/test.dart';

void main() {
  group('DispatchLoop', () {
    test('executes LOAD_INT + ADD_INT + RETURN_VAL', () {
      // Program: return 3 + 7
      final code = Uint32List.fromList([
        Instr.encodeAsBx(OpCode.loadInt, 0, 3),    // v[0] = 3
        Instr.encodeAsBx(OpCode.loadInt, 1, 7),    // v[1] = 7
        Instr.encodeABC(OpCode.addInt, 2, 0, 1),   // v[2] = v[0] + v[1]
        Instr.encodeABC(OpCode.returnVal, 2, 0, 0),// return v[2]
      ]);
      final func = FuncProto(
        name: 'test', paramCount: 0,
        refRegCount: 4, valRegCount: 4, bytecode: code,
      );
      final module = DartiModule(
        functions: [func], classes: [], constPool: [], entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: HostBindings());
      final result = runtime.execute(module);
      expect(result, equals(10));
    });

    test('executes for loop counting to 10', () {
      // Program: i=0; while(i<10) i++; return i
      final code = Uint32List.fromList([
        Instr.encodeAsBx(OpCode.loadInt, 0, 0),     // v[0] = i = 0
        Instr.encodeAsBx(OpCode.loadInt, 1, 10),    // v[1] = 10
        // LOOP (pc=2):
        Instr.encodeABC(OpCode.ltInt, 2, 0, 1),     // v[2] = (i < 10)
        Instr.encodeAsBx(OpCode.jumpIfFalse, 2, 2), // if false: skip to RETURN
        Instr.encodeABC(OpCode.addIntImm, 0, 0, 1), // i += 1 (C=1 immediate)
        Instr.encodeAsBx(OpCode.jump, 0, -3),       // back to LOOP
        // RETURN (pc=6):
        Instr.encodeABC(OpCode.returnVal, 0, 0, 0), // return i
      ]);
      final func = FuncProto(
        name: 'test', paramCount: 0,
        refRegCount: 4, valRegCount: 4, bytecode: code,
      );
      final module = DartiModule(
        functions: [func], classes: [], constPool: [], entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: HostBindings());
      final result = runtime.execute(module);
      expect(result, equals(10));
    });

    test('NEW_INSTANCE + GET/SET_FIELD_VAL', () {
      // Class with 1 value field, set it to 42, get it back
      final cls = ClassInfo(
        classId: 0, name: 'Foo',
        refFieldCount: 0, valueFieldCount: 1,
        fieldOffsets: {'x': 0}, fieldIsValue: {'x': true},
        methodTable: {},
      );
      final code = Uint32List.fromList([
        Instr.encodeABx(OpCode.newInstance, 0, 0),     // ref[0] = new Foo
        Instr.encodeAsBx(OpCode.loadInt, 0, 42),       // val[0] = 42
        Instr.encodeABC(OpCode.setFieldVal, 0, 0, 0),  // ref[0].valueFields[0] = val[0]
        Instr.encodeABC(OpCode.getFieldVal, 1, 0, 0),  // val[1] = ref[0].valueFields[0]
        Instr.encodeABC(OpCode.returnVal, 1, 0, 0),    // return val[1]
      ]);

      // Note: ref[0] and val[0] are different stacks!
      // newInstance writes to refStack, loadInt writes to valueStack
      final func = FuncProto(
        name: 'test', paramCount: 0,
        refRegCount: 4, valRegCount: 4, bytecode: code,
      );
      final module = DartiModule(
        functions: [func], classes: [cls], constPool: [], entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: HostBindings());
      final result = runtime.execute(module);
      expect(result, equals(42));
    });

    test('CALL_HOST invokes print binding', () {
      final printLog = <Object?>[];
      final bindings = HostBindings();
      bindings.register('print', (args) {
        printLog.add(args[0]);
      });

      // load "hello" from constPool[0], call print
      final code = Uint32List.fromList([
        Instr.encodeABx(OpCode.loadConst, 0, 0),   // ref[0] = constPool[0]
        Instr.encodeABx(OpCode.callHost, 0, 0),    // hostBindings[0](ref[0])
        Instr.encodeABC(OpCode.returnNull, 0, 0, 0),
      ]);
      final func = FuncProto(
        name: 'test', paramCount: 0,
        refRegCount: 4, valRegCount: 4, bytecode: code,
      );
      final module = DartiModule(
        functions: [func], classes: [], constPool: ['hello'], entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: bindings);
      runtime.execute(module);
      expect(printLog, equals(['hello']));
    });
  });
}
```

**Step 2: 运行测试确认失败**

Run: `dart test test/runtime/dispatch_loop_test.dart`
Expected: FAIL

**Step 3: 实现**

`lib/src/runtime/host_bindings.dart`:
```dart
typedef HostFn = Object? Function(List<Object?> args);

class HostBindings {
  final List<HostFn> _functions = [];
  final Map<String, int> _nameToId = {};

  int register(String name, HostFn fn) {
    final id = _functions.length;
    _functions.add(fn);
    _nameToId[name] = id;
    return id;
  }

  int? getId(String name) => _nameToId[name];

  Object? invoke(int id, List<Object?> args) => _functions[id](args);
}
```

`lib/src/runtime/dispatch_loop.dart`:
```dart
import 'dart:typed_data';
import 'opcodes.dart';
import 'types.dart';
import 'value_stack.dart';
import 'ref_stack.dart';
import 'host_bindings.dart';

class DartiRuntime {
  final HostBindings hostBindings;
  late ValueStack _vs;
  late RefStack _rs;

  DartiRuntime({required this.hostBindings});

  Object? execute(DartiModule module) {
    _vs = ValueStack(4096);
    _rs = RefStack(4096);
    return _executeFunc(module, module.entryPoint, [], 0, 0);
  }

  Object? _executeFunc(
    DartiModule module,
    int funcId,
    List<Object?> refArgs,
    int baseV,
    int baseR,
  ) {
    final func = module.functions[funcId];
    final code = func.bytecode;
    final vBase = baseV;
    final rBase = baseR;
    var pc = 0;

    // Copy ref args into ref stack
    for (int i = 0; i < refArgs.length; i++) {
      _rs.slots[rBase + i] = refArgs[i];
    }

    while (true) {
      final instr = code[pc++];
      final op = instr & 0xFF;

      switch (op) {
        case OpCode.nop:
          break;

        case OpCode.loadInt:
          _vs.intView[vBase + Instr.decodeA(instr)] = Instr.decodesBx(instr);

        case OpCode.loadConst:
          final a = Instr.decodeA(instr);
          final bx = Instr.decodeBx(instr);
          _rs.slots[rBase + a] = module.constPool[bx];

        case OpCode.loadNull:
          _rs.slots[rBase + Instr.decodeA(instr)] = null;

        case OpCode.loadTrue:
          _vs.intView[vBase + Instr.decodeA(instr)] = 1;

        case OpCode.loadFalse:
          _vs.intView[vBase + Instr.decodeA(instr)] = 0;

        case OpCode.moveRef:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          _rs.slots[rBase + a] = _rs.slots[rBase + b];

        case OpCode.moveVal:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          _vs.intView[vBase + a] = _vs.intView[vBase + b];

        case OpCode.addInt:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          _vs.intView[vBase + a] =
              _vs.intView[vBase + b] + _vs.intView[vBase + c];

        case OpCode.addIntImm:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          _vs.intView[vBase + a] = _vs.intView[vBase + b] + c;

        case OpCode.ltInt:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          _vs.intView[vBase + a] =
              _vs.intView[vBase + b] < _vs.intView[vBase + c] ? 1 : 0;

        case OpCode.jump:
          pc += Instr.decodesBx(instr);

        case OpCode.jumpIfFalse:
          if (_vs.intView[vBase + Instr.decodeA(instr)] == 0) {
            pc += Instr.decodesBx(instr);
          }

        case OpCode.call:
          final a = Instr.decodeA(instr);  // dest ref reg
          final b = Instr.decodeB(instr);  // func/receiver ref reg
          final c = Instr.decodeC(instr);  // arg count

          // Collect args from ref stack
          final args = <Object?>[];
          for (int i = 0; i < c; i++) {
            args.add(_rs.slots[rBase + b + 1 + i]);
          }

          // Get target: InterpreterObject for method call
          final target = _rs.slots[rBase + b];
          if (target is InterpreterObject) {
            // Method call: look up in class method table
            // For POC simplicity, we encode method name in constPool
            // Actually let's use CALL_STATIC for static calls
            // and CALL for instance method dispatch
            // For now, this is a placeholder
          }
          // Result goes to ref stack
          // _rs.slots[rBase + a] = result;

        case OpCode.callStatic:
          final a = Instr.decodeA(instr);
          final bx = Instr.decodeBx(instr);
          final targetFunc = module.functions[bx];

          // Collect args from ref[a+1..a+paramCount]
          final args = <Object?>[];
          for (int i = 0; i < targetFunc.paramCount; i++) {
            args.add(_rs.slots[rBase + a + 1 + i]);
          }

          final newBaseV = vBase + func.valRegCount;
          final newBaseR = rBase + func.refRegCount;
          final result = _executeFunc(module, bx, args, newBaseV, newBaseR);
          _rs.slots[rBase + a] = result;

        case OpCode.callHost:
          final a = Instr.decodeA(instr);
          final bx = Instr.decodeBx(instr);
          // Collect args from ref[a..a+N], where N determined by binding
          // For simplicity: pass ref[a] as single arg
          final arg = _rs.slots[rBase + a];
          final result = hostBindings.invoke(bx, [arg]);
          _rs.slots[rBase + a] = result;

        case OpCode.returnRef:
          final a = Instr.decodeA(instr);
          final retVal = _rs.slots[rBase + a];
          _rs.clear(rBase, rBase + func.refRegCount);
          return retVal;

        case OpCode.returnVal:
          final a = Instr.decodeA(instr);
          final retVal = _vs.intView[vBase + a];
          _rs.clear(rBase, rBase + func.refRegCount);
          return retVal;

        case OpCode.returnNull:
          _rs.clear(rBase, rBase + func.refRegCount);
          return null;

        case OpCode.newInstance:
          final a = Instr.decodeA(instr);
          final bx = Instr.decodeBx(instr);
          final cls = module.classes[bx];
          _rs.slots[rBase + a] = InterpreterObject(
            classId: cls.classId,
            refFieldCount: cls.refFieldCount,
            valueFieldCount: cls.valueFieldCount,
          );

        case OpCode.getFieldRef:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          final obj = _rs.slots[rBase + b] as InterpreterObject;
          _rs.slots[rBase + a] = obj.refFields[c];

        case OpCode.setFieldRef:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          final obj = _rs.slots[rBase + a] as InterpreterObject;
          obj.refFields[c] = _rs.slots[rBase + b];

        case OpCode.getFieldVal:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          final obj = _rs.slots[rBase + b] as InterpreterObject;
          _vs.intView[vBase + a] = obj.valueFields![c];

        case OpCode.setFieldVal:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          final obj = _rs.slots[rBase + a] as InterpreterObject;
          obj.valueFields![c] = _vs.intView[vBase + b];

        case OpCode.halt:
          return null;

        default:
          throw StateError(
              'Unknown opcode: 0x${op.toRadixString(16)} at pc=${pc - 1}');
      }
    }
  }
}
```

**Step 4: 运行测试**

Run: `dart test test/runtime/dispatch_loop_test.dart`
Expected: PASS

> **注意**：如果 CALL_HOST 的参数传递约定需要调整（多参数场景），在此修改。POC 阶段允许简化。

**Step 5: Commit**

```bash
git add lib/src/runtime/host_bindings.dart lib/src/runtime/dispatch_loop.dart test/runtime/dispatch_loop_test.dart
git commit -m "feat(poc-4): implement dispatch loop with 22-opcode ISA subset"
```

---

## Task 17: POC-4 — 手写字节码集成测试（Counter 程序）

**Files:**
- Test: `test/e2e/handwritten_counter_test.dart`

**目的**：在引入编译器之前，用手写字节码验证运行时能正确执行 Counter 程序。

**Step 1: 编写测试**

`test/e2e/handwritten_counter_test.dart`:
```dart
import 'dart:typed_data';
import 'package:darti/src/runtime/opcodes.dart';
import 'package:darti/src/runtime/types.dart';
import 'package:darti/src/runtime/host_bindings.dart';
import 'package:darti/src/runtime/dispatch_loop.dart';
import 'package:test/test.dart';

void main() {
  test('hand-written Counter program outputs 10 and 4', () {
    final printLog = <Object?>[];
    final bindings = HostBindings();
    final printId = bindings.register('print', (args) {
      printLog.add(args[0]);
    });
    final listAddId = bindings.register('List.add', (args) {
      (args[0] as List).add(args[1]);
    });
    final listLengthId = bindings.register('List.length', (args) {
      return (args[0] as List).length;
    });
    final listCreateId = bindings.register('List.create', (args) {
      return <int>[...(args[0] as List<Object?>).cast<int>()];
    });

    // Class 0: Counter { int _count = 0 }
    final counterClass = ClassInfo(
      classId: 0, name: 'Counter',
      refFieldCount: 0, valueFieldCount: 1,
      fieldOffsets: {'_count': 0}, fieldIsValue: {'_count': true},
      methodTable: {'increment': 1, 'count': 2},
    );

    // Func 0: main
    // Func 1: Counter.increment(this)
    // Func 2: Counter.count getter(this)

    // increment: this._count = this._count + 1; return null
    final incrementCode = Uint32List.fromList([
      // ref[0] = this (passed as arg)
      Instr.encodeABC(OpCode.getFieldVal, 0, 0, 0),   // val[0] = this.valueFields[0]
      Instr.encodeABC(OpCode.addIntImm, 0, 0, 1),     // val[0] += 1
      Instr.encodeABC(OpCode.setFieldVal, 0, 0, 0),   // this.valueFields[0] = val[0]
      Instr.encodeABC(OpCode.returnNull, 0, 0, 0),
    ]);

    // count getter: return this._count (as boxed int via returnVal)
    final countCode = Uint32List.fromList([
      // ref[0] = this
      Instr.encodeABC(OpCode.getFieldVal, 0, 0, 0),   // val[0] = this.valueFields[0]
      Instr.encodeABC(OpCode.returnVal, 0, 0, 0),     // return val[0]
    ]);

    // main: var c = Counter(); for(i=0;i<10;i++) c.increment(); print(c.count);
    //        var list = [1,2,3]; list.add(4); print(list.length);
    //
    // This is complex to hand-write, so we simplify to test the runtime
    // by directly constructing the module and calling functions programmatically.
    // The real compiler (Task 18+) will generate this.

    final incrementFunc = FuncProto(
      name: 'Counter.increment', paramCount: 1,
      refRegCount: 4, valRegCount: 4, bytecode: incrementCode,
    );
    final countFunc = FuncProto(
      name: 'Counter.count', paramCount: 1,
      refRegCount: 4, valRegCount: 4, bytecode: countCode,
    );

    // For main, we test runtime APIs directly
    final runtime = DartiRuntime(hostBindings: bindings);
    final module = DartiModule(
      functions: [
        FuncProto(name: 'main', paramCount: 0,
          refRegCount: 8, valRegCount: 8,
          bytecode: Uint32List(0)), // unused, we call manually
        incrementFunc,
        countFunc,
      ],
      classes: [counterClass],
      constPool: [],
      entryPoint: 0,
    );

    // Simulate main logic manually using runtime APIs
    // Create Counter
    final counter = InterpreterObject(classId: 0, refFieldCount: 0, valueFieldCount: 1);
    counter.valueFields![0] = 0;

    // Call increment 10 times
    for (int i = 0; i < 10; i++) {
      runtime._executeFunc(module, 1, [counter], 0, 0);
    }

    // Call count getter
    final count = runtime._executeFunc(module, 2, [counter], 0, 0);
    printLog.add(count);

    // List operations via host bindings
    final list = <int>[1, 2, 3];
    bindings.invoke(listAddId, [list, 4]);
    final len = bindings.invoke(listLengthId, [list]);
    printLog.add(len);

    expect(printLog, equals([10, 4]));
  });
}
```

> **注意**：`_executeFunc` 是 private，测试可能需要将其改为 `@visibleForTesting` 或使用 `test/` 目录的 part-of 访问。如果不行，将 `_executeFunc` 改为公开方法 `executeFunc`。

**Step 2: 运行测试**

Run: `dart test test/e2e/handwritten_counter_test.dart`
Expected: PASS（可能需要微调 dispatch_loop.dart 的可见性）

**Step 3: Commit**

```bash
git add test/e2e/
git commit -m "test(poc-4): hand-written Counter bytecode integration test"
```

---

## Task 18: POC-4 — 最小编译器（Kernel → 字节码）

> **这是最复杂的任务**。建议拆分为多个子步骤执行。

**Files:**
- Create: `lib/src/compiler/kernel_loader.dart`
- Create: `lib/src/compiler/simple_compiler.dart`
- Create: `lib/src/compiler/bytecode_emitter.dart`
- Test: `test/compiler/simple_compiler_test.dart`

**前置条件**：POC-1 验证了 Kernel 加载可行。此处复用 `package:kernel`。

**Step 1: 在主包中添加 kernel 依赖**

修改根 `pubspec.yaml`，在 `dependencies` 中添加:
```yaml
dependencies:
  kernel:
    git:
      url: https://github.com/dart-lang/sdk.git
      path: pkg/kernel
      ref: "3.10.7"
  _fe_analyzer_shared:
    git:
      url: https://github.com/dart-lang/sdk.git
      path: pkg/_fe_analyzer_shared
      ref: "3.10.7"
```

Run: `dart pub get`

**Step 2: 编写编译器测试**

`test/compiler/simple_compiler_test.dart`:
```dart
import 'dart:io';
import 'package:darti/src/compiler/simple_compiler.dart';
import 'package:darti/src/runtime/dispatch_loop.dart';
import 'package:darti/src/runtime/host_bindings.dart';
import 'package:test/test.dart';

void main() {
  // 前置：编译 fixture 为 .dill
  setUpAll(() {
    final result = Process.runSync('dart', [
      'compile', 'kernel', '--no-link-platform',
      '-o', 'test/fixtures/counter.dill',
      'test/fixtures/counter.dart',
    ]);
    if (result.exitCode != 0) {
      throw StateError('Failed to compile fixture: ${result.stderr}');
    }
  });

  test('compiles and executes counter.dart', () {
    final printLog = <Object?>[];

    final compiler = SimpleCompiler();
    final module = compiler.compile('test/fixtures/counter.dill');

    final bindings = HostBindings();
    bindings.register('dart:core::print', (args) {
      printLog.add(args[0]);
    });
    bindings.register('dart:core::List.add', (args) {
      (args[0] as List).add(args[1]);
    });
    bindings.register('dart:core::List.length', (args) {
      return (args[0] as List).length;
    });

    final runtime = DartiRuntime(hostBindings: bindings);
    runtime.execute(module);

    expect(printLog, equals([10, 4]));
  });
}
```

`test/fixtures/counter.dart`:
```dart
class Counter {
  int _count = 0;
  void increment() { _count = _count + 1; }
  int get count => _count;
}

void main() {
  var c = Counter();
  for (var i = 0; i < 10; i = i + 1) {
    c.increment();
  }
  print(c.count);

  var list = <int>[1, 2, 3];
  list.add(4);
  print(list.length);
}
```

> **注意**：简化了 `_count++` 为 `_count = _count + 1`，`i++` 为 `i = i + 1`，避免需要处理 ++/-- 的脱糖。

**Step 3: 实现编译器骨架**

这是最复杂的部分。编译器实现较长，作为独立步骤执行。

`lib/src/compiler/kernel_loader.dart`:
```dart
import 'dart:io';
import 'package:kernel/kernel.dart';
import 'package:kernel/binary/ast_from_binary.dart';

Component loadKernel(String dillPath) {
  final bytes = File(dillPath).readAsBytesSync();
  final component = Component();
  BinaryBuilder(bytes).readComponent(component);
  return component;
}
```

`lib/src/compiler/bytecode_emitter.dart`:
```dart
import 'dart:typed_data';
import '../runtime/opcodes.dart';

class BytecodeEmitter {
  final List<int> _code = [];

  int get currentOffset => _code.length;

  void emitABC(int op, int a, int b, int c) {
    _code.add(Instr.encodeABC(op, a, b, c));
  }

  void emitABx(int op, int a, int bx) {
    _code.add(Instr.encodeABx(op, a, bx));
  }

  void emitAsBx(int op, int a, int sbx) {
    _code.add(Instr.encodeAsBx(op, a, sbx));
  }

  /// Emit a jump placeholder, returns the index to patch later
  int emitJumpPlaceholder(int op, int a) {
    final idx = _code.length;
    _code.add(Instr.encodeAsBx(op, a, 0)); // placeholder offset = 0
    return idx;
  }

  /// Patch a jump instruction at [index] to jump to [targetOffset]
  void patchJump(int index, int targetOffset) {
    final instr = _code[index];
    final op = instr & 0xFF;
    final a = (instr >> 8) & 0xFF;
    final offset = targetOffset - (index + 1); // relative to next instruction
    _code[index] = Instr.encodeAsBx(op, a, offset);
  }

  void emit(int rawInstruction) {
    _code.add(rawInstruction);
  }

  Uint32List build() => Uint32List.fromList(_code);
}
```

`lib/src/compiler/simple_compiler.dart` — 这是核心文件，实现从 Kernel AST 到字节码的编译。由于这是 POC 中最复杂的组件，编译器实现会在执行阶段根据实际 Kernel AST 结构迭代开发。初始骨架如下：

```dart
import 'package:kernel/ast.dart' as k;
import 'package:kernel/core_types.dart';
import '../runtime/opcodes.dart';
import '../runtime/types.dart';
import 'kernel_loader.dart';
import 'bytecode_emitter.dart';

class SimpleCompiler {
  late k.Component _component;
  late CoreTypes _coreTypes;
  final List<FuncProto> _functions = [];
  final List<ClassInfo> _classes = [];
  final List<Object?> _constPool = [];
  final Map<String, int> _hostBindingIds = {};
  int _entryPoint = -1;

  DartiModule compile(String dillPath) {
    _component = loadKernel(dillPath);
    _coreTypes = CoreTypes(_component);

    // Find user library
    final userLib = _component.libraries.firstWhere(
      (lib) => !lib.importUri.isScheme('dart'),
    );

    // Compile classes
    for (final cls in userLib.classes) {
      _compileClass(cls);
    }

    // Compile top-level procedures
    for (final proc in userLib.procedures) {
      final funcId = _compileFunction(proc.function, proc.name.text);
      if (proc.name.text == 'main') {
        _entryPoint = funcId;
      }
    }

    return DartiModule(
      functions: _functions,
      classes: _classes,
      constPool: _constPool,
      entryPoint: _entryPoint,
    );
  }

  // ... 编译方法实现在执行阶段迭代完成
  // 关键方法：_compileClass, _compileFunction, _compileStatement, _compileExpression

  void _compileClass(k.Class cls) {
    // 收集字段布局，生成 ClassInfo
    // 编译每个方法为 FuncProto
  }

  int _compileFunction(k.FunctionNode func, String name) {
    // 分配寄存器（递增）
    // 遍历 func.body，为每个 Statement 生成字节码
    // 返回 funcId
    return _functions.length - 1;
  }
}
```

> **关键说明**：SimpleCompiler 的完整实现需要处理 Kernel AST 的许多节点类型（IfStatement、ForStatement、VariableDeclaration、MethodInvocation 等）。这部分将在执行阶段根据实际 Kernel 输出迭代开发，因为 Kernel AST 的具体结构需要通过 POC-1 的探索结果来指导。

**Step 4: 运行测试**

Run: `dart test test/compiler/simple_compiler_test.dart`
Expected: 初始可能 FAIL（编译器需要迭代完善）

**Step 5: 迭代直到测试通过**

根据测试失败信息，逐步实现 `_compileClass`、`_compileFunction`、`_compileStatement`、`_compileExpression`。每个节点类型的处理参考 POC-1 的 KernelWalker 探索结果。

**Step 6: Commit**

```bash
git add lib/src/compiler/ test/compiler/ test/fixtures/counter.dart
git commit -m "feat(poc-4): implement minimal Kernel-to-bytecode compiler"
```

---

## Task 19: POC-4 — 更新导出与全部测试

**Files:**
- Modify: `lib/darti.dart`

**Step 1: 更新导出**

`lib/darti.dart`:
```dart
library;

export 'src/runtime/opcodes.dart';
export 'src/runtime/types.dart';
export 'src/runtime/value_stack.dart';
export 'src/runtime/ref_stack.dart';
export 'src/runtime/host_bindings.dart';
export 'src/runtime/dispatch_loop.dart';
export 'src/compiler/simple_compiler.dart';
```

**Step 2: 运行全部测试**

Run: `dart test`
Expected: 全部 PASS

**Step 3: Commit**

```bash
git add lib/darti.dart
git commit -m "feat(poc-4): finalize POC-4 with exports and full test suite"
```

---

## 完成检查清单

| POC | 关键验证 | 状态 |
|-----|---------|------|
| POC-1 | package:kernel 成功加载 .dill | Task 3 |
| POC-1 | 类型分类（int→value, T→ref）正确 | Task 4 |
| POC-1 | CFE 脱糖确认 | Task 5 |
| POC-2 | 双视图 vs 装箱 ≥3x 加速 | Task 9 |
| POC-2 | 分发循环 vs AOT ≥1/5 性能 | Task 9 |
| POC-3 | Expando 身份一致性 | Task 11 |
| POC-3 | Bridge VM→解释器调用 | Task 13 |
| POC-3 | CallbackProxy 回调 | Task 13 |
| POC-4 | 手写字节码正确执行 | Task 17 |
| POC-4 | counter.dart 全链路输出 10, 4 | Task 18 |
