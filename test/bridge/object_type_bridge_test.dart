import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('Object bridge', () {
    test('Object().toString()', () async {
      final (_, out) = await compileAndCapturePrint('''
void main() {
  print(Object().toString());
}
''');
      expect(out.single, startsWith('Instance of'));
    });

    test('Object().hashCode returns int', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return Object().hashCode;
}
''');
      expect(result, isA<int>());
    });

    test('null.toString() returns "null"', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return null.toString();
}
''');
      expect(result, 'null');
    });
  });

  group('Type bridge', () {
    test('42.runtimeType.toString() returns "int"', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 42.runtimeType.toString();
}
''');
      expect(result, 'int');
    });

    test('"hello".runtimeType.toString() returns "String"', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 'hello'.runtimeType.toString();
}
''');
      expect(result, 'String');
    });
  });

  group('identical', () {
    test('identical(null, null) returns true', () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return identical(null, null);
}
''');
      expect(result, true);
    });

    test('identical(42, 42) returns true', () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return identical(42, 42);
}
''');
      expect(result, true);
    });
  });
}
