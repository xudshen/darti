import 'dart:io';
import 'package:darti/src/compiler/simple_compiler.dart';
import 'package:darti/src/runtime/dispatch_loop.dart';
import 'package:darti/src/runtime/host_bindings.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    final result = Process.runSync('fvm', [
      'dart', 'compile', 'kernel',
      '-o', 'test/fixtures/counter.dill',
      'test/fixtures/counter.dart',
    ]);
    if (result.exitCode != 0) {
      // Fallback without fvm
      final result2 = Process.runSync('dart', [
        'compile', 'kernel',
        '-o', 'test/fixtures/counter.dill',
        'test/fixtures/counter.dart',
      ]);
      if (result2.exitCode != 0) {
        throw StateError('Failed to compile fixture: ${result2.stderr}');
      }
    }
  });

  test('compiles and executes counter.dart', () async {
    final printLog = <Object?>[];

    final bindings = HostBindings();
    bindings.register('dart:core::print', (args) {
      printLog.add(args[0]);
      return null;
    });

    final compiler = SimpleCompiler(hostBindings: bindings);
    final module = compiler.compile('test/fixtures/counter.dill');

    final runtime = DartiRuntime(hostBindings: bindings);
    await runtime.execute(module);

    expect(printLog, equals([10, 4]));
  });
}
