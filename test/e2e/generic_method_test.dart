import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('generic top-level function', () {
    test('identity<int>(42) returns 42', () async {
      final result = await compileAndRun('''
T identity<T>(T x) => x;
int main() {
  return identity<int>(42);
}
''');
      expect(result, 42);
    });

    test('identity<String> returns string', () async {
      final result = await compileAndRun('''
T identity<T>(T x) => x;
String main() {
  return identity<String>('hello');
}
''');
      expect(result, 'hello');
    });

    test('is T check in generic function (true case)', () async {
      final result = await compileAndRun('''
bool checkType<T>(Object o) => o is T;
int main() {
  if (checkType<int>(42)) return 1;
  return 0;
}
''');
      expect(result, 1);
    });

    test('is T check in generic function (false case)', () async {
      final result = await compileAndRun('''
bool checkType<T>(Object o) => o is T;
int main() {
  if (checkType<int>('hello')) return 1;
  return 0;
}
''');
      expect(result, 0);
    });

    test('multiple type parameters', () async {
      final result = await compileAndRun('''
A pickFirst<A, B>(A a, B b) => a;
int main() {
  return pickFirst<int, String>(99, 'ignored');
}
''');
      expect(result, 99);
    });
  });

  group('generic instance method', () {
    test('instance method with FTA: cast<T>', () async {
      final result = await compileAndRun('''
class Caster {
  Object val;
  Caster(this.val);
  T cast<T>() => val as T;
}
int main() {
  Caster c = Caster(42);
  return c.cast<int>();
}
''');
      expect(result, 42);
    });

    test('is T in instance generic method', () async {
      final result = await compileAndRun('''
class Checker {
  bool check<T>(Object o) => o is T;
}
int main() {
  Checker c = Checker();
  int result = 0;
  if (c.check<int>(42)) result = result + 1;
  if (c.check<int>('hello')) result = result + 10;
  return result;
}
''');
      // check<int>(42) → true (+1), check<int>('hello') → false (+0) = 1
      expect(result, 1);
    });
  });

  group('generic class with generic method (ITA + FTA)', () {
    test('Box<T>.check<R>: ITA and FTA coexist', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
  bool check<R>(Object o) => o is R;
}
int main() {
  Box<int> b = Box<int>(42);
  int result = 0;
  if (b.check<String>('hi')) result = result + 1;
  if (b.check<String>(42)) result = result + 10;
  return result;
}
''');
      // check<String>('hi') → true (+1), check<String>(42) → false (+0) = 1
      expect(result, 1);
    });

    test('Box<T>.isValueType: uses ITA T from class, not FTA', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
  bool isValueType(Object o) => o is T;
}
int main() {
  Box<int> b = Box<int>(42);
  if (b.isValueType(10)) return 1;
  return 0;
}
''');
      expect(result, 1);
    });
  });

  group('generic static function type inference', () {
    test('generic static function return used in arithmetic', () async {
      final result = await compileAndRun('''
T identity<T>(T x) => x;
int main() {
  return identity<int>(40) + 2;
}
''');
      expect(result, 42);
    });

    test('generic static function with multiple type params', () async {
      final result = await compileAndRun('''
A first<A, B>(A a, B b) => a;
int main() {
  return first<int, String>(42, 'hello');
}
''');
      expect(result, 42);
    });
  });

  group('chained generic function calls', () {
    test('nested generic function calls', () async {
      final result = await compileAndRun('''
T identity<T>(T x) => x;
int main() {
  return identity<int>(identity<int>(7));
}
''');
      expect(result, 7);
    });
  });
}
