/// Error thrown when bytecode validation or loading fails.
///
/// See: docs/design/08-sandbox.md "错误分类"
library;

/// Error thrown when bytecode validation or loading fails.
///
/// Collects all validation errors so that a module author can fix them all
/// at once rather than playing whack-a-mole with one-at-a-time reporting.
class DarticLoadError extends Error {
  DarticLoadError(this.errors, {this.modulePath});

  /// List of validation error descriptions.
  final List<String> errors;

  /// Optional path of the module that failed validation.
  final String? modulePath;

  @override
  String toString() =>
      'DarticLoadError: ${errors.length} error(s):\n${errors.join('\n')}';
}
