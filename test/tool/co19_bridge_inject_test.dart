@Tags(['integration'])
library;

import 'dart:io';

import 'package:test/test.dart';

// Import the tool source directly (not a package import — tool/ is outside lib/).
// ignore: avoid_relative_lib_imports
import '../../tool/co19_runner.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Bridge injection integration tests
  // ---------------------------------------------------------------------------

  group('co19 bridge injection', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('co19_bridge_inject_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('runTest passes for a simple print program', () async {
      // Write a minimal Dart file that calls print — this exercises CALL_HOST.
      final dartFile = File('${tempDir.path}/print_test_t01.dart');
      dartFile.writeAsStringSync('void main() { print(1 + 2); }\n');

      final entry = TestEntry(
        path: dartFile.path,
        category: 'Bridge',
        subcategory: '',
      );

      final outcome = await runTest(entry);

      expect(outcome.result, equals(TestResult.pass),
          reason: 'Expected pass but got ${outcome.result}: ${outcome.message}');
    });

    test('runTest passes with explicit import dart:core', () async {
      // Explicit `import 'dart:core';` should not break compilation or execution.
      final dartFile = File('${tempDir.path}/explicit_core_t01.dart');
      dartFile.writeAsStringSync(
        "import 'dart:core';\n"
        '\n'
        'void main() {\n'
        '  print(42);\n'
        '}\n',
      );

      final entry = TestEntry(
        path: dartFile.path,
        category: 'Bridge',
        subcategory: '',
      );

      final outcome = await runTest(entry);

      expect(outcome.result, equals(TestResult.pass),
          reason: 'Expected pass but got ${outcome.result}: ${outcome.message}');
    });

    test('runTest passes for program using int arithmetic and print', () async {
      // Exercises both arithmetic (compiled as bytecode) and print (CALL_HOST).
      final dartFile = File('${tempDir.path}/arith_print_t01.dart');
      dartFile.writeAsStringSync(
        'void main() {\n'
        '  int a = 10;\n'
        '  int b = 20;\n'
        '  print(a + b);\n'
        '}\n',
      );

      final entry = TestEntry(
        path: dartFile.path,
        category: 'Bridge',
        subcategory: '',
      );

      final outcome = await runTest(entry);

      expect(outcome.result, equals(TestResult.pass),
          reason: 'Expected pass but got ${outcome.result}: ${outcome.message}');
    });
  });
}
