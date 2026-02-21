# dartic Performance Benchmark Suite

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a three-channel benchmark suite (host / dartic / dart_eval) that measures and compares execution performance across micro and macro benchmarks.

**Architecture:** Each benchmark case defines a Dart source string (shared by dartic & dart_eval compilers) and a hand-written host function (native baseline). A `BenchmarkRunner` pre-compiles once, then runs warmup + measurement loops with adaptive iteration sizing. Results are reported as a ratio table (dartic/host, dart_eval/host).

**Tech Stack:** Pure Dart (`Stopwatch` timing, no external benchmark framework). `package:dartic` for interpreter, `package:dart_eval` for competitor. `package:test` for infrastructure unit tests.

---

## Directory Layout

`benchmark/` 是独立 Dart package，通过 path dependency 依赖 dartic，自带 dart_eval 依赖。
主项目 pubspec.yaml 不需要任何修改。

```
benchmark/                       # 独立 package: dartic_benchmark
  pubspec.yaml                   # depends on dartic (path: ..) + dart_eval
  analysis_options.yaml
  bin/
    run.dart                     # CLI entry: cd benchmark && fvm dart run bin/run.dart
  lib/
    src/
      types.dart                 # BenchmarkCase, ChannelResult, BenchmarkResult
      config.dart                # BenchmarkConfig
      stats.dart                 # median, mean, stddev, cv
      runner.dart                # BenchmarkRunner (3-channel compile + measure)
      reporter.dart              # ConsoleReporter (formatted table)
      host_functions.dart        # @pragma('vm:never-inline') host baselines
    suites/
      micro.dart                 # microSuites() -> List<BenchmarkCase>
      macro.dart                 # macroSuites() -> List<BenchmarkCase>
  test/
    stats_test.dart              # stats unit tests
    runner_test.dart             # integration: 1 case x 3 channels
```

---

## 决策记录

| 问题 | 决策 | 理由 |
|------|------|------|
| 基准测试框架 | 自建轻量 runner + Stopwatch | 三通道 setup 差异大，benchmark_harness 不够灵活 |
| 统计方法 | median + CV% | 抗 GC 尖峰，比 mean 更可靠 |
| 迭代策略 | 自适应：倍增直到 sample >= 200ms | 不同 benchmark 量级差异大（µs vs ms） |
| dart_eval API | Compiler + Runtime（预编译） | eval() 每次编译，不公平 |
| dartic fuel | 1 << 30 | 默认 50000 不够 fibonacci(30)（~2.7M 操作） |
| Interpreter 复用 | 每次迭代 new DarticInterpreter | 模拟真实使用场景，包含初始化开销 |
| Host 防内联 | @pragma('vm:never-inline') | 防止 JIT 消除整个函数 |
| 测试策略 | 先试后决定 — stats 单测 + runner 集成测试 | 跑通后看是否需要更多测试 |

---

### Task 1: Setup — 独立 benchmark package

**Files:**
- Create: `benchmark/pubspec.yaml`
- Create: `benchmark/analysis_options.yaml`
- Create: `benchmark/bin/run.dart` (empty main)
- Create: `benchmark/lib/src/` (placeholder files)
- Create: `benchmark/lib/suites/` (placeholder files)

**Step 1: Create benchmark/pubspec.yaml**

```yaml
name: dartic_benchmark
description: Performance benchmark suite for dartic interpreter.
publish_to: none

environment:
  sdk: ^3.10.7

dependencies:
  dartic:
    path: ..
  dart_eval: ^0.8.4

dev_dependencies:
  test: ^1.25.6
  lints: ^6.0.0
```

**Step 2: Create benchmark/analysis_options.yaml**

```yaml
include: package:lints/recommended.yaml
```

**Step 3: Run pub get to verify dependencies resolve**

Run: `cd benchmark && fvm dart pub get`
Expected: "Resolving dependencies..." followed by "Got dependencies!"

**Step 4: Create directory scaffold**

`benchmark/bin/run.dart`:
```dart
Future<void> main() async {
  print('dartic benchmark suite — not yet implemented');
}
```

`benchmark/lib/src/types.dart`:
```dart
// Benchmark data types — Task 2.
```

`benchmark/lib/src/config.dart`:
```dart
// Benchmark configuration — Task 2.
```

`benchmark/lib/src/stats.dart`:
```dart
// Statistics functions — Task 2.
```

`benchmark/lib/src/runner.dart`:
```dart
// BenchmarkRunner — Task 3.
```

`benchmark/lib/src/reporter.dart`:
```dart
// ConsoleReporter — Task 4.
```

`benchmark/lib/src/host_functions.dart`:
```dart
// Host baseline functions — Task 5.
```

`benchmark/lib/suites/micro.dart`:
```dart
// Micro benchmark definitions — Task 5.
```

