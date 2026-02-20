import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('Bridge end-to-end', () {
    test('print(42) calls print without error', () async {
      final (_, output) = await compileAndCapturePrint('''
void main() {
  print(42);
}
''');
      expect(output, ['42']);
    });

    test('print("hello world") passes string argument', () async {
      final (_, output) = await compileAndCapturePrint('''
void main() {
  print('hello world');
}
''');
      expect(output, ['hello world']);
    });

    test('42.toString() returns "42"', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 42.toString();
}
''');
      expect(result, equals('42'));
    });

    test("'hello'.length returns 5", () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 'hello'.length;
}
''');
      expect(result, equals(5));
    });

    test('42.toString().length returns 2 (chain)', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 42.toString().length;
}
''');
      expect(result, equals(2));
    });

    test('int.toString() on computed value', () async {
      final result = await compileAndRunWithHost('''
String main() {
  int x = 10 + 32;
  return x.toString();
}
''');
      expect(result, equals('42'));
    });

    test('print with multiple statements', () async {
      final (_, output) = await compileAndCapturePrint('''
void main() {
  print(1);
  print('two');
  print(3);
}
''');
      expect(output, ['1', 'two', '3']);
    });
  });
}
