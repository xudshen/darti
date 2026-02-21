/// Registers `Error` and `Exception` host bindings for the CALL_HOST pipeline.
///
/// Covers constructors, getters, factories, and toString for error types:
/// Error, ArgumentError, RangeError, IndexError, StateError, UnsupportedError,
/// UnimplementedError, FormatException, AssertionError, TypeError,
/// ConcurrentModificationError, StackOverflowError, NoSuchMethodError,
/// and the Exception factory.
///
/// See: docs/design/04-interop.md
library;

// IndexError's positional constructor is deprecated in favor of
// IndexError.withLength, but the runtime still uses the old form
// (RangeError.index delegates to it). Suppress to keep the binding aligned.
// ignore_for_file: deprecated_member_use

import '../host_function_registry.dart';

/// Registers all `dart:core` error/exception host function bindings.
abstract final class ErrorBindings {
  static void register(HostFunctionRegistry registry) {
    // ── ArgumentError ──
    // Kernel may report 1 or 2 params depending on SDK version (hidden
    // _hasMessage field). Register both variants.
    registry.register('dart:core::ArgumentError::#1', (args) {
      return ArgumentError(args[0]);
    });
    registry.register('dart:core::ArgumentError::#2', (args) {
      return ArgumentError(args[0], args[1] as String?);
    });
    registry.register('dart:core::ArgumentError::message#0', (args) {
      return (args[0] as ArgumentError).message;
    });
    registry.register('dart:core::ArgumentError::toString#0', (args) {
      return (args[0] as ArgumentError).toString();
    });
    registry.register('dart:core::ArgumentError::name#0', (args) {
      return (args[0] as ArgumentError).name;
    });
    registry.register('dart:core::ArgumentError::invalidValue#0', (args) {
      return (args[0] as ArgumentError).invalidValue;
    });
    // ArgumentError.value(value, [name, message]) — 3 params
    registry.register('dart:core::ArgumentError::value#3', (args) {
      return ArgumentError.value(
        args[0],
        args.length > 1 ? args[1] as String? : null,
        args.length > 2 ? args[2] : null,
      );
    });
    // ArgumentError.notNull([name]) — 1 param
    registry.register('dart:core::ArgumentError::notNull#1', (args) {
      return ArgumentError.notNull(args.isNotEmpty ? args[0] as String? : null);
    });

    // ── RangeError ──
    // RangeError(message)
    registry.register('dart:core::RangeError::#1', (args) {
      return RangeError(args[0]);
    });
    // RangeError.range(value, min, max, [name, message]) — 5 params
    registry.register('dart:core::RangeError::range#5', (args) {
      return RangeError.range(
        args[0] as int,
        args[1] as int?,
        args[2] as int?,
        args.length > 3 ? args[3] as String? : null,
        args.length > 4 ? args[4] as String? : null,
      );
    });
    registry.register('dart:core::RangeError::toString#0', (args) {
      return (args[0] as RangeError).toString();
    });
    registry.register('dart:core::RangeError::start#0', (args) {
      return (args[0] as RangeError).start;
    });
    registry.register('dart:core::RangeError::end#0', (args) {
      return (args[0] as RangeError).end;
    });
    // RangeError.value(num value, [String? name, String? message]) — 3 params
    registry.register('dart:core::RangeError::value#3', (args) {
      return RangeError.value(
        args[0] as num,
        args.length > 1 ? args[1] as String? : null,
        args.length > 2 ? args[2] as String? : null,
      );
    });
    // RangeError.index(int index, dynamic indexable, [String? name,
    //   String? message, int? length]) — 5 params
    registry.register('dart:core::RangeError::index#5', (args) {
      return RangeError.index(
        args[0] as int,
        args[1],
        args.length > 2 ? args[2] as String? : null,
        args.length > 3 ? args[3] as String? : null,
        args.length > 4 ? args[4] as int? : null,
      );
    });
    // RangeError.checkValidIndex(int index, dynamic indexable,
    //   [String? name, int? length, String? message]) — 5 params
    registry.register('dart:core::RangeError::checkValidIndex#5', (args) {
      return RangeError.checkValidIndex(
        args[0] as int,
        args[1],
        args.length > 2 ? args[2] as String? : null,
        args.length > 3 ? args[3] as int? : null,
        args.length > 4 ? args[4] as String? : null,
      );
    });
    // RangeError.checkValidRange(int start, int? end, int length,
    //   [String? startName, String? endName, String? message]) — 6 params
    registry.register('dart:core::RangeError::checkValidRange#6', (args) {
      return RangeError.checkValidRange(
        args[0] as int,
        args[1] as int?,
        args[2] as int,
        args.length > 3 ? args[3] as String? : null,
        args.length > 4 ? args[4] as String? : null,
        args.length > 5 ? args[5] as String? : null,
      );
    });
    // RangeError.checkNotNegative(int value, [String? name, String? message])
    //   — 3 params
    registry.register('dart:core::RangeError::checkNotNegative#3', (args) {
      return RangeError.checkNotNegative(
        args[0] as int,
        args.length > 1 ? args[1] as String? : null,
        args.length > 2 ? args[2] as String? : null,
      );
    });

    // ── StateError ──
    registry.register('dart:core::StateError::#1', (args) {
      return StateError(args[0] as String);
    });
    registry.register('dart:core::StateError::toString#0', (args) {
      return (args[0] as StateError).toString();
    });
    registry.register('dart:core::StateError::message#0', (args) {
      return (args[0] as StateError).message;
    });

    // ── UnsupportedError ──
    registry.register('dart:core::UnsupportedError::#1', (args) {
      return UnsupportedError(args[0] as String);
    });
    registry.register('dart:core::UnsupportedError::toString#0', (args) {
      return (args[0] as UnsupportedError).toString();
    });
    registry.register('dart:core::UnsupportedError::message#0', (args) {
      return (args[0] as UnsupportedError).message;
    });

    // ── FormatException ──
    // FormatException([message, source, offset]) — 3 params
    registry.register('dart:core::FormatException::#3', (args) {
      return FormatException(
        args.isNotEmpty ? args[0] as String? ?? '' : '',
        args.length > 1 ? args[1] : null,
        args.length > 2 ? args[2] as int? : null,
      );
    });
    registry.register('dart:core::FormatException::message#0', (args) {
      return (args[0] as FormatException).message;
    });
    registry.register('dart:core::FormatException::toString#0', (args) {
      return (args[0] as FormatException).toString();
    });
    registry.register('dart:core::FormatException::source#0', (args) {
      return (args[0] as FormatException).source;
    });
    registry.register('dart:core::FormatException::offset#0', (args) {
      return (args[0] as FormatException).offset;
    });

    // ── Error base ──
    registry.register('dart:core::Error::toString#0', (args) {
      return (args[0] as Error).toString();
    });
    registry.register('dart:core::Error::stackTrace#0', (args) {
      return (args[0] as Error).stackTrace;
    });

    // ── Exception base ──
    registry.register('dart:core::Exception::toString#0', (args) {
      return args[0].toString();
    });
    // Exception([message]) — factory constructor, 1 param
    registry.register('dart:core::Exception::#1', (args) {
      return Exception(args.isNotEmpty ? args[0] : null);
    });

    // ── ConcurrentModificationError ──
    registry.register('dart:core::ConcurrentModificationError::#1', (args) {
      return ConcurrentModificationError(args.isNotEmpty ? args[0] : null);
    });
    registry.register(
        'dart:core::ConcurrentModificationError::toString#0', (args) {
      return (args[0] as ConcurrentModificationError).toString();
    });

    // ── StackOverflowError ──
    registry.register('dart:core::StackOverflowError::#0', (args) {
      return StackOverflowError();
    });

    // ── UnimplementedError ──
    registry.register('dart:core::UnimplementedError::#1', (args) {
      return UnimplementedError(args.isNotEmpty ? args[0] as String? : null);
    });
    registry.register('dart:core::UnimplementedError::message#0', (args) {
      return (args[0] as UnimplementedError).message;
    });
    registry.register('dart:core::UnimplementedError::toString#0', (args) {
      return (args[0] as UnimplementedError).toString();
    });
    registry.register('dart:core::UnimplementedError::stackTrace#0', (args) {
      return (args[0] as UnimplementedError).stackTrace;
    });

    // ── AssertionError ──
    registry.register('dart:core::AssertionError::#1', (args) {
      return AssertionError(args.isNotEmpty ? args[0] : null);
    });
    registry.register('dart:core::AssertionError::message#0', (args) {
      return (args[0] as AssertionError).message;
    });
    registry.register('dart:core::AssertionError::toString#0', (args) {
      return (args[0] as AssertionError).toString();
    });

    // ── TypeError ──
    // TypeError has no public constructor — only toString
    registry.register('dart:core::TypeError::toString#0', (args) {
      return (args[0] as TypeError).toString();
    });

    // ── IndexError ──
    // IndexError(int invalidValue, dynamic indexable,
    //   [String? name, String? message, int? length]) — 5 params
    registry.register('dart:core::IndexError::#5', (args) {
      return IndexError(
        args[0] as int,
        args[1],
        args.length > 2 ? args[2] as String? : null,
        args.length > 3 ? args[3] as String? : null,
        args.length > 4 ? args[4] as int? : null,
      );
    });
    registry.register('dart:core::IndexError::indexable#0', (args) {
      return (args[0] as IndexError).indexable;
    });
    registry.register('dart:core::IndexError::length#0', (args) {
      return (args[0] as IndexError).length;
    });
    registry.register('dart:core::IndexError::start#0', (args) {
      return (args[0] as IndexError).start;
    });
    registry.register('dart:core::IndexError::end#0', (args) {
      return (args[0] as IndexError).end;
    });
    registry.register('dart:core::IndexError::toString#0', (args) {
      return (args[0] as IndexError).toString();
    });

    // ── NoSuchMethodError ──
    // No public constructor — only toString
    registry.register('dart:core::NoSuchMethodError::toString#0', (args) {
      return (args[0] as NoSuchMethodError).toString();
    });
  }
}
