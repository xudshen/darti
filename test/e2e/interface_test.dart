import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('implements interface contracts', () {
    test('simple implements: Dog implements Animal, is Animal == true',
        () async {
      final result = await compileAndRun('''
abstract class Animal {
  String speak();
}
class Dog implements Animal {
  String speak() => 'Woof';
}
int main() {
  Dog d = Dog();
  if (d is Animal) return 1;
  return 0;
}
''');
      expect(result, 1);
    });

    test('simple implements: interface method call works', () async {
      final result = await compileAndRun('''
abstract class Animal {
  String speak();
}
class Dog implements Animal {
  String speak() => 'Woof';
}
String main() {
  Dog d = Dog();
  return d.speak();
}
''');
      expect(result, 'Woof');
    });

    test('multiple implements: C implements A, B — is A and is B both true',
        () async {
      final result = await compileAndRun('''
abstract class A {
  int fa();
}
abstract class B {
  int fb();
}
class C implements A, B {
  int fa() => 10;
  int fb() => 20;
}
int main() {
  C c = C();
  int result = 0;
  if (c is A) result = result + 1;
  if (c is B) result = result + 2;
  return result;
}
''');
      // Both is A (1) and is B (2) should be true -> 3
      expect(result, 3);
    });

    test('interface inheritance chain: C implements B, B implements A — C is A',
        () async {
      final result = await compileAndRun('''
abstract class A {
  int fa();
}
abstract class B implements A {
  int fb();
}
class C implements B {
  int fa() => 1;
  int fb() => 2;
}
int main() {
  C c = C();
  int result = 0;
  if (c is A) result = result + 1;
  if (c is B) result = result + 2;
  return result;
}
''');
      // C is A (through B) and C is B -> 3
      expect(result, 3);
    });

    test('interface method call through interface type reference', () async {
      final result = await compileAndRun('''
abstract class Speakable {
  String speak();
}
class Cat implements Speakable {
  String speak() => 'Meow';
}
String main() {
  Speakable s = Cat();
  return s.speak();
}
''');
      expect(result, 'Meow');
    });

    test('abstract method does not generate bytecode (no crash)', () async {
      // This test verifies that abstract methods are correctly skipped
      // during Pass 2c compilation. If they were compiled, the null body
      // would cause a crash.
      final result = await compileAndRun('''
abstract class Shape {
  int area();
  int perimeter();
}
class Square implements Shape {
  int side;
  Square(this.side);
  int area() => side * side;
  int perimeter() => side * 4;
}
int main() {
  Square s = Square(5);
  return s.area() + s.perimeter();
}
''');
      // area=25, perimeter=20 -> 45
      expect(result, 45);
    });

    test('abstract class with concrete method and constructor via implements',
        () async {
      final result = await compileAndRun('''
abstract class Base {
  int value() => 42;
  int doubled();
}
class Impl implements Base {
  int value() => 42;
  int doubled() => value() * 2;
}
int main() {
  Impl i = Impl();
  return i.doubled();
}
''');
      expect(result, 84);
    });

    test('implements does not inherit fields (no super constructor)',
        () async {
      // Unlike extends, implements does not bring in field layout or constructors.
      // The implementing class must provide its own fields.
      final result = await compileAndRun('''
abstract class Named {
  String getName();
}
class Person implements Named {
  String name;
  Person(this.name);
  String getName() => name;
}
String main() {
  Person p = Person('Alice');
  return p.getName();
}
''');
      expect(result, 'Alice');
    });

    test('extends + implements combined', () async {
      final result = await compileAndRun('''
class Base {
  int baseVal() => 10;
}
abstract class Printable {
  String label();
}
class Child extends Base implements Printable {
  String label() => 'child';
}
int main() {
  Child c = Child();
  int result = 0;
  if (c is Base) result = result + 1;
  if (c is Printable) result = result + 2;
  return result + c.baseVal();
}
''');
      // is Base (1) + is Printable (2) + baseVal (10) = 13
      expect(result, 13);
    });
  });
}
