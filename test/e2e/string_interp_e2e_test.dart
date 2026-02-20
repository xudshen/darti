import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('String interpolation E2E', () {
    test('simple string concat: hello world', () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  return 'hello ${'world'}';
}
""");
      expect(result, 'hello world');
    });

    test('int variable interpolation', () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  int x = 42;
  return 'value is $x';
}
""");
      expect(result, 'value is 42');
    });

    test('expression interpolation: 1 + 2', () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  return '${1 + 2} items';
}
""");
      expect(result, '3 items');
    });

    test('double variable interpolation', () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  double d = 3.14;
  return 'pi is $d';
}
""");
      expect(result, 'pi is 3.14');
    });

    test('multi-segment interpolation', () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  int a = 1;
  int b = 2;
  return '$a + $b = ${a + b}';
}
""");
      expect(result, '1 + 2 = 3');
    });

    test('null interpolation', () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  return '${null}';
}
""");
      expect(result, 'null');
    });

    test('adjacent string literals', () async {
      // Dart concatenates adjacent string literals at parse time;
      // Kernel typically represents this as a single StringLiteral.
      final result = await compileAndRunWithHost(r"""
String main() {
  return 'abc' 'def';
}
""");
      expect(result, 'abcdef');
    });

    test('bool interpolation', () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  bool b = true;
  return 'flag=$b';
}
""");
      expect(result, 'flag=true');
    });

    test('nested string interpolation', () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  int x = 5;
  return 'result=${x > 3 ? 'yes' : 'no'}';
}
""");
      expect(result, 'result=yes');
    });

    test('empty interpolation segments', () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  return '${''}hello';
}
""");
      expect(result, 'hello');
    });

    test('string interpolation with toString() call', () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  int x = 99;
  return 'val=${x.toString()}';
}
""");
      expect(result, 'val=99');
    });
  });
}
