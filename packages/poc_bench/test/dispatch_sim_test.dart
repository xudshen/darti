import 'package:poc_bench/src/value_stack.dart';
import 'package:poc_bench/src/dispatch_sim.dart';
import 'package:test/test.dart';

void main() {
  group('Dispatch simulator', () {
    test('fibonacci correctness for known values', () {
      for (final (n, expected) in [
        (0, 0),
        (1, 1),
        (2, 1),
        (5, 5),
        (10, 55),
        (20, 6765),
      ]) {
        final vs = ValueStack(16);
        final code = fibBytecode(n);
        final result = executeDispatch(code, vs);
        expect(result, equals(expected), reason: 'fib($n)');
      }
    });

    test('nativeFibonacci matches dispatch results', () {
      for (int n = 0; n <= 30; n++) {
        final vs = ValueStack(16);
        final result = executeDispatch(fibBytecode(n), vs);
        expect(result, equals(nativeFibonacci(n)), reason: 'fib($n)');
      }
    });
  });
}
