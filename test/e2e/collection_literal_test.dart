import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// Compiles Dart source and executes with CoreBindings host functions.
Future<Object?> _compileAndRunWithHost(String source) async {
  final module = await compileDart(source);
  final registry = HostFunctionRegistry();
  CoreBindings.registerAll(registry);
  final interp = DarticInterpreter(hostFunctionRegistry: registry);
  interp.execute(module);
  return interp.entryResult;
}

void main() {
  group('Collection literal E2E', () {
    // ── List literals ──

    test('return list literal [1, 2, 3]', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return [1, 2, 3];
}
''');
      expect(result, isA<List>());
      expect(result, equals([1, 2, 3]));
    });

    test('list literal with expressions [1 + 2, 3 * 4]', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return [1 + 2, 3 * 4];
}
''');
      expect(result, isA<List>());
      expect(result, equals([3, 12]));
    });

    test('nested list literal [[1, 2], [3, 4]]', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return [[1, 2], [3, 4]];
}
''');
      expect(result, isA<List>());
      final list = result as List;
      expect(list.length, 2);
      expect(list[0], equals([1, 2]));
      expect(list[1], equals([3, 4]));
    });

    test('empty list literal', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return [];
}
''');
      expect(result, isA<List>());
      expect(result, isEmpty);
    });

    test('list with string elements', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return ['hello', 'world'];
}
''');
      expect(result, isA<List>());
      expect(result, equals(['hello', 'world']));
    });

    test('list with mixed typed elements', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return [1, 'two', 3];
}
''');
      expect(result, isA<List>());
      final list = result as List;
      expect(list[0], 1);
      expect(list[1], 'two');
      expect(list[2], 3);
    });

    test('list.length via bridge', () async {
      final result = await _compileAndRunWithHost('''
int main() {
  var list = [1, 2, 3];
  return list.length;
}
''');
      expect(result, equals(3));
    });

    // ── Map literals ──

    test('return map literal', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return {'a': 1};
}
''');
      expect(result, isA<Map>());
      expect(result, equals({'a': 1}));
    });

    test('map literal with multiple entries', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return {'a': 1, 'b': 2, 'c': 3};
}
''');
      expect(result, isA<Map>());
      expect(result, equals({'a': 1, 'b': 2, 'c': 3}));
    });

    test('empty map literal', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return <String, int>{};
}
''');
      expect(result, isA<Map>());
      expect(result, isEmpty);
    });

    test('map.length via bridge', () async {
      final result = await _compileAndRunWithHost('''
int main() {
  var map = {'a': 1, 'b': 2};
  return map.length;
}
''');
      expect(result, equals(2));
    });

    // ── Set literals ──

    test('return set literal', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return {1, 2, 3};
}
''');
      expect(result, isA<Set>());
      expect(result, equals({1, 2, 3}));
    });

    test('empty set literal', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return <int>{};
}
''');
      expect(result, isA<Set>());
      expect(result, isEmpty);
    });

    // ── Constant collections ──

    test('const list literal', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return const [1, 2, 3];
}
''');
      expect(result, isA<List>());
      expect(result, equals([1, 2, 3]));
    });

    test('const map literal', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return const {'a': 1, 'b': 2};
}
''');
      expect(result, isA<Map>());
      expect(result, equals({'a': 1, 'b': 2}));
    });

    test('const set literal', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return const {1, 2, 3};
}
''');
      expect(result, isA<Set>());
      expect(result, equals({1, 2, 3}));
    });

    test('list assigned to variable then returned', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  var x = [10, 20, 30];
  return x;
}
''');
      expect(result, isA<List>());
      expect(result, equals([10, 20, 30]));
    });

    test('map with int keys', () async {
      final result = await _compileAndRunWithHost('''
Object main() {
  return {1: 'one', 2: 'two'};
}
''');
      expect(result, isA<Map>());
      expect(result, equals({1: 'one', 2: 'two'}));
    });
  });
}
