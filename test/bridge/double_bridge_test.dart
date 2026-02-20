import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('double bridge', () {
    test('3.14.toString()', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 3.14.toString();
}
''');
      expect(result, '3.14');
    });

    test('3.14.ceil()', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 3.14.ceil();
}
''');
      expect(result, 4);
    });

    test('3.14.floor()', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 3.14.floor();
}
''');
      expect(result, 3);
    });

    test('3.14.round()', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 3.14.round();
}
''');
      expect(result, 3);
    });

    test('3.14.truncate()', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 3.14.truncate();
}
''');
      expect(result, 3);
    });

    test('3.14.toInt()', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 3.14.toInt();
}
''');
      expect(result, 3);
    });

    test('3.14.isFinite', () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return 3.14.isFinite;
}
''');
      expect(result, true);
    });

    test('3.14.abs()', () async {
      final result = await compileAndRunWithHost('''
double main() {
  return 3.14.abs();
}
''');
      expect(result, 3.14);
    });

    test('(-3.14).sign', () async {
      final result = await compileAndRunWithHost('''
double main() {
  double x = -3.14;
  return x.sign;
}
''');
      expect(result, -1.0);
    });

    test('3.14.toStringAsFixed(1)', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 3.14.toStringAsFixed(1);
}
''');
      expect(result, '3.1');
    });

    test('3.14.ceilToDouble()', () async {
      final result = await compileAndRunWithHost('''
double main() {
  return 3.14.ceilToDouble();
}
''');
      expect(result, 4.0);
    });

    test('3.14.floorToDouble()', () async {
      final result = await compileAndRunWithHost('''
double main() {
  return 3.14.floorToDouble();
}
''');
      expect(result, 3.0);
    });

    test('double.parse("3.14")', () async {
      final result = await compileAndRunWithHost('''
double main() {
  return double.parse('3.14');
}
''');
      expect(result, 3.14);
    });

    test('double.tryParse("abc")', () async {
      final result = await compileAndRunWithHost('''
int main() {
  double? v = double.tryParse('abc');
  if (v == null) return 1;
  return 0;
}
''');
      expect(result, 1);
    });
  });
}
