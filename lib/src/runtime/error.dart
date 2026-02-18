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
