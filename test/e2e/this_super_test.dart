import 'package:dartic/src/runtime/object.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('this reference', () {
    test('implicit this field access via InstanceGet', () async {
      final result = await compileAndRun('''
class Box {
  int x;
  Box(this.x);
  int getX() => x;
}
int main() {
  Box b = Box(42);
  return b.getX();
}
''');
      // Kernel resolves `x` in getX() as `this.x` (InstanceGet with
      // ThisExpression receiver). The compiler reads field from rsp+2.
      expect(result, 42);
    });

    test('explicit return this', () async {
      final result = await compileAndRun('''
class Node {
  int value;
  Node(this.value);
  Object self() => this;
}
Object main() {
  Node n = Node(7);
  return n.self();
}
''');
      // `return this;` returns the DarticObject itself.
      final obj = result as DarticObject;
      expect(obj.valueFields[0], 7);
    });

    test('this as argument to another method', () async {
      final result = await compileAndRun('''
class Extractor {
  int extract(Box b) => b.value;
}
class Box {
  int value;
  Box(this.value);
  int extractVia(Extractor e) => e.extract(this);
}
int main() {
  Box b = Box(99);
  Extractor e = Extractor();
  return b.extractVia(e);
}
''');
      // `this` is passed as an argument to Extractor.extract.
      expect(result, 99);
    });

    test('implicit this in instance method (bare field name)', () async {
      final result = await compileAndRun('''
class Counter {
  int count;
  Counter(this.count);
  int increment() {
    count = count + 1;
    return count;
  }
}
int main() {
  Counter c = Counter(10);
  return c.increment();
}
''');
      // Kernel resolves bare `count` as `this.count`.
      expect(result, 11);
    });

    test('this in constructor body', () async {
      final result = await compileAndRun('''
class Pair {
  int a;
  int b;
  Pair(int x) : a = x, b = 0 {
    b = a * 2;
  }
  int sum() => a + b;
}
int main() {
  Pair p = Pair(10);
  return p.sum();
}
''');
      // Constructor body accesses `this.b` (via this at rsp+2) to set b = a*2.
      // a=10, b=20, sum=30.
      expect(result, 30);
    });

    test('this passed to method that calls back', () async {
      final result = await compileAndRun('''
class Caller {
  int callGetValue(Provider p) => p.getValue();
}
class Provider {
  int x;
  Provider(this.x);
  int getValue() => x;
  int delegateTo(Caller c) => c.callGetValue(this);
}
int main() {
  Provider p = Provider(55);
  Caller c = Caller();
  return p.delegateTo(c);
}
''');
      // Provider passes `this` to Caller, which calls back getValue() on it.
      expect(result, 55);
    });

    test('this identity: returned this is the same object', () async {
      final result = await compileAndRun('''
class Wrapper {
  int x;
  Wrapper(this.x);
  Object me() => this;
}
int main() {
  Wrapper w = Wrapper(5);
  Object o = w.me();
  Wrapper w2 = o as Wrapper;
  return w2.x;
}
''');
      // The returned `this` can be used as the same object.
      expect(result, 5);
    });
  });

  group('super field access', () {
    test('super field read via SuperPropertyGet', () async {
      final result = await compileAndRun('''
class Parent {
  int x;
  Parent(this.x);
}
class Child extends Parent {
  Child(int v) : super(v);
  int getParentX() => super.x;
}
int main() {
  Child c = Child(42);
  return c.getParentX();
}
''');
      // super.x reads the parent's field via GET_FIELD on this.
      expect(result, 42);
    });

    test('super field access with child own fields', () async {
      final result = await compileAndRun('''
class Base {
  int a;
  Base(this.a);
}
class Derived extends Base {
  int b;
  Derived(int a, this.b) : super(a);
  int parentA() => super.a;
  int sum() => parentA() + b;
}
int main() {
  Derived d = Derived(10, 32);
  return d.sum();
}
''');
      // super.a = 10, b = 32, sum = 42.
      expect(result, 42);
    });
  });

  group('super getter', () {
    test('super getter call', () async {
      final result = await compileAndRun('''
class Parent {
  int _x;
  Parent(this._x);
  int get value => _x;
}
class Child extends Parent {
  Child(int v) : super(v);
  int getParentValue() => super.value;
}
int main() {
  Child c = Child(42);
  return c.getParentValue();
}
''');
      // super.value calls Parent's getter via CALL_SUPER.
      expect(result, 42);
    });

    test('super getter with computation', () async {
      final result = await compileAndRun('''
class Base {
  int a;
  int b;
  Base(this.a, this.b);
  int get product => a * b;
}
class Sub extends Base {
  Sub(int a, int b) : super(a, b);
  int getBaseProduct() => super.product;
}
int main() {
  Sub s = Sub(6, 7);
  return s.getBaseProduct();
}
''');
      // super.product calls Base's getter: 6*7 = 42.
      expect(result, 42);
    });
  });

  group('super setter', () {
    test('super setter call', () async {
      final result = await compileAndRun('''
class Parent {
  int _x;
  Parent(this._x);
  int get value => _x;
  set value(int v) { _x = v; }
}
class Child extends Parent {
  Child(int v) : super(v);
  void setParentValue(int v) { super.value = v; }
  int getParentValue() => super.value;
}
int main() {
  Child c = Child(0);
  c.setParentValue(42);
  return c.getParentValue();
}
''');
      // super.value = 42 calls Parent's setter via CALL_SUPER.
      expect(result, 42);
    });

    test('super setter with computation in setter body', () async {
      final result = await compileAndRun('''
class Base {
  int _v;
  Base(this._v);
  int get val => _v;
  set val(int x) { _v = x * 2; }
}
class Sub extends Base {
  Sub(int v) : super(v);
  void setBaseVal(int x) { super.val = x; }
  int getBaseVal() => super.val;
}
int main() {
  Sub s = Sub(0);
  s.setBaseVal(21);
  return s.getBaseVal();
}
''');
      // super.val = 21 triggers Base's setter: _v = 21*2 = 42.
      expect(result, 42);
    });
  });

  group('super method with arguments', () {
    test('super method call with value args', () async {
      final result = await compileAndRun('''
class A {
  int add(int x, int y) => x + y;
}
class B extends A {
  int callSuperAdd(int x, int y) => super.add(x, y);
}
int main() {
  B b = B();
  return b.callSuperAdd(10, 32);
}
''');
      // super.add(10, 32) calls A.add via CALL_SUPER.
      expect(result, 42);
    });

    test('super method call with ref args', () async {
      final result = await compileAndRun('''
class Base {
  String combine(String a, String b) => a;
}
class Child extends Base {
  int callSuperCombine() {
    String r = super.combine('hello', 'world');
    if (r == 'hello') return 1;
    return 0;
  }
}
int main() {
  Child c = Child();
  return c.callSuperCombine();
}
''');
      // super.combine passes String (ref) args.
      expect(result, 1);
    });

    test('super method call with mixed value and ref args', () async {
      final result = await compileAndRun('''
class Base {
  int process(int n, String label) => n;
}
class Child extends Base {
  int callProcess() => super.process(42, 'test');
}
int main() {
  Child c = Child();
  return c.callProcess();
}
''');
      // super.process(42, 'test') — mixed int (value) and String (ref) args.
      expect(result, 42);
    });
  });

  group('chained super calls', () {
    test('A -> B -> C: C calls super which calls super', () async {
      final result = await compileAndRun('''
class A {
  int f() => 100;
}
class B extends A {
  int f() => super.f() + 10;
}
class C extends B {
  int f() => super.f() + 1;
}
int main() {
  C c = C();
  return c.f();
}
''');
      // C.f() → B.f() → A.f()=100 + 10 = 110 + 1 = 111
      expect(result, 111);
    });

    test('three-level super with fields', () async {
      final result = await compileAndRun('''
class A {
  int a;
  A(this.a);
  int getA() => a;
}
class B extends A {
  int b;
  B(int a, this.b) : super(a);
  int getSum() => super.getA() + b;
}
class C extends B {
  int c;
  C(int a, int b, this.c) : super(a, b);
  int total() => super.getSum() + c;
}
int main() {
  C obj = C(10, 20, 12);
  return obj.total();
}
''');
      // C.total() → B.getSum()=A.getA()+b = 10+20=30 + 12 = 42
      expect(result, 42);
    });

    test('deep chain: four levels of super calls', () async {
      final result = await compileAndRun('''
class L0 {
  int val() => 1;
}
class L1 extends L0 {
  int val() => super.val() * 10;
}
class L2 extends L1 {
  int val() => super.val() * 10;
}
class L3 extends L2 {
  int val() => super.val() * 10;
}
int main() {
  L3 obj = L3();
  return obj.val();
}
''');
      // L3.val()=L2.val()*10 = L1.val()*100 = L0.val()*1000 = 1000
      expect(result, 1000);
    });
  });

  group('combined this and super scenarios', () {
    test('method uses both this fields and super method', () async {
      final result = await compileAndRun('''
class Base {
  int base() => 10;
}
class Child extends Base {
  int x;
  Child(this.x);
  int combined() => x + super.base();
}
int main() {
  Child c = Child(32);
  return c.combined();
}
''');
      // combined() reads this.x (32) + super.base() (10) = 42.
      expect(result, 42);
    });

    test('super property get on ref field', () async {
      final result = await compileAndRun('''
class Parent {
  String name;
  Parent(this.name);
}
class Child extends Parent {
  Child(String n) : super(n);
  String getParentName() => super.name;
}
int main() {
  Child c = Child('dartic');
  if (c.getParentName() == 'dartic') return 1;
  return 0;
}
''');
      // super.name reads parent's String (ref) field.
      expect(result, 1);
    });

    test('override method and call super version', () async {
      final result = await compileAndRun('''
class A {
  int compute() => 5;
}
class B extends A {
  int compute() => super.compute() * 2;
}
int main() {
  B b = B();
  int fromB = b.compute();
  A a = A();
  int fromA = a.compute();
  return fromB + fromA;
}
''');
      // B.compute() = A.compute()*2 = 10; A.compute() = 5; total = 15.
      expect(result, 15);
    });
  });
}
