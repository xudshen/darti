import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('operator overloading e2e', () {
    test('operator+ on user-defined class', () async {
      final result = await compileAndRun('''
class Vec {
  int x;
  Vec(this.x);
  Vec operator+(Vec other) => Vec(x + other.x);
  int getX() => x;
}
int main() {
  Vec a = Vec(10);
  Vec b = Vec(20);
  Vec c = a + b;
  return c.getX();
}
''');
      expect(result, 30);
    });

    test('operator- on user-defined class', () async {
      final result = await compileAndRun('''
class Num {
  int v;
  Num(this.v);
  Num operator-(Num other) => Num(v - other.v);
  int getV() => v;
}
int main() {
  Num a = Num(50);
  Num b = Num(20);
  Num c = a - b;
  return c.getV();
}
''');
      expect(result, 30);
    });

    test('operator* on user-defined class', () async {
      final result = await compileAndRun('''
class Scalar {
  int v;
  Scalar(this.v);
  Scalar operator*(Scalar other) => Scalar(v * other.v);
  int getV() => v;
}
int main() {
  Scalar a = Scalar(5);
  Scalar b = Scalar(6);
  return (a * b).getV();
}
''');
      expect(result, 30);
    });

    test('comparison operators: < and >', () async {
      final result = await compileAndRun('''
class Score {
  int v;
  Score(this.v);
  bool operator<(Score other) => v < other.v;
  bool operator>(Score other) => v > other.v;
}
int main() {
  Score a = Score(10);
  Score b = Score(20);
  int r = 0;
  if (a < b) r = r + 1;
  if (b > a) r = r + 10;
  return r;
}
''');
      expect(result, 11);
    });

    test('operator== on user-defined class', () async {
      final result = await compileAndRun('''
class Id {
  int v;
  Id(this.v);
  bool operator==(Object other) {
    if (other is Id) return v == other.v;
    return false;
  }
}
int main() {
  Id a = Id(42);
  Id b = Id(42);
  Id c = Id(99);
  int r = 0;
  if (a == b) r = r + 1;
  if (a == c) r = r + 10;
  return r;
}
''');
      // a==b is true (+1), a==c is false (+0) → 1
      expect(result, 1);
    });

    test('operator[] getter', () async {
      final result = await compileAndRun('''
class MyList {
  int a;
  int b;
  int c;
  MyList(this.a, this.b, this.c);
  int operator[](int index) {
    if (index == 0) return a;
    if (index == 1) return b;
    return c;
  }
}
int main() {
  MyList m = MyList(10, 20, 30);
  return m[0] + m[1] + m[2];
}
''');
      expect(result, 60);
    });

    test('operator[]= setter', () async {
      final result = await compileAndRun('''
class MyList {
  int a;
  int b;
  MyList(this.a, this.b);
  void operator[]=(int index, int value) {
    if (index == 0) a = value;
    else b = value;
  }
  int operator[](int index) {
    if (index == 0) return a;
    return b;
  }
}
int main() {
  MyList m = MyList(0, 0);
  m[0] = 10;
  m[1] = 20;
  return m[0] + m[1];
}
''');
      expect(result, 30);
    });

    test('unary minus operator', () async {
      final result = await compileAndRun('''
class Num {
  int v;
  Num(this.v);
  Num operator-() => Num(0 - v);
  int getV() => v;
}
int main() {
  Num a = Num(42);
  Num b = -a;
  return b.getV();
}
''');
      // -42 is represented as 0 - 42 = -42
      expect(result, -42);
    });

    test('chained operator calls', () async {
      final result = await compileAndRun('''
class Vec {
  int x;
  Vec(this.x);
  Vec operator+(Vec other) => Vec(x + other.x);
  Vec operator-(Vec other) => Vec(x - other.x);
  int getX() => x;
}
int main() {
  Vec a = Vec(100);
  Vec b = Vec(30);
  Vec c = Vec(20);
  Vec d = (a - b) + c;
  return d.getX();
}
''');
      // (100 - 30) + 20 = 90
      expect(result, 90);
    });
  });
}
