import 'package:poc_bench/src/value_stack.dart';
import 'package:poc_bench/src/benchmarks.dart';
import 'package:poc_bench/src/dispatch_sim.dart';

void main() {
  const iterations = 10000000; // 10M
  const runs = 10;

  print('=== POC-2: Value Stack Performance Benchmarks ===\n');
  print('Iterations per run: $iterations');
  print('Runs: $runs (reporting median)\n');

  // Arithmetic benchmarks
  final arithBenches = <String, BenchResult Function()>{
    'int (dual-view)': () => benchIntArith(iterations),
    'int (boxed)': () => benchBoxedArith(iterations),
    'int (native)': () => benchNativeArith(iterations),
    'double (dual-view)': () => benchDoubleArith(iterations),
    'double (boxed)': () => benchBoxedDoubleArith(iterations),
    'double (native)': () => benchNativeDoubleArith(iterations),
    'mixed (dual-view)': () => benchMixedArith(iterations),
    'mixed (boxed)': () => benchBoxedMixedArith(iterations),
  };

  for (final entry in arithBenches.entries) {
    final results = <BenchResult>[];
    for (int i = 0; i < runs; i++) {
      results.add(entry.value());
    }
    results.sort((a, b) => a.elapsed.compareTo(b.elapsed));
    final median = results[runs ~/ 2];
    print(median);
  }

  // Dispatch loop benchmark
  print('\n--- Dispatch Loop (iterative fib) ---\n');
  final fibNs = [20, 30, 35, 40];
  for (final n in fibNs) {
    // Native warmup + measure
    nativeFibonacci(n);
    nativeFibonacci(n);
    final nativeSw = Stopwatch()..start();
    final nativeResult = nativeFibonacci(n);
    nativeSw.stop();

    // Interpreted warmup + measure
    final vsWarm = ValueStack(16);
    executeDispatch(fibBytecode(n), vsWarm);
    executeDispatch(fibBytecode(n), ValueStack(16));
    final vs = ValueStack(16);
    final code = fibBytecode(n);
    final interpSw = Stopwatch()..start();
    final interpResult = executeDispatch(code, vs);
    interpSw.stop();

    print('fib($n) = $nativeResult');
    print('  native:  ${nativeSw.elapsedMicroseconds}us');
    print('  interp:  ${interpSw.elapsedMicroseconds}us');
    if (nativeSw.elapsedMicroseconds > 0) {
      final ratio =
          interpSw.elapsedMicroseconds / nativeSw.elapsedMicroseconds;
      print('  ratio:   ${ratio.toStringAsFixed(1)}x slower');
    }
    if (nativeResult != interpResult) {
      print(
          '  ERROR: results differ! native=$nativeResult interp=$interpResult');
    }
  }

  // Dual-view vs boxed speedup
  print('\n--- Summary ---\n');
  final dualView = benchIntArith(iterations);
  final boxed = benchBoxedArith(iterations);
  final speedup =
      boxed.elapsed.inMicroseconds / dualView.elapsed.inMicroseconds;
  print('Dual-view vs Boxed speedup: ${speedup.toStringAsFixed(1)}x');
}
