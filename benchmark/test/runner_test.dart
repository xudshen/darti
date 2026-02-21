import 'package:test/test.dart';
import 'package:dartic_benchmark/src/runner.dart';
import 'package:dartic_benchmark/src/config.dart';
import 'package:dartic_benchmark/src/types.dart';

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
    dartEvalSupported: false,
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

    expect(r.host.medianUs, greaterThan(0));
    expect(r.dartic.medianUs, greaterThan(0));
    expect(r.darticRatio, greaterThan(1.0));
    expect(r.dartEval, isNull);

    print('Host: ${r.host.medianUs.toStringAsFixed(2)} µs/iter');
    print('Dartic: ${r.dartic.medianUs.toStringAsFixed(2)} µs/iter');
    print('Ratio: ${r.darticRatio.toStringAsFixed(1)}x');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
