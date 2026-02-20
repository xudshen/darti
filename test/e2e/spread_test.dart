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
  group('Spread compilation', () {
    test('list spread', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          return [1, ...[2, 3], 4];
        }
      ''');
      expect(result, equals([1, 2, 3, 4]));
    });

    test('map spread', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          return {...{'a': 1}, 'b': 2};
        }
      ''');
      expect(result, equals({'a': 1, 'b': 2}));
    });

    test('collection if', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          return [1, if (true) 2, 3];
        }
      ''');
      expect(result, equals([1, 2, 3]));
    });

    test('collection for', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          return [for (var i = 0; i < 3; i++) i];
        }
      ''');
      expect(result, equals([0, 1, 2]));
    });
  });
}
