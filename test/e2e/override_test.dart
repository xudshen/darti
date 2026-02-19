import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('method override e2e', () {
    test('child overrides parent method', () async {
      final result = await compileAndRun('''
class A {
  int f() => 1;
}
class B extends A {
  int f() => 2;
}
int main() {
  B b = B();
  return b.f();
}
''');
      expect(result, 2);
    });

    test('polymorphic dispatch: static type A, runtime type B', () async {
      final result = await compileAndRun('''
class A {
  int f() => 1;
}
class B extends A {
  int f() => 2;
}
int main() {
  A obj = B();
  return obj.f();
}
''');
      // Runtime dispatch to B.f() even though static type is A.
      expect(result, 2);
    });

    test('inherited method not overridden', () async {
      final result = await compileAndRun('''
class A {
  int g() => 10;
}
class B extends A {}
int main() {
  B b = B();
  return b.g();
}
''');
      expect(result, 10);
    });

    test('multi-level override: A -> B -> C', () async {
      final result = await compileAndRun('''
class A {
  int f() => 1;
}
class B extends A {
  int f() => 2;
}
class C extends B {
  int f() => 3;
}
int main() {
  A a = A();
  A b = B();
  A c = C();
  return a.f() * 100 + b.f() * 10 + c.f();
}
''');
      // a.f()=1, b.f()=2, c.f()=3 → 123
      expect(result, 123);
    });

    test('IC polymorphism: same call site, different receiver types', () async {
      final result = await compileAndRun('''
class A {
  int f() => 10;
}
class B extends A {
  int f() => 20;
}
int callF(A obj) => obj.f();
int main() {
  A a = A();
  B b = B();
  int r1 = callF(a);
  int r2 = callF(b);
  return r1 + r2;
}
''');
      // callF(a)=10, callF(b)=20 → 30
      // The same CALL_VIRTUAL site in callF first sees A, then B → IC miss on second call.
      expect(result, 30);
    });

    test('override with super call', () async {
      final result = await compileAndRun('''
class A {
  int f() => 5;
}
class B extends A {
  int f() => super.f() + 10;
}
int main() {
  A obj = B();
  return obj.f();
}
''');
      // B.f() calls super.f() (A.f()=5) + 10 = 15
      expect(result, 15);
    });

    test('inherited method with own fields', () async {
      final result = await compileAndRun('''
class Base {
  int x;
  Base(this.x);
  int getX() => x;
}
class Child extends Base {
  int y;
  Child(int x, this.y) : super(x);
}
int main() {
  Child c = Child(42, 99);
  return c.getX();
}
''');
      // Child inherits getX() from Base, which reads field x.
      expect(result, 42);
    });
  });
}
