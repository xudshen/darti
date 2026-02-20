import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

Future<Object?> _run(String source) async {
  final module = await compileDart(source);
  final registry = HostFunctionRegistry();
  CoreBindings.registerAll(registry);
  final interp = DarticInterpreter(hostFunctionRegistry: registry);
  interp.execute(module);
  return interp.entryResult;
}

Future<(Object?, List<String>)> _runCapturePrint(String source) async {
  final printLog = <String>[];
  final module = await compileDart(source);
  final registry = HostFunctionRegistry();
  CoreBindings.registerAll(registry, printFn: (v) => printLog.add('$v'));
  final interp = DarticInterpreter(hostFunctionRegistry: registry);
  interp.execute(module);
  return (interp.entryResult, printLog);
}

void main() {
  group('Object bridge', () {
    test('Object().toString()', () async {
      final (_, out) = await _runCapturePrint('''
void main() {
  print(Object().toString());
}
''');
      expect(out.single, startsWith('Instance of'));
    });

    test('Object().hashCode returns int', () async {
      final result = await _run('''
int main() {
  return Object().hashCode;
}
''');
      expect(result, isA<int>());
    });

    test('null.toString() returns "null"', () async {
      final result = await _run('''
String main() {
  return null.toString();
}
''');
      expect(result, 'null');
    });
  });

  group('Type bridge', () {
    test('42.runtimeType.toString() returns "int"', () async {
      final result = await _run('''
String main() {
  return 42.runtimeType.toString();
}
''');
      expect(result, 'int');
    });

    test('"hello".runtimeType.toString() returns "String"', () async {
      final result = await _run('''
String main() {
  return 'hello'.runtimeType.toString();
}
''');
      expect(result, 'String');
    });
  });

  group('identical', () {
    test('identical(null, null) returns true', () async {
      final result = await _run('''
bool main() {
  return identical(null, null);
}
''');
      expect(result, true);
    });

    test('identical(42, 42) returns true', () async {
      final result = await _run('''
bool main() {
  return identical(42, 42);
}
''');
      expect(result, true);
    });
  });
}
