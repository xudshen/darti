import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('abstract class e2e', () {
    test('concrete subclass implements abstract method', () async {
      final result = await compileAndRun('''
abstract class Shape {
  int area();
}
class Circle extends Shape {
  int area() => 314;
}
int main() {
  Circle c = Circle();
  return c.area();
}
''');
      expect(result, 314);
    });

    test('abstract class as type declaration (polymorphism)', () async {
      final result = await compileAndRun('''
abstract class Shape {
  int area();
}
class Circle extends Shape {
  int area() => 314;
}
int main() {
  Shape s = Circle();
  return s.area();
}
''');
      expect(result, 314);
    });

    test('mixed abstract and concrete methods', () async {
      final result = await compileAndRun('''
abstract class Animal {
  int legs();
  String describe() => 'animal';
}
class Dog extends Animal {
  int legs() => 4;
}
int main() {
  Dog d = Dog();
  return d.legs();
}
''');
      expect(result, 4);
    });

    test('inherited concrete method from abstract class', () async {
      final result = await compileAndRun('''
abstract class Base {
  int value() => 42;
  int doubled();
}
class Impl extends Base {
  int doubled() => value() * 2;
}
int main() {
  Impl i = Impl();
  return i.doubled();
}
''');
      // doubled() = value() * 2 = 42 * 2 = 84
      expect(result, 84);
    });

    test('abstract class with constructor and fields', () async {
      final result = await compileAndRun('''
abstract class Shape {
  int sides;
  Shape(this.sides);
  int getSides() => sides;
  int area();
}
class Square extends Shape {
  int size;
  Square(this.size) : super(4);
  int area() => size * size;
}
int main() {
  Square s = Square(5);
  return s.area() + s.getSides();
}
''');
      // area()=25, getSides()=4 → 29
      expect(result, 29);
    });

    test('polymorphic dispatch through abstract type', () async {
      final result = await compileAndRun('''
abstract class Shape {
  int area();
}
class Rect extends Shape {
  int area() => 20;
}
class Tri extends Shape {
  int area() => 10;
}
int totalArea(Shape a, Shape b) => a.area() + b.area();
int main() {
  Rect r = Rect();
  Tri t = Tri();
  return totalArea(r, t);
}
''');
      expect(result, 30);
    });
  });
}
