import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('Collection literal E2E', () {
    // ── List literals ──

    test('return list literal [1, 2, 3]', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return [1, 2, 3];
}
''');
      expect(result, equals([1, 2, 3]));
    });

    test('list literal with expressions [1 + 2, 3 * 4]', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return [1 + 2, 3 * 4];
}
''');
      expect(result, equals([3, 12]));
    });

    test('nested list literal [[1, 2], [3, 4]]', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return [[1, 2], [3, 4]];
}
''');
      expect(result, equals([[1, 2], [3, 4]]));
    });

    test('empty list literal', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return [];
}
''');
      expect(result, isA<List>());
      expect(result, isEmpty);
    });

    test('list with string elements', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return ['hello', 'world'];
}
''');
      expect(result, equals(['hello', 'world']));
    });

    test('list with mixed typed elements', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return [1, 'two', 3];
}
''');
      expect(result, equals([1, 'two', 3]));
    });

    test('list.length via bridge', () async {
      final result = await compileAndRunWithHost('''
int main() {
  var list = [1, 2, 3];
  return list.length;
}
''');
      expect(result, equals(3));
    });

    // ── Map literals ──

    test('return map literal', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return {'a': 1};
}
''');
      expect(result, equals({'a': 1}));
    });

    test('map literal with multiple entries', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return {'a': 1, 'b': 2, 'c': 3};
}
''');
      expect(result, equals({'a': 1, 'b': 2, 'c': 3}));
    });

    test('empty map literal', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return <String, int>{};
}
''');
      expect(result, isA<Map>());
      expect(result, isEmpty);
    });

    test('map.length via bridge', () async {
      final result = await compileAndRunWithHost('''
int main() {
  var map = {'a': 1, 'b': 2};
  return map.length;
}
''');
      expect(result, equals(2));
    });

    // ── Set literals ──

    test('return set literal', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return {1, 2, 3};
}
''');
      expect(result, equals({1, 2, 3}));
    });

    test('empty set literal', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return <int>{};
}
''');
      expect(result, isA<Set>());
      expect(result, isEmpty);
    });

    // ── Constant collections ──

    test('const list literal', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return const [1, 2, 3];
}
''');
      expect(result, equals([1, 2, 3]));
    });

    test('const map literal', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return const {'a': 1, 'b': 2};
}
''');
      expect(result, equals({'a': 1, 'b': 2}));
    });

    test('const set literal', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return const {1, 2, 3};
}
''');
      expect(result, equals({1, 2, 3}));
    });

    test('list assigned to variable then returned', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  var x = [10, 20, 30];
  return x;
}
''');
      expect(result, equals([10, 20, 30]));
    });

    test('map with int keys', () async {
      final result = await compileAndRunWithHost('''
Object main() {
  return {1: 'one', 2: 'two'};
}
''');
      expect(result, equals({1: 'one', 2: 'two'}));
    });
  });
}
