import 'value_stack.dart';

typedef BenchFn = void Function();

class BenchResult {
  final String name;
  final int iterations;
  final Duration elapsed;

  BenchResult(this.name, this.iterations, this.elapsed);

  double get opsPerSec => iterations / (elapsed.inMicroseconds / 1e6);

  @override
  String toString() =>
      '$name: ${opsPerSec.toStringAsFixed(0)} ops/sec '
      '(${elapsed.inMilliseconds}ms for $iterations iterations)';
}

BenchResult runBench(String name, int iterations, BenchFn fn) {
  // Warmup
  fn();
  fn();

  final sw = Stopwatch()..start();
  fn();
  sw.stop();
  return BenchResult(name, iterations, sw.elapsed);
}

BenchResult benchIntArith(int iterations) {
  final vs = ValueStack(16);
  return runBench('int_arith (dual-view)', iterations, () {
    vs.intView[0] = 0;
    for (int i = 0; i < iterations; i++) {
      vs.intView[1] = i;
      vs.intView[2] = vs.intView[1] * 3;
      vs.intView[2] = vs.intView[2] + 1;
      vs.intView[0] = vs.intView[0] + vs.intView[2];
    }
  });
}

BenchResult benchDoubleArith(int iterations) {
  final vs = ValueStack(16);
  return runBench('double_arith (dual-view)', iterations, () {
    vs.doubleView[0] = 0.0;
    for (int i = 0; i < iterations; i++) {
      vs.doubleView[1] = i.toDouble();
      vs.doubleView[2] = vs.doubleView[1] * 3.14;
      vs.doubleView[0] = vs.doubleView[0] + vs.doubleView[2];
    }
  });
}

BenchResult benchBoxedArith(int iterations) {
  final stack = List<Object?>.filled(16, null);
  return runBench('int_arith (boxed)', iterations, () {
    stack[0] = 0;
    for (int i = 0; i < iterations; i++) {
      stack[1] = i;
      stack[2] = (stack[1] as int) * 3;
      stack[2] = (stack[2] as int) + 1;
      stack[0] = (stack[0] as int) + (stack[2] as int);
    }
  });
}

BenchResult benchBoxedDoubleArith(int iterations) {
  final stack = List<Object?>.filled(16, null);
  return runBench('double_arith (boxed)', iterations, () {
    stack[0] = 0.0;
    for (int i = 0; i < iterations; i++) {
      stack[1] = i.toDouble();
      stack[2] = (stack[1] as double) * 3.14;
      stack[0] = (stack[0] as double) + (stack[2] as double);
    }
  });
}

BenchResult benchNativeDoubleArith(int iterations) {
  return runBench('double_arith (native)', iterations, () {
    double sum = 0.0;
    for (int i = 0; i < iterations; i++) {
      sum += i.toDouble() * 3.14;
    }
    if (sum < 0) print(sum);
  });
}

BenchResult benchMixedArith(int iterations) {
  final vs = ValueStack(16);
  return runBench('mixed_arith (dual-view)', iterations, () {
    vs.intView[0] = 0;
    vs.doubleView[2] = 0.0;
    for (int i = 0; i < iterations; i++) {
      vs.intView[1] = i * 3 + 1;
      vs.intView[0] = vs.intView[0] + vs.intView[1];
      vs.doubleView[3] = vs.intView[1].toDouble() * 2.5;
      vs.doubleView[2] = vs.doubleView[2] + vs.doubleView[3];
    }
  });
}

BenchResult benchBoxedMixedArith(int iterations) {
  final stack = List<Object?>.filled(16, null);
  return runBench('mixed_arith (boxed)', iterations, () {
    stack[0] = 0;
    stack[2] = 0.0;
    for (int i = 0; i < iterations; i++) {
      stack[1] = i * 3 + 1;
      stack[0] = (stack[0] as int) + (stack[1] as int);
      stack[3] = (stack[1] as int).toDouble() * 2.5;
      stack[2] = (stack[2] as double) + (stack[3] as double);
    }
  });
}

BenchResult benchNativeArith(int iterations) {
  return runBench('int_arith (native)', iterations, () {
    int sum = 0;
    for (int i = 0; i < iterations; i++) {
      sum += i * 3 + 1;
    }
    // Prevent dead code elimination
    if (sum < 0) print(sum);
  });
}
