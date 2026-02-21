import 'package:dartic_benchmark/src/config.dart';
import 'package:dartic_benchmark/src/reporter.dart';
import 'package:dartic_benchmark/src/runner.dart';
import 'package:dartic_benchmark/suites/macro.dart';
import 'package:dartic_benchmark/suites/micro.dart';

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
