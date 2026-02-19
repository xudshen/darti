/// Registers `Error` and `Exception` host bindings for the CALL_HOST pipeline.
///
/// Covers constructors, message getters, and toString for common error types:
/// ArgumentError, RangeError, StateError, UnsupportedError, FormatException,
/// ConcurrentModificationError, StackOverflowError.
///
/// See: docs/design/04-interop.md
library;

import '../host_bindings.dart';

/// Registers all `dart:core` error/exception host function bindings.
abstract final class ErrorBindings {
  static void register(HostBindings bindings) {
    // ── ArgumentError ──
    bindings.register('dart:core::ArgumentError::#1', (args) {
      return ArgumentError(args[0]);
    });
    bindings.register('dart:core::ArgumentError::message#0', (args) {
      return (args[0] as ArgumentError).message;
    });
    bindings.register('dart:core::ArgumentError::toString#0', (args) {
      return (args[0] as ArgumentError).toString();
    });

    // ── RangeError ──
    // RangeError(message)
    bindings.register('dart:core::RangeError::#1', (args) {
      return RangeError(args[0]);
    });
    // RangeError.range(value, min, max, [name, message]) — 5 params
    bindings.register('dart:core::RangeError::range#5', (args) {
      return RangeError.range(
        args[0] as int,
        args[1] as int?,
        args[2] as int?,
        args.length > 3 ? args[3] as String? ?? '' : '',
        args.length > 4 ? args[4] as String? : null,
      );
    });
    bindings.register('dart:core::RangeError::toString#0', (args) {
      return (args[0] as RangeError).toString();
    });

    // ── StateError ──
    bindings.register('dart:core::StateError::#1', (args) {
      return StateError(args[0] as String);
    });
    bindings.register('dart:core::StateError::toString#0', (args) {
      return (args[0] as StateError).toString();
    });
    bindings.register('dart:core::StateError::message#0', (args) {
      return (args[0] as StateError).message;
    });

    // ── UnsupportedError ──
    bindings.register('dart:core::UnsupportedError::#1', (args) {
      return UnsupportedError(args[0] as String);
    });
    bindings.register('dart:core::UnsupportedError::toString#0', (args) {
      return (args[0] as UnsupportedError).toString();
    });
    bindings.register('dart:core::UnsupportedError::message#0', (args) {
      return (args[0] as UnsupportedError).message;
    });

    // ── FormatException ──
    // FormatException([message, source, offset]) — 3 params
    bindings.register('dart:core::FormatException::#3', (args) {
      return FormatException(
        args.isNotEmpty ? args[0] as String? ?? '' : '',
        args.length > 1 ? args[1] : null,
        args.length > 2 ? args[2] as int? : null,
      );
    });
    bindings.register('dart:core::FormatException::message#0', (args) {
      return (args[0] as FormatException).message;
    });
    bindings.register('dart:core::FormatException::toString#0', (args) {
      return (args[0] as FormatException).toString();
    });

    // ── Error base ──
    bindings.register('dart:core::Error::toString#0', (args) {
      return (args[0] as Error).toString();
    });

    // ── Exception base ──
    bindings.register('dart:core::Exception::toString#0', (args) {
      return args[0].toString();
    });

    // ── ConcurrentModificationError ──
    bindings.register('dart:core::ConcurrentModificationError::#1', (args) {
      return ConcurrentModificationError(args.isNotEmpty ? args[0] : null);
    });

    // ── StackOverflowError ──
    bindings.register('dart:core::StackOverflowError::#0', (args) {
      return StackOverflowError();
    });
  }
}
