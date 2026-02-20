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

/// Like [_compileAndRunWithHost] but captures print output.
Future<(Object?, List<String>)> _compileAndCapturePrint(String source) async {
  final printLog = <String>[];
  final module = await compileDart(source);
  final registry = HostFunctionRegistry();
  CoreBindings.registerAll(registry, printFn: (v) => printLog.add('$v'));
  final interp = DarticInterpreter(hostFunctionRegistry: registry);
  interp.execute(module);
  return (interp.entryResult, printLog);
}

void main() {
  group('callback bridge e2e', () {
    test('forEach invokes callback for each element', () async {
      final (_, prints) = await _compileAndCapturePrint('''
        void main() {
          var list = [1, 2, 3];
          list.forEach((e) {
            print(e);
          });
        }
      ''');
      expect(prints, equals(['1', '2', '3']));
    });

    test('map transforms elements via callback', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          var list = [1, 2, 3];
          return list.map((e) => e * 2).toList();
        }
      ''');
      expect(result, equals([2, 4, 6]));
    });

    test('where filters elements via predicate callback', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          var list = [1, 2, 3, 4, 5];
          return list.where((e) => e > 2).toList();
        }
      ''');
      expect(result, equals([3, 4, 5]));
    });

    test('sort with comparator callback', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          var list = [3, 1, 2];
          list.sort((a, b) => a - b);
          return list;
        }
      ''');
      expect(result, equals([1, 2, 3]));
    });

    test('List.generate with callback', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          return List.generate(4, (i) => i * 10);
        }
      ''');
      expect(result, equals([0, 10, 20, 30]));
    });

    test('fold accumulates via callback', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          var list = [1, 2, 3, 4];
          return list.fold<int>(0, (int sum, int e) => sum + e);
        }
      ''');
      expect(result, equals(10));
    });

    test('any returns true when predicate matches', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          var list = [1, 2, 3];
          return list.any((e) => e > 2);
        }
      ''');
      expect(result, isTrue);
    });

    test('every returns false when predicate fails', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          var list = [1, 2, 3];
          return list.every((e) => e > 0);
        }
      ''');
      expect(result, isTrue);
    });

    test('chained map + where + toList', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          var list = [1, 2, 3, 4, 5];
          return list.map((e) => e * 2).where((e) => e > 4).toList();
        }
      ''');
      expect(result, equals([6, 8, 10]));
    });
  });

  group('host-created collection passed to dartic', () {
    test('String.split returns a host List, dartic reads its length', () async {
      final result = await _compileAndRunWithHost('''
        int main() {
          String s = 'a,b,c';
          List<String> parts = s.split(',');
          return parts.length;
        }
      ''');
      expect(result, equals(3));
    });

    test('String.split result used with indexing', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          String s = 'hello world';
          List<String> parts = s.split(' ');
          return parts[1];
        }
      ''');
      expect(result, equals('world'));
    });

    test('String.split result used with forEach callback', () async {
      final (_, prints) = await _compileAndCapturePrint('''
        void main() {
          String csv = 'x,y,z';
          List<String> parts = csv.split(',');
          parts.forEach((p) {
            print(p);
          });
        }
      ''');
      expect(prints, equals(['x', 'y', 'z']));
    });

    test('String.split result chained with map', () async {
      final result = await _compileAndRunWithHost('''
        Object main() {
          String s = 'ab,cd,ef';
          return s.split(',').map((p) => p.length).toList();
        }
      ''');
      expect(result, equals([2, 2, 2]));
    });
  });
}