`benchmark/lib/suites/macro.dart`:
```dart
// Macro benchmark definitions — Task 6.
```

**Step 5: Verify scaffold compiles**

Run: `cd benchmark && fvm dart run bin/run.dart`
Expected: prints "dartic benchmark suite — not yet implemented"

**Step 6: Commit**

```bash
git add benchmark/
git commit -m "chore: scaffold benchmark package with dartic + dart_eval dependencies"
```

---

### Task 2: Types + Stats + 单元测试

**Files:**
- Create: `benchmark/src/types.dart`
- Create: `benchmark/src/config.dart`
- Create: `benchmark/src/stats.dart`
- Create: `test/benchmark/stats_test.dart`

**Step 1: Write stats unit tests**

`test/benchmark/stats_test.dart`:
```dart
import 'package:test/test.dart';

import '../../benchmark/src/stats.dart';

void main() {
  group('median', () {
    test('odd count', () {
      expect(median([1, 3, 5, 7, 9]), 5.0);
    });

    test('even count', () {
      expect(median([1, 2, 3, 4]), 2.5);
    });

    test('single element', () {
      expect(median([42]), 42.0);
    });

    test('resists outliers', () {
      // Mean would be 14.0, median is 5.0
      expect(median([4.9, 5.0, 5.0, 5.1, 50.0]), 5.0);
    });
  });

  group('mean', () {
    test('simple', () {
      expect(mean([2, 4, 6]), 4.0);
    });
  });

  group('cv', () {
    test('identical values give 0%', () {
      expect(cv([5, 5, 5, 5]), 0.0);
    });

    test('varied values give positive CV', () {
      expect(cv([1, 2, 3, 4, 5]), greaterThan(0));
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `fvm dart test test/benchmark/stats_test.dart`
Expected: FAIL — `stats.dart` has no exports yet

**Step 3: Implement types + config + stats**

`benchmark/src/config.dart`:
```dart
/// Benchmark run configuration.
class BenchmarkConfig {
  const BenchmarkConfig({
    this.warmupIterations = 500,
    this.sampleCount = 20,
    this.minSampleDurationMs = 200,
    this.enableDartEval = true,
  });

  /// Warmup iterations before measurement (JIT compilation).
  final int warmupIterations;

  /// Number of measurement samples to collect.
  final int sampleCount;

  /// Minimum duration (ms) for each sample to ensure stable timing.
  final int minSampleDurationMs;

  /// Whether to include dart_eval channel.
  final bool enableDartEval;
}
```

`benchmark/src/types.dart`:
```dart
/// A single benchmark case definition.
class BenchmarkCase {
  const BenchmarkCase({
    required this.name,
    required this.category,
    required this.dartSource,
    required this.hostFn,
    this.dartEvalSupported = true,
  });

  /// Display name (e.g. 'fibonacci_30').
  final String name;

  /// Category: 'micro' or 'macro'.
  final String category;

  /// Dart source code with `int main() { ... }` returning a result.
  /// Shared by dartic and dart_eval compilers.
  final String dartSource;

  /// Native host implementation — must produce the same result as dartSource.
  final Object? Function() hostFn;

  /// Whether dart_eval supports this benchmark's language features.
  final bool dartEvalSupported;
}

/// Timing result for a single channel on a single benchmark.
class ChannelResult {
  const ChannelResult({
    required this.medianUs,
    required this.meanUs,
    required this.cvPct,
    required this.samples,
    required this.iterationsPerSample,
  });

  /// Median per-iteration time in microseconds.
  final double medianUs;

  /// Mean per-iteration time in microseconds.
  final double meanUs;

  /// Coefficient of variation (%).
  final double cvPct;

  /// Raw per-iteration sample times (µs), sorted.
  final List<double> samples;

  /// How many iterations were packed into each sample.
  final int iterationsPerSample;
}

/// Result of running one benchmark case across all channels.
class BenchmarkResult {
  const BenchmarkResult({
    required this.name,
    required this.category,
    required this.host,
    required this.dartic,
    this.dartEval,
  });

  final String name;
  final String category;
  final ChannelResult host;
  final ChannelResult dartic;
  final ChannelResult? dartEval;

  /// dartic / host ratio (lower = better for dartic).
  double get darticRatio => dartic.medianUs / host.medianUs;

  /// dart_eval / host ratio.
  double? get dartEvalRatio =>
      dartEval != null ? dartEval!.medianUs / host.medianUs : null;
}
```

`benchmark/src/stats.dart`:
```dart
import 'dart:math' as math;

