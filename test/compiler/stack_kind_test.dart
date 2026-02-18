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
      // Should NOT add to ref stack beyond the 3 reserved (ITA/FTA/this).
      expect(f.refRegCount, 3);
    });

    test('bool parameter -> StackKind.intVal (value stack)', () async {
      final module = await compileDart('''
bool identity(bool x) => x;
void main() {}
''');
      final f = findFunc(module, 'identity');
      // bool param goes to value stack (encoded as 0/1 int).
      expect(f.valueRegCount, greaterThanOrEqualTo(1));
      expect(f.paramCount, 1);
      // Should NOT add to ref stack beyond the 3 reserved.
      expect(f.refRegCount, 3);
    });

    test('String parameter -> StackKind.ref (ref stack)', () async {
      final module = await compileDart('''
String identity(String s) => s;
void main() {}
''');
      final f = findFunc(module, 'identity');
      // String param goes to ref stack: ITA + FTA + this + s = at least 4.
      expect(f.refRegCount, greaterThanOrEqualTo(4));
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

    test('ref.isValue returns false', () {
      expect(StackKind.ref.isValue, isFalse);
    });
  });

  group('StackKind enum', () {
    test('has exactly three values: intVal, doubleVal, ref', () {
      expect(StackKind.values.length, 3);
      expect(StackKind.values, contains(StackKind.intVal));
      expect(StackKind.values, contains(StackKind.doubleVal));
      expect(StackKind.values, contains(StackKind.ref));
    });
  });
}
