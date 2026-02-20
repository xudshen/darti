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
  group('Bridge end-to-end', () {
    test('print(42) calls print without error', () async {
      final (_, output) = await _compileAndCapturePrint('''
void main() {
  print(42);
}
''');
      expect(output, ['42']);
    });

    test('print("hello world") passes string argument', () async {
      final (_, output) = await _compileAndCapturePrint('''
void main() {
  print('hello world');
}
''');
      expect(output, ['hello world']);
    });

    test('42.toString() returns "42"', () async {
      final result = await _compileAndRunWithHost('''
String main() {
  return 42.toString();
}
''');
      expect(result, equals('42'));
    });

    test("'hello'.length returns 5", () async {
      final result = await _compileAndRunWithHost('''
int main() {
  return 'hello'.length;
}
''');
      expect(result, equals(5));
    });

    test('42.toString().length returns 2 (chain)', () async {
      final result = await _compileAndRunWithHost('''
int main() {
  return 42.toString().length;
}
''');
      expect(result, equals(2));
    });

    test('int.toString() on computed value', () async {
      final result = await _compileAndRunWithHost('''
String main() {
  int x = 10 + 32;
  return x.toString();
}
''');
      expect(result, equals('42'));
    });

    test('print with multiple statements', () async {
      final (_, output) = await _compileAndCapturePrint('''
void main() {
  print(1);
  print('two');
  print(3);
}
''');
      expect(output, ['1', 'two', '3']);
    });
  });
}
