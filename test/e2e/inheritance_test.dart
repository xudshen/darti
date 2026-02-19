import 'package:dartic/src/runtime/object.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('inheritance e2e', () {
    test('simple inheritance: child inherits parent fields', () async {
      final result = await compileAndRun('''
class Animal {
  int legs;
  Animal(this.legs);
}
class Dog extends Animal {
  Dog() : super(4);
}
Object main() => Dog();
''');
      final obj = result as DarticObject;
      // Dog inherits `legs` from Animal at valueFields[0].
      expect(obj.valueFields[0], 4);
    });

    test('child class accesses inherited field', () async {
      final result = await compileAndRun('''
class Base {
  int x;
  Base(this.x);
}
class Child extends Base {
  Child(int v) : super(v);
  int getX() => x;
}
int main() {
  Child c = Child(42);
  return c.getX();
}
''');
      expect(result, 42);
    });

    test('child class has own fields after parent fields', () async {
      final result = await compileAndRun('''
class Parent {
  int a;
  int b;
  Parent(this.a, this.b);
}
class Child extends Parent {
  int c;
  Child(int a, int b, this.c) : super(a, b);
}
Object main() => Child(10, 20, 30);
''');
      final obj = result as DarticObject;
      // Parent: a=valueFields[0], b=valueFields[1]
      // Child: c=valueFields[2] (offset starts after parent's 2 value fields)
      expect(obj.valueFields[0], 10);
      expect(obj.valueFields[1], 20);
      expect(obj.valueFields[2], 30);
    });

    test('super method call', () async {
      final result = await compileAndRun('''
class A {
  int f() => 1;
}
class B extends A {
  int g() => super.f() + 10;
}
int main() {
  B b = B();
  return b.g();
}
''');
      expect(result, 11);
    });

    test('super constructor call initializes parent fields', () async {
      final result = await compileAndRun('''
class Shape {
  int sides;
  Shape(this.sides);
}
class Triangle extends Shape {
  String name;
  Triangle(this.name) : super(3);
}
Object main() => Triangle('tri');
''');
      final obj = result as DarticObject;
      // Shape: sides=valueFields[0]
      // Triangle: name=refFields[0]
      expect(obj.valueFields[0], 3);
      expect(obj.refFields[0], 'tri');
    });

    test('multi-level inheritance: A -> B -> C', () async {
      final result = await compileAndRun('''
class A {
  int val() => 100;
}
class B extends A {
  int doubled() => super.val() * 2;
}
class C extends B {
  int tripled() => super.doubled() + super.val();
}
int main() {
  C c = C();
  return c.tripled();
}
''');
      // C.tripled() = B.doubled() + A.val() = (100*2) + 100 = 300
      expect(result, 300);
    });

    test('field offset calculation with mixed types across inheritance',
        () async {
      final result = await compileAndRun('''
class Base {
  int x;
  String name;
  Base(this.x, this.name);
}
class Derived extends Base {
  int y;
  String label;
  Derived(int x, String name, this.y, this.label) : super(x, name);
}
Object main() => Derived(1, 'base', 2, 'derived');
''');
      final obj = result as DarticObject;
      // Base: x=valueFields[0], name=refFields[0]
      // Derived: y=valueFields[1], label=refFields[1]
      expect(obj.valueFields[0], 1);
      expect(obj.refFields[0], 'base');
      expect(obj.valueFields[1], 2);
      expect(obj.refFields[1], 'derived');
    });

    test('instanceof check with inheritance', () async {
      final result = await compileAndRun('''
class Animal {
  int legs;
  Animal(this.legs);
}
class Dog extends Animal {
  Dog() : super(4);
}
int main() {
  Dog d = Dog();
  if (d is Animal) return 1;
  return 0;
}
''');
      expect(result, 1);
    });
  });
}
