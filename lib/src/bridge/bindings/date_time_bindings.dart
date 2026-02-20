/// Registers `DateTime` host bindings for the CALL_HOST pipeline.
///
/// Covers DateTime constructors, named constructors, static methods,
/// instance getters, methods, and operators.
///
/// See: docs/design/04-interop.md
library;

import '../host_function_registry.dart';

/// Registers all `dart:core::DateTime` host function bindings.
abstract final class DateTimeBindings {
  static void register(HostFunctionRegistry registry) {
    // ── Constructors ──

    // DateTime(int year, [int month=1, int day=1, int hour=0, int minute=0,
    //          int second=0, int millisecond=0, int microsecond=0])
    // 8 formal params, 7 optional
    registry.register('dart:core::DateTime::#8', (args) {
      return DateTime(
        args[0] as int,
        args.length > 1 && args[1] != null ? args[1] as int : 1,
        args.length > 2 && args[2] != null ? args[2] as int : 1,
        args.length > 3 && args[3] != null ? args[3] as int : 0,
        args.length > 4 && args[4] != null ? args[4] as int : 0,
        args.length > 5 && args[5] != null ? args[5] as int : 0,
        args.length > 6 && args[6] != null ? args[6] as int : 0,
        args.length > 7 && args[7] != null ? args[7] as int : 0,
      );
    });

    // DateTime.utc(int year, [int month=1, int day=1, int hour=0, int minute=0,
    //              int second=0, int millisecond=0, int microsecond=0])
    registry.register('dart:core::DateTime::utc#8', (args) {
      return DateTime.utc(
        args[0] as int,
        args.length > 1 && args[1] != null ? args[1] as int : 1,
        args.length > 2 && args[2] != null ? args[2] as int : 1,
        args.length > 3 && args[3] != null ? args[3] as int : 0,
        args.length > 4 && args[4] != null ? args[4] as int : 0,
        args.length > 5 && args[5] != null ? args[5] as int : 0,
        args.length > 6 && args[6] != null ? args[6] as int : 0,
        args.length > 7 && args[7] != null ? args[7] as int : 0,
      );
    });

    // DateTime.now()
    registry.register('dart:core::DateTime::now#0', (args) {
      return DateTime.now();
    });

    // DateTime.fromMillisecondsSinceEpoch(int ms, {bool isUtc = false})
    registry.register('dart:core::DateTime::fromMillisecondsSinceEpoch#2',
        (args) {
      final ms = args[0] as int;
      if (args.length > 1 && args[1] != null) {
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: args[1] as bool);
      }
      return DateTime.fromMillisecondsSinceEpoch(ms);
    });

    // DateTime.fromMicrosecondsSinceEpoch(int us, {bool isUtc = false})
    registry.register('dart:core::DateTime::fromMicrosecondsSinceEpoch#2',
        (args) {
      final us = args[0] as int;
      if (args.length > 1 && args[1] != null) {
        return DateTime.fromMicrosecondsSinceEpoch(us, isUtc: args[1] as bool);
      }
      return DateTime.fromMicrosecondsSinceEpoch(us);
    });

    // ── Static methods ──

    registry.register('dart:core::DateTime::parse#1', (args) {
      return DateTime.parse(args[0] as String);
    });

    registry.register('dart:core::DateTime::tryParse#1', (args) {
      return DateTime.tryParse(args[0] as String);
    });

    // ── Getters (symbol #0, receiver in args[0]) ──

    registry.register('dart:core::DateTime::year#0', (args) {
      return (args[0] as DateTime).year;
    });

    registry.register('dart:core::DateTime::month#0', (args) {
      return (args[0] as DateTime).month;
    });

    registry.register('dart:core::DateTime::day#0', (args) {
      return (args[0] as DateTime).day;
    });

    registry.register('dart:core::DateTime::hour#0', (args) {
      return (args[0] as DateTime).hour;
    });

    registry.register('dart:core::DateTime::minute#0', (args) {
      return (args[0] as DateTime).minute;
    });

    registry.register('dart:core::DateTime::second#0', (args) {
      return (args[0] as DateTime).second;
    });

    registry.register('dart:core::DateTime::millisecond#0', (args) {
      return (args[0] as DateTime).millisecond;
    });

    registry.register('dart:core::DateTime::microsecond#0', (args) {
      return (args[0] as DateTime).microsecond;
    });

    registry.register('dart:core::DateTime::weekday#0', (args) {
      return (args[0] as DateTime).weekday;
    });

    registry.register('dart:core::DateTime::isUtc#0', (args) {
      return (args[0] as DateTime).isUtc;
    });

    registry.register('dart:core::DateTime::timeZoneName#0', (args) {
      return (args[0] as DateTime).timeZoneName;
    });

    registry.register('dart:core::DateTime::timeZoneOffset#0', (args) {
      return (args[0] as DateTime).timeZoneOffset;
    });

    registry.register('dart:core::DateTime::millisecondsSinceEpoch#0', (args) {
      return (args[0] as DateTime).millisecondsSinceEpoch;
    });

    registry.register('dart:core::DateTime::microsecondsSinceEpoch#0', (args) {
      return (args[0] as DateTime).microsecondsSinceEpoch;
    });

    registry.register('dart:core::DateTime::hashCode#0', (args) {
      return (args[0] as DateTime).hashCode;
    });

    // ── Methods ──

    registry.register('dart:core::DateTime::add#1', (args) {
      return (args[0] as DateTime).add(args[1] as Duration);
    });

    registry.register('dart:core::DateTime::subtract#1', (args) {
      return (args[0] as DateTime).subtract(args[1] as Duration);
    });

    registry.register('dart:core::DateTime::difference#1', (args) {
      return (args[0] as DateTime).difference(args[1] as DateTime);
    });

    registry.register('dart:core::DateTime::compareTo#1', (args) {
      return (args[0] as DateTime).compareTo(args[1] as DateTime);
    });

    registry.register('dart:core::DateTime::isAfter#1', (args) {
      return (args[0] as DateTime).isAfter(args[1] as DateTime);
    });

    registry.register('dart:core::DateTime::isBefore#1', (args) {
      return (args[0] as DateTime).isBefore(args[1] as DateTime);
    });

    registry.register('dart:core::DateTime::isAtSameMomentAs#1', (args) {
      return (args[0] as DateTime).isAtSameMomentAs(args[1] as DateTime);
    });

    registry.register('dart:core::DateTime::toLocal#0', (args) {
      return (args[0] as DateTime).toLocal();
    });

    registry.register('dart:core::DateTime::toUtc#0', (args) {
      return (args[0] as DateTime).toUtc();
    });

    registry.register('dart:core::DateTime::toIso8601String#0', (args) {
      return (args[0] as DateTime).toIso8601String();
    });

    registry.register('dart:core::DateTime::toString#0', (args) {
      return (args[0] as DateTime).toString();
    });

    // ── Operators ──

    registry.register('dart:core::DateTime::==#1', (args) {
      return args[0] == args[1];
    });
  }
}
