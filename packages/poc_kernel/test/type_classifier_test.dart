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
      final classifier = TypeClassifier();

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
      final classifier = TypeClassifier();

      final lib = component.libraries.firstWhere(
          (l) => !l.importUri.isScheme('dart'));
      final boxClass = lib.classes.firstWhere((c) => c.name == 'Box');
      // Box.value field is T → ref
      final valueField = boxClass.fields.firstWhere((f) => f.name.text == 'value');
      expect(classifier.classify(valueField.type), equals(StackKind.ref));
    });

    test('generates summary statistics', () {
      final component = loadDill('simple');
      final classifier = TypeClassifier();
      final summary = classifier.summarize(component);

      expect(summary.valueCount, greaterThan(0));
      expect(summary.totalCount, greaterThan(summary.valueCount));
    });
  });
}
