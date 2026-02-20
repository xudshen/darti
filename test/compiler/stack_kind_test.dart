import 'package:dartic/src/compiler/scope.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('StackKind classification', () {
    test('int parameter -> StackKind.intVal (value stack)', () async {
      final module = await compileDart('''
int identity(int x) => x;
void main() {}
''');
      final f = findFunc(module, 'identity');
      // int param goes to value stack: at least 1 value reg for param.
      expect(f.valueRegCount, greaterThanOrEqualTo(1));
      expect(f.paramCount, 1);
    });

    test('double parameter -> StackKind.doubleVal (value stack)', () async {
      final module = await compileDart('''
double identity(double x) => x;
void main() {}
''');
      final f = findFunc(module, 'identity');
      // double param goes to value stack: at least 1 value reg for param.
      expect(f.valueRegCount, greaterThanOrEqualTo(1));
      expect(f.paramCount, 1);
      // 3 reserved ref regs (ITA+FTA+this) but no ref params.
      expect(f.refRegCount, 3);
    });

    test('bool parameter -> StackKind.boolVal (value stack)', () async {
      final module = await compileDart('''
bool identity(bool x) => x;
void main() {}
''');
      final f = findFunc(module, 'identity');
      // bool param goes to value stack (boolVal, encoded as 0/1 int).
      expect(f.valueRegCount, greaterThanOrEqualTo(1));
      expect(f.paramCount, 1);
      // 3 reserved ref regs (ITA+FTA+this) but no ref params.
      expect(f.refRegCount, 3);
    });

    test('String parameter -> StackKind.ref (ref stack)', () async {
      final module = await compileDart('''
String identity(String s) => s;
void main() {}
''');
      final f = findFunc(module, 'identity');
      // String param goes to ref stack (at least 1).
      expect(f.refRegCount, greaterThanOrEqualTo(1));
      expect(f.paramCount, 1);
      // Should NOT add to value stack.
      expect(f.valueRegCount, 0);
    });
  });

  group('StackKind.isValue', () {
    test('intVal.isValue returns true', () {
      expect(StackKind.intVal.isValue, isTrue);
    });

    test('doubleVal.isValue returns true', () {
      expect(StackKind.doubleVal.isValue, isTrue);
    });

    test('boolVal.isValue returns true', () {
      expect(StackKind.boolVal.isValue, isTrue);
    });

    test('ref.isValue returns false', () {
      expect(StackKind.ref.isValue, isFalse);
    });
  });

  group('StackKind enum', () {
    test('has exactly four values: ref, boolVal, intVal, doubleVal', () {
      expect(StackKind.values.length, 4);
      expect(StackKind.values, contains(StackKind.ref));
      expect(StackKind.values, contains(StackKind.boolVal));
      expect(StackKind.values, contains(StackKind.intVal));
      expect(StackKind.values, contains(StackKind.doubleVal));
    });
  });
}
