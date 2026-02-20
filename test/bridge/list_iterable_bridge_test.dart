import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('List bridge', () {
    test('[1,2,3].length', () async {
      final result = await compileAndRunWithHost('''
int main() {
  List<int> list = [1, 2, 3];
  return list.length;
}
''');
      expect(result, 3);
    });

    test('[].isEmpty', () async {
      final result = await compileAndRunWithHost('''
bool main() {
  List<int> list = [];
  return list.isEmpty;
}
''');
      expect(result, true);
    });

    test('[10,20,30][1]', () async {
      final result = await compileAndRunWithHost('''
int main() {
  List<int> list = [10, 20, 30];
  return list[1];
}
''');
      expect(result, 20);
    });

    test('list[0] = 99', () async {
      final result = await compileAndRunWithHost('''
int main() {
  List<int> list = [10, 20, 30];
  list[0] = 99;
  return list[0];
}
''');
      expect(result, 99);
    });

    test('list.add and list.length', () async {
      final result = await compileAndRunWithHost('''
int main() {
  List<int> list = [1, 2];
  list.add(3);
  return list.length;
}
''');
      expect(result, 3);
    });

    test('list.contains(2)', () async {
      final result = await compileAndRunWithHost('''
bool main() {
  List<int> list = [1, 2, 3];
  return list.contains(2);
}
''');
      expect(result, true);
    });

    test('list.indexOf(2)', () async {
      final result = await compileAndRunWithHost('''
int main() {
  List<int> list = [1, 2, 3];
  return list.indexOf(2);
}
''');
      expect(result, 1);
    });

    test('[1,2,3].join(",")', () async {
      final result = await compileAndRunWithHost('''
String main() {
  List<int> list = [1, 2, 3];
  return list.join(',');
}
''');
      expect(result, '1,2,3');
    });

    test('[1,2].first', () async {
      final result = await compileAndRunWithHost('''
int main() {
  List<int> list = [1, 2];
  return list.first;
}
''');
      expect(result, 1);
    });

    test('[1,2].last', () async {
      final result = await compileAndRunWithHost('''
int main() {
  List<int> list = [1, 2];
  return list.last;
}
''');
      expect(result, 2);
    });

    test('list.removeAt(0)', () async {
      final result = await compileAndRunWithHost('''
int main() {
  List<int> list = [10, 20, 30];
  list.removeAt(0);
  return list[0];
}
''');
      expect(result, 20);
    });

    test('list.removeLast()', () async {
      final result = await compileAndRunWithHost('''
int main() {
  List<int> list = [10, 20, 30];
  list.removeLast();
  return list.length;
}
''');
      expect(result, 2);
    });

    test('List.filled(3, 0)', () async {
      final result = await compileAndRunWithHost('''
int main() {
  List<int> list = List.filled(3, 0);
  return list.length;
}
''');
      expect(result, 3);
    });
  });

  group('List missing methods', () {
    test('removeWhere', () async {
      final result = await compileAndRunWithHost('''
String main() {
  List<int> list = [1, 2, 3, 4];
  list.removeWhere((e) => e.isEven);
  return list.toString();
}
''');
      expect(result, '[1, 3]');
    });

    test('retainWhere', () async {
      final result = await compileAndRunWithHost('''
String main() {
  List<int> list = [1, 2, 3, 4];
  list.retainWhere((e) => e.isEven);
  return list.toString();
}
''');
      expect(result, '[2, 4]');
    });

    test('expand', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return [1, 2].expand((e) => [e, e * 10]).toList().toString();
}
''');
      expect(result, '[1, 10, 2, 20]');
    });

    test('reduce', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return [1, 2, 3].reduce((a, b) => a + b);
}
''');
      expect(result, 6);
    });

    test('firstWhere', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return [1, 2, 3, 4].firstWhere((e) => e > 2);
}
''');
      expect(result, 3);
    });

    test('lastWhere', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return [1, 2, 3, 4].lastWhere((e) => e < 3);
}
''');
      expect(result, 2);
    });

    test('singleWhere', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return [42].singleWhere((e) => e == 42);
}
''');
      expect(result, 42);
    });

    test('operator +', () async {
      final result = await compileAndRunWithHost('''
int main() {
  List<int> a = [1, 2];
  List<int> b = [3, 4];
  return (a + b).length;
}
''');
      expect(result, 4);
    });

    test('single', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return [42].single;
}
''');
      expect(result, 42);
    });
  });

  group('Iterable missing methods', () {
    test('reduce', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return Iterable.generate(5).reduce((a, b) => a + b);
}
''');
      expect(result, 10);
    });

    test('takeWhile', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return Iterable.generate(5).takeWhile((e) => e < 3).toList().toString();
}
''');
      expect(result, '[0, 1, 2]');
    });

    test('skipWhile', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return Iterable.generate(5).skipWhile((e) => e < 3).toList().toString();
}
''');
      expect(result, '[3, 4]');
    });

    test('firstWhere', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return Iterable.generate(5).firstWhere((e) => e > 2);
}
''');
      expect(result, 3);
    });

    test('single', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return Iterable.generate(1).single;
}
''');
      expect(result, 0);
    });

    test('followedBy', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return Iterable.generate(3).followedBy(Iterable.generate(2)).toList().toString();
}
''');
      expect(result, '[0, 1, 2, 0, 1]');
    });
  });
}
