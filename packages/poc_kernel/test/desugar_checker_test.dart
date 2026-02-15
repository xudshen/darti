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
