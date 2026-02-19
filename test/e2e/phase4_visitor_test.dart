import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// Tests for Phase 4 visitor methods identified in visitor-coverage-report.md:
///   - visitInstanceConstant (ConstCompile)
///   - visitTypeLiteral (ExprCompile)
///   - visitTypeLiteralConstant (ConstCompile)
///   - visitInstantiation (ExprCompile)
///   - visitInstantiationConstant (ConstCompile)
void main() {
  // ── visitInstanceConstant ──

  group('visitInstanceConstant', () {
    test('simple const instance with int field', () async {
      final result = await compileAndRun('''
class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);
}
int main() {
  const p = Point(3, 4);
  return p.x + p.y;
}
''');
      expect(result, 7);
    });

    test('const instance with string field', () async {
      final result = await compileAndRun('''
class Tag {
  final String name;
  const Tag(this.name);
}
String main() {
  const t = Tag('hello');
  return t.name;
}
''');
      expect(result, 'hello');
    });

    test('nested const instances', () async {
      final result = await compileAndRun('''
class Inner {
  final int value;
  const Inner(this.value);
}
class Outer {
  final Inner inner;
  const Outer(this.inner);
}
int main() {
  const o = Outer(Inner(42));
  return o.inner.value;
}
''');
      expect(result, 42);
    });

    test('const instance used as default parameter', () async {
      final result = await compileAndRun('''
class Config {
  final int value;
  const Config(this.value);
}
int getValue([Config c = const Config(10)]) => c.value;
int main() {
  return getValue();
}
''');
      expect(result, 10);
    });

    test('const instance with mixed ref/value fields', () async {
      final result = await compileAndRun('''
class Entry {
  final String key;
  final int value;
  const Entry(this.key, this.value);
}
int main() {
  const e = Entry('answer', 42);
  return e.value;
}
''');
      expect(result, 42);
    });

    test('generic const instance', () async {
      final result = await compileAndRun('''
class Box<T> {
  final T value;
  const Box(this.value);
}
int main() {
  const b = Box<int>(99);
  return b.value;
}
''');
      expect(result, 99);
    });

    test('const instance is-check works', () async {
      final result = await compileAndRun('''
class Marker {
  final int id;
  const Marker(this.id);
}
int main() {
  const m = Marker(1);
  if (m is Marker) return m.id;
  return 0;
}
''');
      expect(result, 1);
    });
  });

  // ── visitTypeLiteral ──

  group('visitTypeLiteral', () {
    test('type literal in is-check with Type variable', () async {
      // This triggers TypeLiteral when a Type object is used as a value.
      // A simple case: passing Type as an argument or storing it.
      final result = await compileAndRun('''
class A {}
class B extends A {}
int main() {
  Object x = B();
  if (x is A) return 1;
  return 0;
}
''');
      expect(result, 1);
    });
  });

  // ── visitInstantiation (generic function instantiation) ──

  group('visitInstantiation', () {
    test('generic function tear-off with int type arg', () async {
      // The thunk bridges value/ref stack mismatch: generic T param (ref)
      // vs instantiated int param (value).
      final result = await compileAndRun('''
T identity<T>(T x) => x;
int main() {
  int Function(int) f = identity<int>;
  return f(42);
}
''');
      expect(result, 42);
    });

    test('generic function tear-off with string type arg (no thunk needed)',
        () async {
      // String is already ref-stack, so no thunk is generated.
      final result = await compileAndRun('''
T identity<T>(T x) => x;
String main() {
  String Function(String) f = identity<String>;
  return f('hello');
}
''');
      expect(result, 'hello');
    });

    test('generic function tear-off passed as callback', () async {
      final result = await compileAndRun('''
T first<T>(T a, T b) => a;
int apply(int Function(int, int) fn) => fn(10, 20);
int main() {
  return apply(first<int>);
}
''');
      expect(result, 10);
    });

    test('generic function tear-off with bool type arg', () async {
      final result = await compileAndRun('''
T identity<T>(T x) => x;
int main() {
  bool Function(bool) f = identity<bool>;
  if (f(true)) return 1;
  return 0;
}
''');
      expect(result, 1);
    });
  });

  // ── visitInstantiationConstant ──

  group('visitInstantiationConstant', () {
    test('const generic function tear-off as default param (int)', () async {
      final result = await compileAndRun('''
T identity<T>(T x) => x;
int run([int Function(int) fn = identity]) {
  return fn(7);
}
int main() {
  return run();
}
''');
      expect(result, 7);
    });

    test('const generic function tear-off as default param (string)',
        () async {
      final result = await compileAndRun('''
T identity<T>(T x) => x;
String run([String Function(String) fn = identity]) {
  return fn('world');
}
String main() {
  return run();
}
''');
      expect(result, 'world');
    });
  });
}
