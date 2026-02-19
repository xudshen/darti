import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('generic class instantiation', () {
    test('Box<int> stores and retrieves int value', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
int main() {
  Box<int> b = Box<int>(42);
  return b.value;
}
''');
      expect(result, 42);
    });

    test('Box<String> stores and retrieves String value', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
String main() {
  Box<String> b = Box<String>('hello');
  return b.value;
}
''');
      expect(result, 'hello');
    });

    test('multiple type parameters: Pair<A, B>', () async {
      // Note: Operators on type-parameter-typed fields (e.g., p.first + p.second)
      // require generic type specialization (Phase 2). This test validates
      // multi-type-param storage/retrieval without operator dispatch.
      final result = await compileAndRun('''
class Pair<A, B> {
  A first;
  B second;
  Pair(this.first, this.second);
}
String main() {
  Pair<String, String> p = Pair<String, String>('hello', 'world');
  return p.first;
}
''');
      expect(result, 'hello');
    });

    test('same class with different type args coexist', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
int main() {
  Box<int> bi = Box<int>(1);
  Box<String> bs = Box<String>('hi');
  return bi.value;
}
''');
      expect(result, 1);
    });

    test('nested generic: Box<Box<int>>', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
int main() {
  Box<int> inner = Box<int>(99);
  Box<Box<int>> outer = Box<Box<int>>(inner);
  return outer.value.value;
}
''');
      expect(result, 99);
    });
  });

  group('generic class with methods', () {
    test('instance method using type parameter (is T)', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
  bool isType(Object o) => o is T;
}
int main() {
  Box<int> b = Box<int>(42);
  if (b.isType(10)) return 1;
  return 0;
}
''');
      expect(result, 1);
    });

    test('is T returns false for wrong type', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
  bool isType(Object o) => o is T;
}
int main() {
  Box<int> b = Box<int>(42);
  if (b.isType('hello')) return 1;
  return 0;
}
''');
      expect(result, 0);
    });

    test('instance method returns value of type T', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
  T get() => value;
}
int main() {
  Box<int> b = Box<int>(7);
  return b.get();
}
''');
      expect(result, 7);
    });
  });

  group('generic field type inference', () {
    test('generic field arithmetic: Pair<int,int>.first + .second', () async {
      final result = await compileAndRun('''
class Pair<A, B> {
  A first;
  B second;
  Pair(this.first, this.second);
}
int main() {
  Pair<int, int> p = Pair<int, int>(10, 32);
  return p.first + p.second;
}
''');
      expect(result, 42);
    });

    test('generic field comparison: Box<int>.value == 42', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
int main() {
  Box<int> b = Box<int>(42);
  if (b.value == 42) return 1;
  return 0;
}
''');
      expect(result, 1);
    });

    test('generic method return value participates in arithmetic', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
  T getValue() => value;
}
int main() {
  Box<int> b = Box<int>(10);
  return b.getValue() + 1;
}
''');
      expect(result, 11);
    });

    test('generic field assigned to int variable then used in arithmetic',
        () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
int main() {
  Box<int> b = Box<int>(20);
  int v = b.value;
  return v + 5;
}
''');
      expect(result, 25);
    });

    test('Box<double> field participates in double arithmetic', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
int main() {
  Box<double> b = Box<double>(3.5);
  double d = b.value + 1.5;
  return d.toInt();
}
''');
      expect(result, 5);
    });

    test('nested Box<Box<int>> inner field arithmetic', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
int main() {
  Box<int> inner = Box<int>(100);
  Box<Box<int>> outer = Box<Box<int>>(inner);
  return outer.value.value + 1;
}
''');
      expect(result, 101);
    });
  });

  group('generic field ref/value coercion', () {
    // A. Bool conditions

    test('if (Box<bool>.value) — condition unbox', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
int main() {
  Box<bool> b = Box<bool>(true);
  if (b.value) return 1;
  return 0;
}
''');
      expect(result, 1);
    });

    test('!Box<bool>.value — Not unbox', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
int main() {
  Box<bool> b = Box<bool>(false);
  if (!b.value) return 1;
  return 0;
}
''');
      expect(result, 1);
    });

    test('Box<bool>.value && true — LogicalExpression unbox', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
int main() {
  Box<bool> b = Box<bool>(true);
  if (b.value && true) return 1;
  return 0;
}
''');
      expect(result, 1);
    });

    test('Box<bool>.value ? 1 : 0 — ConditionalExpression condition unbox',
        () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
int main() {
  Box<bool> b = Box<bool>(true);
  return b.value ? 1 : 0;
}
''');
      expect(result, 1);
    });

    // B. Function arguments

    test('add(Box<int>.value, 5) — StaticInvocation ref→value arg', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
int add(int a, int b) => a + b;
int main() {
  Box<int> b = Box<int>(10);
  return add(b.value, 5);
}
''');
      expect(result, 15);
    });

    test('obj.method(Box<int>.value) — VirtualCall ref→value arg', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
class Adder {
  int add(int x) => x + 100;
}
int main() {
  Box<int> b = Box<int>(7);
  Adder a = Adder();
  return a.add(b.value);
}
''');
      expect(result, 107);
    });

    // C. Variable reassignment

    test('int v = 0; v = Box<int>.value; return v; — VariableSet ref→value',
        () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
int main() {
  Box<int> b = Box<int>(42);
  int v = 0;
  v = b.value;
  return v;
}
''');
      expect(result, 42);
    });
  });

  group('generic class inheritance', () {
    test('non-generic child extends generic parent: IntBox extends Box<int>',
        () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
class IntBox extends Box<int> {
  IntBox(int v) : super(v);
}
int main() {
  IntBox ib = IntBox(55);
  return ib.value;
}
''');
      expect(result, 55);
    });

    test('super method call on generic parent: arithmetic on return value',
        () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
  T getValue() => value;
}
class IntBox extends Box<int> {
  IntBox(int v) : super(v);
  int addOne() => super.getValue() + 1;
}
int main() {
  IntBox ib = IntBox(41);
  return ib.addOne();
}
''');
      expect(result, 42);
    });

    test('super generic method call with function-level type params', () async {
      final result = await compileAndRun('''
class Base {
  T identity<T>(T value) => value;
}
class Child extends Base {
  int foo() => super.identity<int>(41) + 1;
}
int main() {
  Child c = Child();
  return c.foo();
}
''');
      expect(result, 42);
    });

    test('super property get on generic parent: arithmetic on field value',
        () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
class IntBox extends Box<int> {
  IntBox(int v) : super(v);
  int doubled() => super.value + super.value;
}
int main() {
  IntBox ib = IntBox(21);
  return ib.doubled();
}
''');
      expect(result, 42);
    });

    test('super getter on generic parent returns substituted type', () async {
      final result = await compileAndRun('''
class Box<T> {
  T _val;
  Box(this._val);
  T get val => _val;
}
class IntBox extends Box<int> {
  IntBox(int v) : super(v);
  int inc() => super.val + 1;
}
int main() {
  IntBox ib = IntBox(9);
  return ib.inc();
}
''');
      expect(result, 10);
    });

    test('is check on non-generic child of generic parent', () async {
      final result = await compileAndRun('''
class Box<T> {
  T value;
  Box(this.value);
}
class IntBox extends Box<int> {
  IntBox(int v) : super(v);
}
int main() {
  IntBox ib = IntBox(1);
  int result = 0;
  if (ib is Box) result = result + 1;
  if (ib is IntBox) result = result + 2;
  return result;
}
''');
      // ib is Box (1) + ib is IntBox (2) = 3
      expect(result, 3);
    });
  });
}
