import 'dart:io';

import 'package:dartic/src/bridge/async_bindings.dart';
import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:dartic/src/compiler/compiler.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:kernel/ast.dart' as ir;
import 'package:kernel/binary/ast_from_binary.dart';
import 'package:test/test.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════
  // static_type_helper.dart
  // ══════════════════════════════════════════════════════════════════

  group('static_type_helper integration', () {
    final helperPath =
        '${Directory.current.path}/vendor/co19/Utils/static_type_helper.dart';

    test('static_type_helper.dart exists', () {
      expect(File(helperPath).existsSync(), isTrue);
    });

    test('static_type_helper compiles and basic usage works', () async {
      // Write a test file that imports static_type_helper.dart using absolute
      // path (since we can't use relative paths easily from a temp dir).
      final tempDir =
          await Directory.systemTemp.createTemp('co19_sth_test_');
      try {
        final testFile = File('${tempDir.path}/main.dart');
        await testFile.writeAsString('''
import '$helperPath';

int main() {
  // Basic extension method usage
  42.expectStaticType<Exactly<int>>();
  'hello'.expectStaticType<Exactly<String>>();
  true.expectStaticType<Exactly<bool>>();
  return 0;
}
''');

        final dillPath = '${tempDir.path}/test.dill';
        final compileResult = await Process.run(
          'fvm',
          ['dart', 'compile', 'kernel', testFile.path, '-o', dillPath],
        );
        expect(compileResult.exitCode, 0,
            reason: 'Compilation failed: ${compileResult.stderr}');

        final bytes = File(dillPath).readAsBytesSync();
        final component = ir.Component();
        BinaryBuilder(bytes).readComponent(component);
        final module = DarticCompiler(component).compile();

        final registry = HostFunctionRegistry();
        CoreBindings.registerAll(registry);
        AsyncBindings.registerAll(registry);
        final interp = DarticInterpreter(hostFunctionRegistry: registry);
        interp.execute(module);
        expect(interp.entryResult, 0);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('typeOf<T>() returns correct Type', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('co19_sth_test_');
      try {
        final testFile = File('${tempDir.path}/main.dart');
        await testFile.writeAsString('''
import '$helperPath';

bool main() {
  return typeOf<int>() == int;
}
''');

        final dillPath = '${tempDir.path}/test.dill';
        final compileResult = await Process.run(
          'fvm',
          ['dart', 'compile', 'kernel', testFile.path, '-o', dillPath],
        );
        expect(compileResult.exitCode, 0,
            reason: 'Compilation failed: ${compileResult.stderr}');

        final bytes = File(dillPath).readAsBytesSync();
        final component = ir.Component();
        BinaryBuilder(bytes).readComponent(component);
        final module = DarticCompiler(component).compile();

        final registry = HostFunctionRegistry();
        CoreBindings.registerAll(registry);
        final interp = DarticInterpreter(hostFunctionRegistry: registry);
        interp.execute(module);
        expect(interp.entryResult, true);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Full vendor expect.dart (including async_utils)
  // ══════════════════════════════════════════════════════════════════

  group('vendor expect.dart integration', () {
    final expectPath =
        '${Directory.current.path}/vendor/co19/Utils/expect.dart';

    test('vendor expect.dart compiles through dartic', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('co19_expect_test_');
      try {
        final testFile = File('${tempDir.path}/main.dart');
        await testFile.writeAsString('''
import '$expectPath';

int main() {
  Expect.equals(1, 1);
  Expect.isTrue(true);
  Expect.isFalse(false);
  return 0;
}
''');

        final dillPath = '${tempDir.path}/test.dill';
        final compileResult = await Process.run(
          'fvm',
          ['dart', 'compile', 'kernel', testFile.path, '-o', dillPath],
        );
        expect(compileResult.exitCode, 0,
            reason: 'Compilation failed: ${compileResult.stderr}');

        final bytes = File(dillPath).readAsBytesSync();
        final component = ir.Component();
        BinaryBuilder(bytes).readComponent(component);
        final module = DarticCompiler(component).compile();

        final printLog = <String>[];
        final registry = HostFunctionRegistry();
        CoreBindings.registerAll(registry, printFn: (v) => printLog.add('$v'));
        AsyncBindings.registerAll(registry);
        final interp = DarticInterpreter(hostFunctionRegistry: registry);
        interp.execute(module);
        expect(interp.entryResult, 0);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Expect.throws works with full vendor expect.dart', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('co19_expect_test_');
      try {
        final testFile = File('${tempDir.path}/main.dart');
        await testFile.writeAsString('''
import '$expectPath';

int main() {
  Expect.throws(() { throw 'error'; });
  return 0;
}
''');

        final dillPath = '${tempDir.path}/test.dill';
        final compileResult = await Process.run(
          'fvm',
          ['dart', 'compile', 'kernel', testFile.path, '-o', dillPath],
        );
        expect(compileResult.exitCode, 0,
            reason: 'Compilation failed: ${compileResult.stderr}');

        final bytes = File(dillPath).readAsBytesSync();
        final component = ir.Component();
        BinaryBuilder(bytes).readComponent(component);
        final module = DarticCompiler(component).compile();

        final registry = HostFunctionRegistry();
        CoreBindings.registerAll(registry);
        AsyncBindings.registerAll(registry);
        final interp = DarticInterpreter(hostFunctionRegistry: registry);
        interp.execute(module);
        expect(interp.entryResult, 0);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Expect.equals fails correctly', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('co19_expect_test_');
      try {
        final testFile = File('${tempDir.path}/main.dart');
        await testFile.writeAsString('''
import '$expectPath';

int main() {
  Expect.equals(1, 2);
  return 0;
}
''');

        final dillPath = '${tempDir.path}/test.dill';
        final compileResult = await Process.run(
          'fvm',
          ['dart', 'compile', 'kernel', testFile.path, '-o', dillPath],
        );
        expect(compileResult.exitCode, 0);

        final bytes = File(dillPath).readAsBytesSync();
        final component = ir.Component();
        BinaryBuilder(bytes).readComponent(component);
        final module = DarticCompiler(component).compile();

        final registry = HostFunctionRegistry();
        CoreBindings.registerAll(registry);
        AsyncBindings.registerAll(registry);
        final interp = DarticInterpreter(hostFunctionRegistry: registry);

        expect(() => interp.execute(module), throwsA(anything));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // asyncStart / asyncEnd (from async_utils.dart, part of expect.dart)
  // ══════════════════════════════════════════════════════════════════

  group('async_utils integration', () {
    final expectPath =
        '${Directory.current.path}/vendor/co19/Utils/expect.dart';

    test('asyncStart/asyncEnd prints markers', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('co19_async_utils_test_');
      try {
        final testFile = File('${tempDir.path}/main.dart');
        await testFile.writeAsString('''
import 'dart:async';
import '$expectPath';

Future<void> main() async {
  asyncStart();
  await Future.value(42);
  asyncEnd();
}
''');

        final dillPath = '${tempDir.path}/test.dill';
        final compileResult = await Process.run(
          'fvm',
          ['dart', 'compile', 'kernel', testFile.path, '-o', dillPath],
        );
        expect(compileResult.exitCode, 0,
            reason: 'Compilation failed: ${compileResult.stderr}');

        final bytes = File(dillPath).readAsBytesSync();
        final component = ir.Component();
        BinaryBuilder(bytes).readComponent(component);
        final module = DarticCompiler(component).compile();

        final printLog = <String>[];
        final registry = HostFunctionRegistry();
        CoreBindings.registerAll(registry, printFn: (v) => printLog.add('$v'));
        AsyncBindings.registerAll(registry);
        final interp = DarticInterpreter(hostFunctionRegistry: registry);
        interp.execute(module);

        final result = interp.entryResult;
        if (result is Future) {
          await result;
        }

        expect(printLog, contains('unittest-suite-wait-for-done'));
        expect(printLog, contains('unittest-suite-success'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('nested asyncStart(N)/asyncEnd', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('co19_async_utils_test_');
      try {
        final testFile = File('${tempDir.path}/main.dart');
        await testFile.writeAsString('''
import 'dart:async';
import '$expectPath';

Future<void> main() async {
  asyncStart(2);
  await Future.value(1);
  asyncEnd();
  await Future.value(2);
  asyncEnd();
}
''');

        final dillPath = '${tempDir.path}/test.dill';
        final compileResult = await Process.run(
          'fvm',
          ['dart', 'compile', 'kernel', testFile.path, '-o', dillPath],
        );
        expect(compileResult.exitCode, 0,
            reason: 'Compilation failed: ${compileResult.stderr}');

        final bytes = File(dillPath).readAsBytesSync();
        final component = ir.Component();
        BinaryBuilder(bytes).readComponent(component);
        final module = DarticCompiler(component).compile();

        final printLog = <String>[];
        final registry = HostFunctionRegistry();
        CoreBindings.registerAll(registry, printFn: (v) => printLog.add('$v'));
        AsyncBindings.registerAll(registry);
        final interp = DarticInterpreter(hostFunctionRegistry: registry);
        interp.execute(module);

        final result = interp.entryResult;
        if (result is Future) {
          await result;
        }

        // Should print wait-for-done once, and success once (when count reaches 0)
        expect(printLog.where((s) => s == 'unittest-suite-wait-for-done').length, 1);
        expect(printLog.where((s) => s == 'unittest-suite-success').length, 1);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
