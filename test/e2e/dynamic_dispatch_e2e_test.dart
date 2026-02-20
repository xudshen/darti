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
  group('Dynamic getter dispatch', () {
    test('dynamic String.length', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          dynamic x = 'hello';
          return x.length;
        }
      ''');
      expect(result, equals(5));
    });

    test('dynamic List.length', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          dynamic x = [1, 2, 3];
          return x.length;
        }
      ''');
      expect(result, equals(3));
    });

    test('dynamic List.isEmpty', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          dynamic x = [];
          return x.isEmpty;
        }
      ''');
      expect(result, equals(true));
    });

    test('dynamic Map.length', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          dynamic x = {'a': 1, 'b': 2};
          return x.length;
        }
      ''');
      expect(result, equals(2));
    });
  });

  group('Dynamic method dispatch', () {
    test('dynamic List.contains', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          dynamic x = [1, 2, 3];
          return x.contains(2);
        }
      ''');
      expect(result, equals(true));
    });

    test('dynamic Map.containsKey', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          dynamic x = {'a': 1};
          return x.containsKey('a');
        }
      ''');
      expect(result, equals(true));
    });

    test('dynamic String.substring', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          dynamic x = 'hello world';
          return x.substring(0, 5);
        }
      ''');
      expect(result, equals('hello'));
    });

    test('dynamic String.contains', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          dynamic x = 'hello';
          return x.contains('ell');
        }
      ''');
      expect(result, equals(true));
    });
  });

  group('Dynamic operator dispatch', () {
    test('dynamic List index operator', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          dynamic x = [10, 20, 30];
          return x[1];
        }
      ''');
      expect(result, equals(20));
    });

    test('dynamic Map index operator', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          dynamic x = {'a': 1, 'b': 2};
          return x['b'];
        }
      ''');
      expect(result, equals(2));
    });
  });
}
