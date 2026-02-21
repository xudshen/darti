import 'package:test/test.dart';

// We test the async protocol logic by importing the co19_runner library.
// Since the co19_runner.dart is a tool (not a library), we need to test
// the protocol logic via the actual runTest function with real test files.
//
// However, for unit-testing the stdout marker detection and timeout logic,
// we define isolated test helpers here.

/// Represents the async test protocol state.
enum AsyncTestState {
  /// Not an async test (no wait-for-done marker).
  synchronous,

  /// Async test waiting for completion (wait-for-done seen, no success yet).
  waiting,

  /// Async test completed (success marker seen).
  success,
}

/// Analyzes print output to determine async test state.
AsyncTestState analyzeAsyncMarkers(List<String> output) {
  bool hasWaitForDone = false;
  bool hasSuccess = false;

  for (final line in output) {
    if (line.contains('unittest-suite-wait-for-done')) {
      hasWaitForDone = true;
    }
    if (line.contains('unittest-suite-success')) {
      hasSuccess = true;
    }
  }

  if (!hasWaitForDone) return AsyncTestState.synchronous;
  if (hasSuccess) return AsyncTestState.success;
  return AsyncTestState.waiting;
}

void main() {
  group('Async marker analysis', () {
    test('no markers → synchronous', () {
      expect(analyzeAsyncMarkers([]), AsyncTestState.synchronous);
      expect(analyzeAsyncMarkers(['hello', 'world']),
          AsyncTestState.synchronous);
    });

    test('wait-for-done only → waiting', () {
      expect(
          analyzeAsyncMarkers(['unittest-suite-wait-for-done']),
          AsyncTestState.waiting);
    });

    test('wait-for-done + success → success', () {
      expect(
          analyzeAsyncMarkers([
            'unittest-suite-wait-for-done',
            'unittest-suite-success'
          ]),
          AsyncTestState.success);
    });

    test('success without wait-for-done → synchronous (no async detected)', () {
      // If there's no wait-for-done, it's treated as synchronous
      // even if success appears (shouldn't happen in practice)
      expect(
          analyzeAsyncMarkers(['unittest-suite-success']),
          AsyncTestState.synchronous);
    });
  });
}
