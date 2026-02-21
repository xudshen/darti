import 'dart:io';

import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/compiler/compiler.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:kernel/ast.dart' as ir;
import 'package:kernel/binary/ast_from_binary.dart';
import 'package:dart_eval/dart_eval.dart' as de;
import 'package:dart_eval/dart_eval_bridge.dart' as de_bridge;

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

      try {
        // --- Pre-compile dartic module ---
        final darticModule = await _compileDartic(bc.dartSource);

        // --- Pre-compile dart_eval program (if enabled + supported) ---
        de.Program? dartEvalProgram;
        if (config.enableDartEval && bc.dartEvalSupported) {
          try {
            dartEvalProgram = _compileDartEval(bc.dartSource);
          } catch (e) {
            print('    dart_eval compile FAILED: $e');
          }
        }

        // --- Calibrate iteration count ---
        final hostIters = _calibrate(bc.hostFn);
        final darticIters = _calibrate(
          () => _executeDartic(darticModule),
        );
        int? dartEvalIters;
        if (dartEvalProgram != null) {
          try {
            dartEvalIters = _calibrate(
              () => _executeDartEval(dartEvalProgram!),
            );
          } catch (e) {
            print('    dart_eval calibrate FAILED: $e');
            dartEvalProgram = null;
          }
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
      } catch (e) {
        print('    FAILED: $e');
      }
    }

    return results;
  }

  // ---------------------------------------------------------------------------
  // Compilation
  // ---------------------------------------------------------------------------

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

  de.Program _compileDartEval(String source) {
    final compiler = de.Compiler();
    return compiler.compile({
      'bench': {'main.dart': source},
    });
  }

  // ---------------------------------------------------------------------------
  // Execution
  // ---------------------------------------------------------------------------

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

  Object? _executeDartEval(de.Program program) {
    final runtime = de.Runtime.ofProgram(program);
    final result = runtime.executeLib('package:bench/main.dart', 'main');
    if (result is de_bridge.$Value) {
      return result.$reified;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Measurement
  // ---------------------------------------------------------------------------

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

  void _warmup(Object? Function() fn, int itersPerSample) {
    for (var i = 0; i < config.warmupIterations; i++) {
      fn();
    }
  }

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