/// Returns the median of a sorted list of doubles.
///
/// For even-length lists, returns the average of the two middle values.
double median(List<double> data) {
  final sorted = [...data]..sort();
  final n = sorted.length;
  if (n.isOdd) return sorted[n ~/ 2];
  return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// Arithmetic mean.
double mean(List<double> data) {
  var sum = 0.0;
  for (final v in data) {
    sum += v;
  }
  return sum / data.length;
}

/// Population standard deviation.
double stddev(List<double> data) {
  final m = mean(data);
  var sumSq = 0.0;
  for (final v in data) {
    sumSq += (v - m) * (v - m);
  }
  return math.sqrt(sumSq / data.length);
}

/// Coefficient of variation (%).
double cv(List<double> data) {
  final m = mean(data);
  if (m == 0) return 0;
  return stddev(data) / m * 100;
}
```

**Step 4: Run test to verify it passes**

Run: `fvm dart test test/benchmark/stats_test.dart`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add benchmark/src/types.dart benchmark/src/config.dart benchmark/src/stats.dart test/benchmark/stats_test.dart
git commit -m "feat(benchmark): add types, config, and statistics module with tests"
```

---

### Task 3: BenchmarkRunner — host + dartic 通道

**Files:**
- Create: `benchmark/src/runner.dart`
- Create: `test/benchmark/runner_test.dart`

**依赖:** Task 2 (types, stats)

**Step 1: Write runner integration test**

`test/benchmark/runner_test.dart`:
```dart
import 'package:test/test.dart';

import '../../benchmark/src/runner.dart';
import '../../benchmark/src/config.dart';
import '../../benchmark/src/types.dart';

@pragma('vm:never-inline')
Object? _hostAdd() {
  int sum = 0;
  for (int i = 0; i < 1000; i++) {
    sum += i;
  }
  return sum;
}

void main() {
  const source = '''
int main() {
  int sum = 0;
  for (int i = 0; i < 1000; i++) {
    sum = sum + i;
  }
  return sum;
}
''';

  final benchCase = BenchmarkCase(
    name: 'test_loop_sum',
    category: 'micro',
    dartSource: source,
    hostFn: _hostAdd,
    dartEvalSupported: false, // test without dart_eval first
  );

  const config = BenchmarkConfig(
    warmupIterations: 50,
    sampleCount: 5,
    minSampleDurationMs: 50,
    enableDartEval: false,
  );

  test('BenchmarkRunner produces valid results for host + dartic', () async {
    final runner = BenchmarkRunner(config: config);
    final results = await runner.runAll([benchCase]);

    expect(results, hasLength(1));
    final r = results.first;

    // Host and dartic both compute 0+1+...+999 = 499500.
    // Verify timing is positive and dartic is slower than host.
    expect(r.host.medianUs, greaterThan(0));
    expect(r.dartic.medianUs, greaterThan(0));
    expect(r.darticRatio, greaterThan(1.0));
    expect(r.dartEval, isNull);

    print('Host: ${r.host.medianUs.toStringAsFixed(2)} µs/iter');
    print('Dartic: ${r.dartic.medianUs.toStringAsFixed(2)} µs/iter');
    print('Ratio: ${r.darticRatio.toStringAsFixed(1)}x');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
```

**Step 2: Run test to verify it fails**

Run: `fvm dart test test/benchmark/runner_test.dart`
Expected: FAIL — `runner.dart` has no BenchmarkRunner

**Step 3: Implement BenchmarkRunner with host + dartic channels**

`benchmark/src/runner.dart`:
```dart
import 'dart:io';

import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/compiler/compiler.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:kernel/ast.dart' as ir;
import 'package:kernel/binary/ast_from_binary.dart';

import 'config.dart';
import 'stats.dart';
import 'types.dart';

/// Three-channel benchmark runner: host / dartic / dart_eval.
class BenchmarkRunner {
  BenchmarkRunner({this.config = const BenchmarkConfig()});

  final BenchmarkConfig config;

  /// Runs all benchmark cases and returns results.
  Future<List<BenchmarkResult>> runAll(List<BenchmarkCase> cases) async {
    final results = <BenchmarkResult>[];

    for (final bc in cases) {
      print('  ${bc.name} ...');

      // --- Pre-compile dartic module ---
      final darticModule = await _compileDartic(bc.dartSource);

      // --- Pre-compile dart_eval program (if enabled + supported) ---
      Object? dartEvalProgram;
      if (config.enableDartEval && bc.dartEvalSupported) {
        dartEvalProgram = await _compileDartEval(bc.dartSource);
      }

      // --- Calibrate iteration count ---
      final hostIters = _calibrate(bc.hostFn);
      final darticIters = _calibrate(
        () => _executeDartic(darticModule),
      );
      int? dartEvalIters;
      if (dartEvalProgram != null) {
        dartEvalIters = _calibrate(
          () => _executeDartEval(dartEvalProgram!),
        );
      }

      // --- Warmup ---
      _warmup(bc.hostFn, hostIters);
      _warmup(() => _executeDartic(darticModule), darticIters);
      if (dartEvalProgram != null) {
        _warmup(() => _executeDartEval(dartEvalProgram!), dartEvalIters!);
      }

      // --- Measure ---
      final hostResult = _measure(bc.hostFn, hostIters);
      final darticResult = _measure(
        () => _executeDartic(darticModule),
        darticIters,
      );
      ChannelResult? dartEvalResult;
      if (dartEvalProgram != null) {
        dartEvalResult = _measure(
          () => _executeDartEval(dartEvalProgram!),
          dartEvalIters!,
        );
      }

      results.add(BenchmarkResult(
        name: bc.name,
        category: bc.category,
        host: hostResult,
        dartic: darticResult,
        dartEval: dartEvalResult,
      ));
    }

    return results;
  }

  // ---------------------------------------------------------------------------
  // Compilation
  // ---------------------------------------------------------------------------

  /// Compiles Dart source → DarticModule via CFE + DarticCompiler.
  Future<DarticModule> _compileDartic(String source) async {
    final dir = await Directory.systemTemp.createTemp('dartic_bench_');
    try {
      final dartFile = File('${dir.path}/input.dart');
      await dartFile.writeAsString(source);

      final dillPath = '${dir.path}/input.dill';
      final result = await Process.run(
        'fvm',
        ['dart', 'compile', 'kernel', dartFile.path, '-o', dillPath],
      );
      if (result.exitCode != 0) {
        throw StateError(
          'Failed to compile .dill:\n'
          'stdout: ${result.stdout}\nstderr: ${result.stderr}',
        );
      }

      final bytes = File(dillPath).readAsBytesSync();
      final component = ir.Component();
      BinaryBuilder(bytes).readComponent(component);
      return DarticCompiler(component).compile();
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// Compiles Dart source via dart_eval Compiler.
  /// Returns the compiled program (dynamic to avoid hard import dependency).
  Future<Object> _compileDartEval(String source) async {
    // Lazy-import dart_eval to keep it optional.
    final program = _dartEvalCompile(source);
    return program;
  }

  // ---------------------------------------------------------------------------
  // Execution
  // ---------------------------------------------------------------------------

  /// Executes a pre-compiled DarticModule once and returns the result.
  Object? _executeDartic(DarticModule module) {
    final registry = HostFunctionRegistry();
    CoreBindings.registerAll(registry);
    final interp = DarticInterpreter(
      hostFunctionRegistry: registry,
      fuelBudget: 1 << 30,
    );
    interp.execute(module);
    return interp.entryResult;
  }

  /// Executes a pre-compiled dart_eval program once.
  Object? _executeDartEval(Object program) {
    return _dartEvalExecute(program);
  }

  // ---------------------------------------------------------------------------
  // Measurement
  // ---------------------------------------------------------------------------

  /// Finds the iteration count so that one sample takes >= minSampleDurationMs.
  int _calibrate(Object? Function() fn) {
    var iters = 1;
    while (true) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < iters; i++) {
        fn();
      }
      sw.stop();
      if (sw.elapsedMilliseconds >= config.minSampleDurationMs) return iters;
      iters *= 2;
    }
  }

  /// Runs warmup iterations.
  void _warmup(Object? Function() fn, int itersPerSample) {
    final total = config.warmupIterations;
    for (var i = 0; i < total; i++) {
      fn();
    }
  }

  /// Collects [sampleCount] samples, each running [iters] iterations.
  /// Returns a [ChannelResult] with per-iteration µs statistics.
  ChannelResult _measure(Object? Function() fn, int iters) {
    final samples = <double>[];
    for (var s = 0; s < config.sampleCount; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < iters; i++) {
        fn();
      }
      sw.stop();
      samples.add(sw.elapsedMicroseconds / iters);
    }
    samples.sort();
    return ChannelResult(
      medianUs: median(samples),
      meanUs: mean(samples),
      cvPct: cv(samples),
      samples: samples,
      iterationsPerSample: iters,
    );
  }
}

// =============================================================================
// dart_eval helpers — isolated to contain the import
// =============================================================================

// ignore: depend_on_referenced_packages
import 'package:dart_eval/dart_eval.dart' as de;

Object _dartEvalCompile(String source) {
  final compiler = de.Compiler();
  return compiler.compile({
    'bench': {'main.dart': source},
  });
}

Object? _dartEvalExecute(Object program) {
  final runtime = de.Runtime.ofProgram(program as de.Program);
  final result = runtime.executeLib('package:bench/main.dart', 'main');
  return (result as de.$Value?)?.$value;
}
```

**Step 4: Run test to verify it passes**

Run: `fvm dart test test/benchmark/runner_test.dart`
Expected: PASS — host + dartic channels produce timing data, dartic is slower than host

**Step 5: 验证正确性 — host 与 dartic 结果一致**

在 runner_test.dart 中，两个通道执行同一段 `0+1+...+999` 代码，都应该返回 499500。如果 darticRatio > 1.0，说明 dartic 更慢（符合预期）。如果 ratio 出现 < 1.0 或 NaN，则可能是编译或执行有 bug。

**Step 6: Commit**

```bash
git add benchmark/src/runner.dart test/benchmark/runner_test.dart
git commit -m "feat(benchmark): BenchmarkRunner with host + dartic + dart_eval channels"
```

---

### Task 4: ConsoleReporter

**Files:**
- Create: `benchmark/src/reporter.dart`

**依赖:** Task 2 (types)

**Step 1: Implement ConsoleReporter**

`benchmark/src/reporter.dart`:
```dart
import 'types.dart';

/// Formats benchmark results as a terminal table.
class ConsoleReporter {
  void report(List<BenchmarkResult> results, {bool showDartEval = true}) {
    final hasDartEval = showDartEval &&
        results.any((r) => r.dartEval != null);

    _printHeader(hasDartEval);

    String? lastCategory;
    for (final r in results) {
      if (r.category != lastCategory) {
        if (lastCategory != null) stdout.writeln();
        _printCategoryHeader(r.category, hasDartEval);
        lastCategory = r.category;
      }
      _printRow(r, hasDartEval);
    }

    _printFooter(hasDartEval);
  }

  void _printHeader(bool hasDartEval) {
    final width = hasDartEval ? 95 : 62;
    stdout.writeln();
    stdout.writeln('${"=" * width}');
    stdout.writeln(
      '  dartic Performance Benchmark Suite  '
      '(${DateTime.now().toIso8601String().substring(0, 10)})',
    );
    stdout.writeln('${"=" * width}');
  }

  void _printCategoryHeader(String category, bool hasDartEval) {
    final label = category.toUpperCase();
    stdout.writeln();
    stdout.writeln('$label BENCHMARKS');
    final sep = hasDartEval
        ? '${"─" * 20}┼${"─" * 13}┼${"─" * 13}┼${"─" * 16}┼${"─" * 11}┼${"─" * 11}'
        : '${"─" * 20}┼${"─" * 13}┼${"─" * 13}┼${"─" * 11}';
    final header = hasDartEval
        ? '${"Benchmark".padRight(20)}│ ${"Host (µs)".padLeft(11)} │ ${"dartic (µs)".padLeft(11)} │ ${"dart_eval (µs)".padLeft(14)} │ ${"d/h".padLeft(9)} │ ${"de/h".padLeft(9)}'
        : '${"Benchmark".padRight(20)}│ ${"Host (µs)".padLeft(11)} │ ${"dartic (µs)".padLeft(11)} │ ${"d/h".padLeft(9)}';
    stdout.writeln(header);
    stdout.writeln(sep);
  }

  void _printRow(BenchmarkResult r, bool hasDartEval) {
    final name = r.name.padRight(20);
    final host = _fmtUs(r.host.medianUs).padLeft(11);
    final dartic = _fmtUs(r.dartic.medianUs).padLeft(11);
    final dRatio = '${r.darticRatio.toStringAsFixed(1)}x'.padLeft(9);

    if (hasDartEval) {
      final de = r.dartEval != null
          ? _fmtUs(r.dartEval!.medianUs).padLeft(14)
          : 'N/A'.padLeft(14);
      final deRatio = r.dartEvalRatio != null
          ? '${r.dartEvalRatio!.toStringAsFixed(1)}x'.padLeft(9)
          : 'N/A'.padLeft(9);
      stdout.writeln('$name│ $host │ $dartic │ $de │ $dRatio │ $deRatio');
    } else {
      stdout.writeln('$name│ $host │ $dartic │ $dRatio');
    }
  }

  void _printFooter(bool hasDartEval) {
    stdout.writeln();
    stdout.writeln('  d/h  = dartic / host  (lower is better)');
    if (hasDartEval) {
      stdout.writeln('  de/h = dart_eval / host  (lower is better)');
    }
    final width = hasDartEval ? 95 : 62;
    stdout.writeln('${"=" * width}');
  }

  String _fmtUs(double us) {
    if (us >= 1000000) return '${(us / 1000000).toStringAsFixed(1)}s';
    if (us >= 1000) return '${(us / 1000).toStringAsFixed(1)}ms';
    return '${us.toStringAsFixed(1)}';
  }
}

// Use dart:io for stdout.
import 'dart:io';
```

**Step 2: Verify it compiles**

Run: `fvm dart analyze benchmark/src/reporter.dart`
Expected: No errors

**Step 3: Commit**

```bash
git add benchmark/src/reporter.dart
git commit -m "feat(benchmark): ConsoleReporter with formatted table output"
```

---

### Task 5: Micro 基准测试套件

**Files:**
- Create: `benchmark/src/host_functions.dart`
- Create: `benchmark/suites/micro.dart`

**依赖:** Task 2 (types)

**Step 1: Implement host baseline functions**

`benchmark/src/host_functions.dart`:
```dart
// Host baseline implementations for all benchmarks.
// Every function uses @pragma('vm:never-inline') to prevent JIT elimination.

// ---------------------------------------------------------------------------
// Micro
// ---------------------------------------------------------------------------

@pragma('vm:never-inline')
Object? hostIntArithmetic() {
  int sum = 0;
  for (int i = 0; i < 10000; i++) {
    sum = sum + i * 3 - i ~/ 2;
  }
  return sum;
}

@pragma('vm:never-inline')
Object? hostDoubleArithmetic() {
  double sum = 0.0;
  for (int i = 0; i < 10000; i++) {
    sum = sum + i * 3.14 - i / 2.0;
  }
  return sum.floor();
}

@pragma('vm:never-inline')
Object? hostLoopSum() {
  int sum = 0;
  for (int i = 0; i < 100000; i++) {
    sum += i;
  }
  return sum;
}

@pragma('vm:never-inline')
Object? hostFunctionCall() {
  return _fibHost(20);
}

int _fibHost(int n) {
  if (n <= 1) return n;
  return _fibHost(n - 1) + _fibHost(n - 2);
}

@pragma('vm:never-inline')
Object? hostMethodDispatch() {
  Animal a = Dog();
  int sum = 0;
  for (int i = 0; i < 10000; i++) {
    sum += a.speak();
    if (i % 2 == 0) {
      a = Cat();
    } else {
      a = Dog();
    }
  }
  return sum;
}

abstract class Animal {
  int speak();
}

class Dog extends Animal {
  @override
  int speak() => 1;
}

class Cat extends Animal {
  @override
  int speak() => 2;
}

// ---------------------------------------------------------------------------
// Macro
// ---------------------------------------------------------------------------

@pragma('vm:never-inline')
Object? hostFibonacci30() {
  return _fibHost(30);
}

@pragma('vm:never-inline')
Object? hostFibonacciIter() {
  int a = 0, b = 1;
  for (int i = 0; i < 10000; i++) {
    final t = a + b;
    a = b;
    b = t;
  }
  return a;
}

@pragma('vm:never-inline')
Object? hostQuicksort() {
  final list = List.generate(1000, (i) => (i * 7 + 13) % 1000);
  _qsort(list, 0, list.length - 1);
  return list[500];
}

void _qsort(List<int> a, int lo, int hi) {
  if (lo >= hi) return;
  final pivot = a[(lo + hi) ~/ 2];
  int i = lo, j = hi;
  while (i <= j) {
    while (a[i] < pivot) i++;
    while (a[j] > pivot) j--;
    if (i <= j) {
      final t = a[i];
      a[i] = a[j];
      a[j] = t;
      i++;
      j--;
    }
  }
  _qsort(a, lo, j);
  _qsort(a, i, hi);
}

@pragma('vm:never-inline')
Object? hostBinaryTree() {
  final tree = _buildTree(15, 0);
  return _sumTree(tree);
}

({Object? left, Object? right, int value}) _buildTree(int depth, int val) {
  if (depth == 0) return (left: null, right: null, value: val);
  return (
    left: _buildTree(depth - 1, val * 2 + 1),
    right: _buildTree(depth - 1, val * 2 + 2),
    value: val,
  );
}

int _sumTree(Object? node) {
  if (node == null) return 0;
  final n = node as ({Object? left, Object? right, int value});
  return n.value + _sumTree(n.left) + _sumTree(n.right);
}
```

**Step 2: Implement micro benchmark definitions**

`benchmark/suites/micro.dart`:
```dart
import '../src/host_functions.dart';
import '../src/types.dart';

List<BenchmarkCase> microSuites() => [
  BenchmarkCase(
    name: 'int_arithmetic',
    category: 'micro',
    hostFn: hostIntArithmetic,
    dartSource: '''
int main() {
  int sum = 0;
  for (int i = 0; i < 10000; i++) {
    sum = sum + i * 3 - i ~/ 2;
  }
  return sum;
}
''',
  ),

  BenchmarkCase(
    name: 'double_arithmetic',
    category: 'micro',
    hostFn: hostDoubleArithmetic,
    dartSource: '''
int main() {
  double sum = 0.0;
  for (int i = 0; i < 10000; i++) {
    sum = sum + i * 3.14 - i / 2.0;
  }
  return sum.floor();
}
''',
    dartEvalSupported: false, // dart_eval double support is limited
  ),

  BenchmarkCase(
    name: 'loop_sum_100k',
    category: 'micro',
    hostFn: hostLoopSum,
    dartSource: '''
int main() {
  int sum = 0;
  for (int i = 0; i < 100000; i++) {
    sum = sum + i;
  }
  return sum;
}
''',
  ),

  BenchmarkCase(
    name: 'function_call',
    category: 'micro',
    hostFn: hostFunctionCall,
    dartSource: '''
int fibonacci(int n) {
  if (n <= 1) return n;
  return fibonacci(n - 1) + fibonacci(n - 2);
}
int main() => fibonacci(20);
''',
  ),

  BenchmarkCase(
    name: 'method_dispatch',
    category: 'micro',
    hostFn: hostMethodDispatch,
    dartSource: '''
abstract class Animal {
  int speak();
}
class Dog extends Animal {
  int speak() => 1;
}
class Cat extends Animal {
  int speak() => 2;
}
int main() {
  Animal a = Dog();
  int sum = 0;
  for (int i = 0; i < 10000; i++) {
    sum = sum + a.speak();
    if (i % 2 == 0) {
      a = Cat();
    } else {
      a = Dog();
    }
  }
  return sum;
}
''',
    dartEvalSupported: false, // dart_eval abstract class support is flaky
  ),
];
```

**Step 3: Verify definitions compile**

Run: `fvm dart analyze benchmark/suites/micro.dart`
Expected: No errors

**Step 4: Commit**

```bash
git add benchmark/src/host_functions.dart benchmark/suites/micro.dart
git commit -m "feat(benchmark): micro benchmark suites — arithmetic, loops, function calls, dispatch"
```

---

### Task 6: Macro 基准测试套件

**Files:**
- Create: `benchmark/suites/macro.dart`

**依赖:** Task 5 (host_functions)

**Step 1: Implement macro benchmark definitions**

`benchmark/suites/macro.dart`:
```dart
import '../src/host_functions.dart';
import '../src/types.dart';

List<BenchmarkCase> macroSuites() => [
  BenchmarkCase(
    name: 'fibonacci_30',
    category: 'macro',
    hostFn: hostFibonacci30,
    dartSource: '''
int fibonacci(int n) {
  if (n <= 1) return n;
  return fibonacci(n - 1) + fibonacci(n - 2);
}
int main() => fibonacci(30);
''',
  ),

  BenchmarkCase(
    name: 'fibonacci_iter',
    category: 'macro',
    hostFn: hostFibonacciIter,
    dartSource: '''
int main() {
  int a = 0;
  int b = 1;
  for (int i = 0; i < 10000; i++) {
    int t = a + b;
    a = b;
    b = t;
  }
  return a;
}
''',
  ),

  BenchmarkCase(
    name: 'quicksort_1k',
    category: 'macro',
    hostFn: hostQuicksort,
    dartEvalSupported: false, // dart_eval List.generate not available
    dartSource: '''
void qsort(List<int> a, int lo, int hi) {
  if (lo >= hi) return;
  int pivot = a[(lo + hi) ~/ 2];
  int i = lo;
  int j = hi;
  while (i <= j) {
    while (a[i] < pivot) { i = i + 1; }
    while (a[j] > pivot) { j = j - 1; }
    if (i <= j) {
      int t = a[i];
      a[i] = a[j];
      a[j] = t;
      i = i + 1;
      j = j - 1;
    }
  }
  qsort(a, lo, j);
  qsort(a, i, hi);
}

int main() {
  List<int> list = [];
  for (int i = 0; i < 1000; i++) {
    list.add((i * 7 + 13) % 1000);
  }
  qsort(list, 0, list.length - 1);
  return list[500];
}
''',
  ),

  BenchmarkCase(
    name: 'binary_tree_15',
    category: 'macro',
    hostFn: hostBinaryTree,
    dartEvalSupported: false, // dart_eval class support too limited
    dartSource: '''
class Node {
  Node? left;
  Node? right;
  int value;
  Node(this.value, this.left, this.right);
}

Node buildTree(int depth, int val) {
  if (depth == 0) return Node(val, null, null);
  return Node(val, buildTree(depth - 1, val * 2 + 1), buildTree(depth - 1, val * 2 + 2));
}

int sumTree(Node? node) {
  if (node == null) return 0;
  return node.value + sumTree(node.left) + sumTree(node.right);
}

int main() {
  Node tree = buildTree(15, 0);
  return sumTree(tree);
}
''',
  ),
];
```

**Step 2: Verify definitions compile**

Run: `fvm dart analyze benchmark/suites/macro.dart`
Expected: No errors

**Step 3: Commit**

```bash
git add benchmark/suites/macro.dart
git commit -m "feat(benchmark): macro benchmark suites — fibonacci, quicksort, binary tree"
```

---

### Task 7: CLI 入口 + 端到端验证

**Files:**
- Modify: `benchmark/run.dart`

**依赖:** Task 3, 4, 5, 6

**Step 1: Implement CLI entry point**

`benchmark/run.dart`:
```dart
import 'src/config.dart';
import 'src/reporter.dart';
import 'src/runner.dart';
import 'suites/macro.dart';
import 'suites/micro.dart';

Future<void> main(List<String> args) async {
  final enableDartEval = !args.contains('--no-dart-eval');
  final quickMode = args.contains('--quick');

  final config = quickMode
      ? BenchmarkConfig(
          warmupIterations: 100,
          sampleCount: 5,
          minSampleDurationMs: 100,
          enableDartEval: enableDartEval,
        )
      : BenchmarkConfig(enableDartEval: enableDartEval);

  print('Compiling and running benchmarks...');
  if (quickMode) print('(quick mode: fewer warmup iterations + samples)');
  if (!enableDartEval) print('(dart_eval disabled)');

  final runner = BenchmarkRunner(config: config);
  final cases = [...microSuites(), ...macroSuites()];
  final results = await runner.runAll(cases);

  ConsoleReporter().report(results, showDartEval: enableDartEval);
}
```

**Step 2: Run end-to-end in quick mode without dart_eval**

Run: `fvm dart run benchmark/run.dart --quick --no-dart-eval`
Expected: Table output with Host and dartic columns, all ratios > 1.0

**Step 3: Run with dart_eval (if supported benchmarks exist)**

Run: `fvm dart run benchmark/run.dart --quick`
Expected: Table output with dart_eval column for supported benchmarks, N/A for others

**Step 4: 验证所有 benchmark 的 dartic 结果正确性**

在每个 benchmark case 的 dartSource 中，`main()` 返回一个 int 结果。可以在 runner_test.dart 中增加断言：

- `int_arithmetic`: `sum = sum + i*3 - i~/2` for i=0..9999
- `loop_sum_100k`: 0+1+...+99999 = 4999950000
- `function_call`: fibonacci(20) = 6765
- `fibonacci_30`: fibonacci(30) = 832040

如果某个 benchmark 的 dartic 结果与 host 不一致，说明 dartic 解释器有 bug（这本身也是性能测试的价值之一：验证正确性）。

**Step 5: Commit**

```bash
git add benchmark/run.dart
git commit -m "feat(benchmark): CLI entry point with --quick and --no-dart-eval flags"
```

---

### Task 8: 更新文档 + 最终提交

**Files:**
- Modify: `docs/tasks/overview.md` — 添加 Benchmark 条目

**Step 1: 在 overview.md 末尾添加 Benchmark 部分**

在文件末尾 Phase 7 之后添加：

```markdown
---

## 基础设施：Performance Benchmark Suite

**目标：** 三通道性能基准测试（host / dartic / dart_eval），量化 dartic 在性能谱系中的位置

**目录：** `benchmark/`

| 组件 | 文件 | 状态 |
|------|------|------|
| Runner 框架 | `benchmark/src/runner.dart` | ✅ |
| 统计模块 | `benchmark/src/stats.dart` | ✅ |
| Console 报告 | `benchmark/src/reporter.dart` | ✅ |
| Micro 套件 | `benchmark/suites/micro.dart` | ✅ |
| Macro 套件 | `benchmark/suites/macro.dart` | ✅ |

**运行:** `fvm dart run benchmark/run.dart [--quick] [--no-dart-eval]`
```

**Step 2: Commit**

```bash
git add docs/tasks/overview.md
git commit -m "docs: add benchmark suite to task overview"
```

**Step 3: 运行完整 benchmark 并记录基线数据**

Run: `fvm dart run benchmark/run.dart`

记录输出作为 dartic 当前版本的性能基线。后续每个 Phase 结束后重新运行，追踪性能变化。

---

## 后续扩展（不在本计划范围内）

| 扩展 | 说明 | 触发条件 |
|------|------|---------|
| JSON reporter | CI 集成，自动检测性能退化 | 接入 CI 时 |
| AOT 模式对比 | `dart compile exe` 编译后运行 | 需要模拟 Flutter release 时 |
| 更多 micro 套件 | closure_create, string_concat, list_build, type_check, generic_ops | 需要定位具体瓶颈时 |
| Flame chart 可视化 | 生成 SVG/HTML 性能分布图 | 对外展示时 |
| 编译时间对比 | 单独测量 CFE + DarticCompiler vs dart_eval Compiler 编译耗时 | 需要优化编译管线时 |
