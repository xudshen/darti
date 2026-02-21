/// Base error class for dartic runtime errors.
///
/// Thrown for expected runtime errors (stack overflow, type check failure,
/// illegal opcode, etc.). After a DarticError, the runtime instance
/// remains usable.
///
/// See: docs/design/03-execution-engine.md "错误恢复"
class DarticError extends Error {
  DarticError(this.message);

  final String message;

  @override
  String toString() => 'DarticError: $message';
}

/// Internal error indicating an interpreter implementation bug.
///
/// After a DarticInternalError, the runtime instance should be discarded
/// and recreated. Unlike [DarticError], the runtime state may be corrupt.
///
/// See: docs/design/08-sandbox.md "错误分类"
class DarticInternalError extends Error {
  DarticInternalError(this.message, [this.originalException]);

  final String message;
  final Object? originalException;

  @override
  String toString() => 'DarticInternalError: $message'
      '${originalException != null ? ' (caused by: $originalException)' : ''}';
}

/// Thrown when [DarticInterpreter.maxTotalFuel] is exceeded.
///
/// The interpreter has consumed more instructions than the configured
/// cumulative limit. After catching this error, the runtime instance
/// remains usable for subsequent [DarticInterpreter.execute] calls.
class FuelExhaustedError extends DarticError {
  FuelExhaustedError(this.totalConsumed, this.limit)
      : super(
            'Fuel exhausted: consumed $totalConsumed instructions (limit: $limit)');

  /// Total number of instructions consumed before the limit was hit.
  final int totalConsumed;

  /// The configured [DarticInterpreter.maxTotalFuel] limit.
  final int limit;
}

/// Thrown when [DarticInterpreter.executionTimeout] is exceeded.
///
/// The interpreter has run longer than the configured wall-clock time limit.
/// After catching this error, the runtime instance remains usable for
/// subsequent [DarticInterpreter.execute] calls.
class ExecutionTimeoutError extends DarticError {
  ExecutionTimeoutError(this.elapsed, this.limit)
      : super(
            'Execution timeout: ${elapsed.inMilliseconds}ms (limit: ${limit.inMilliseconds}ms)');

  /// The elapsed wall-clock duration when the timeout was detected.
  final Duration elapsed;

  /// The configured [DarticInterpreter.executionTimeout] limit.
  final Duration limit;
}
