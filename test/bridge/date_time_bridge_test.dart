import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  late HostFunctionRegistry registry;

  setUp(() {
    registry = HostFunctionRegistry();
    CoreBindings.registerAll(registry);
  });

  Object? invoke(String name, List<Object?> args) {
    final id = registry.lookupByName(name);
    if (id == -1) fail('Binding not found: $name');
    return registry.invoke(id, args);
  }

  // ── Registration ──

  group('registration', () {
    test('all expected bindings are registered', () {
      final expectedNames = [
        'dart:core::DateTime::#8',
        'dart:core::DateTime::utc#8',
        'dart:core::DateTime::now#0',
        'dart:core::DateTime::fromMillisecondsSinceEpoch#2',
        'dart:core::DateTime::fromMicrosecondsSinceEpoch#2',
        'dart:core::DateTime::parse#1',
        'dart:core::DateTime::tryParse#1',
        'dart:core::DateTime::year#0',
        'dart:core::DateTime::month#0',
        'dart:core::DateTime::day#0',
        'dart:core::DateTime::hour#0',
        'dart:core::DateTime::minute#0',
        'dart:core::DateTime::second#0',
        'dart:core::DateTime::millisecond#0',
        'dart:core::DateTime::microsecond#0',
        'dart:core::DateTime::weekday#0',
        'dart:core::DateTime::isUtc#0',
        'dart:core::DateTime::timeZoneName#0',
        'dart:core::DateTime::timeZoneOffset#0',
        'dart:core::DateTime::millisecondsSinceEpoch#0',
        'dart:core::DateTime::microsecondsSinceEpoch#0',
        'dart:core::DateTime::hashCode#0',
        'dart:core::DateTime::add#1',
        'dart:core::DateTime::subtract#1',
        'dart:core::DateTime::difference#1',
        'dart:core::DateTime::compareTo#1',
        'dart:core::DateTime::isAfter#1',
        'dart:core::DateTime::isBefore#1',
        'dart:core::DateTime::isAtSameMomentAs#1',
        'dart:core::DateTime::toLocal#0',
        'dart:core::DateTime::toUtc#0',
        'dart:core::DateTime::toIso8601String#0',
        'dart:core::DateTime::toString#0',
        'dart:core::DateTime::==#1',
      ];
      for (final name in expectedNames) {
        expect(registry.lookupByName(name), isNot(-1),
            reason: 'Missing binding: $name');
      }
    });
  });

  // ── Constructors ──

  group('constructors', () {
    test('DateTime(2024, 1, 15) via default constructor', () {
      final dt =
          invoke('dart:core::DateTime::#8', [2024, 1, 15, 0, 0, 0, 0, 0]);
      expect(dt, isA<DateTime>());
      final d = dt as DateTime;
      expect(d.year, 2024);
      expect(d.month, 1);
      expect(d.day, 15);
    });

    test('DateTime(2024) with only year (optional params default)', () {
      final dt = invoke('dart:core::DateTime::#8', [2024]);
      final d = dt as DateTime;
      expect(d.year, 2024);
      expect(d.month, 1);
      expect(d.day, 1);
      expect(d.hour, 0);
      expect(d.minute, 0);
      expect(d.second, 0);
    });

    test('DateTime(2024, 6, 15, 10, 30, 45) with time components', () {
      final dt = invoke(
          'dart:core::DateTime::#8', [2024, 6, 15, 10, 30, 45, null, null]);
      final d = dt as DateTime;
      expect(d.year, 2024);
      expect(d.month, 6);
      expect(d.day, 15);
      expect(d.hour, 10);
      expect(d.minute, 30);
      expect(d.second, 45);
    });

    test('DateTime.utc(2024, 3, 20)', () {
      final dt =
          invoke('dart:core::DateTime::utc#8', [2024, 3, 20, 0, 0, 0, 0, 0]);
      final d = dt as DateTime;
      expect(d.year, 2024);
      expect(d.month, 3);
      expect(d.day, 20);
      expect(d.isUtc, true);
    });

    test('DateTime.utc(2024) with only year', () {
      final dt = invoke('dart:core::DateTime::utc#8', [2024]);
      final d = dt as DateTime;
      expect(d.year, 2024);
      expect(d.isUtc, true);
    });

    test('DateTime.now() returns a DateTime close to now', () {
      final before = DateTime.now();
      final dt = invoke('dart:core::DateTime::now#0', []) as DateTime;
      final after = DateTime.now();
      expect(dt.isAfter(before) || dt.isAtSameMomentAs(before), true);
      expect(dt.isBefore(after) || dt.isAtSameMomentAs(after), true);
    });

    test('DateTime.fromMillisecondsSinceEpoch(0)', () {
      final dt = invoke(
          'dart:core::DateTime::fromMillisecondsSinceEpoch#2', [0, null]);
      final d = dt as DateTime;
      expect(d.millisecondsSinceEpoch, 0);
    });

    test('DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)', () {
      final dt = invoke(
          'dart:core::DateTime::fromMillisecondsSinceEpoch#2', [0, true]);
      final d = dt as DateTime;
      expect(d.millisecondsSinceEpoch, 0);
      expect(d.isUtc, true);
    });

    test('DateTime.fromMicrosecondsSinceEpoch(1000000)', () {
      final dt = invoke(
          'dart:core::DateTime::fromMicrosecondsSinceEpoch#2',
          [1000000, null]);
      final d = dt as DateTime;
      expect(d.microsecondsSinceEpoch, 1000000);
    });

    test('DateTime.fromMicrosecondsSinceEpoch(1000000, isUtc: true)', () {
      final dt = invoke(
          'dart:core::DateTime::fromMicrosecondsSinceEpoch#2',
          [1000000, true]);
      final d = dt as DateTime;
      expect(d.microsecondsSinceEpoch, 1000000);
      expect(d.isUtc, true);
    });
  });

  // ── Static methods ──

  group('static methods', () {
    test('DateTime.parse("2024-01-15")', () {
      final dt =
          invoke('dart:core::DateTime::parse#1', ['2024-01-15']) as DateTime;
      expect(dt.year, 2024);
      expect(dt.month, 1);
      expect(dt.day, 15);
    });

    test('DateTime.parse("2024-06-15T10:30:00Z") UTC', () {
      final dt = invoke(
              'dart:core::DateTime::parse#1', ['2024-06-15T10:30:00Z'])
          as DateTime;
      expect(dt.year, 2024);
      expect(dt.month, 6);
      expect(dt.hour, 10);
      expect(dt.minute, 30);
      expect(dt.isUtc, true);
    });

    test('DateTime.tryParse("2024-01-15") returns DateTime', () {
      final dt = invoke('dart:core::DateTime::tryParse#1', ['2024-01-15']);
      expect(dt, isA<DateTime>());
      expect((dt as DateTime).year, 2024);
    });

    test('DateTime.tryParse("not-a-date") returns null', () {
      final dt = invoke('dart:core::DateTime::tryParse#1', ['not-a-date']);
      expect(dt, isNull);
    });
  });

  // ── Getters ──

  group('getters', () {
    // Use a fixed UTC DateTime for deterministic tests.
    final ref = DateTime.utc(2024, 6, 15, 10, 30, 45, 123, 456);

    test('year', () {
      expect(invoke('dart:core::DateTime::year#0', [ref]), 2024);
    });

    test('month', () {
      expect(invoke('dart:core::DateTime::month#0', [ref]), 6);
    });

    test('day', () {
      expect(invoke('dart:core::DateTime::day#0', [ref]), 15);
    });

    test('hour', () {
      expect(invoke('dart:core::DateTime::hour#0', [ref]), 10);
    });

    test('minute', () {
      expect(invoke('dart:core::DateTime::minute#0', [ref]), 30);
    });

    test('second', () {
      expect(invoke('dart:core::DateTime::second#0', [ref]), 45);
    });

    test('millisecond', () {
      expect(invoke('dart:core::DateTime::millisecond#0', [ref]), 123);
    });

    test('microsecond', () {
      expect(invoke('dart:core::DateTime::microsecond#0', [ref]), 456);
    });

    test('weekday (2024-06-15 is Saturday = 6)', () {
      expect(invoke('dart:core::DateTime::weekday#0', [ref]), DateTime.saturday);
    });

    test('isUtc', () {
      expect(invoke('dart:core::DateTime::isUtc#0', [ref]), true);
      final local = DateTime(2024, 1, 1);
      expect(invoke('dart:core::DateTime::isUtc#0', [local]), false);
    });

    test('timeZoneName', () {
      final name = invoke('dart:core::DateTime::timeZoneName#0', [ref]);
      expect(name, isA<String>());
    });

    test('timeZoneOffset', () {
      final offset = invoke('dart:core::DateTime::timeZoneOffset#0', [ref]);
      expect(offset, isA<Duration>());
    });

    test('millisecondsSinceEpoch', () {
      final epoch = DateTime.utc(1970, 1, 1);
      expect(invoke('dart:core::DateTime::millisecondsSinceEpoch#0', [epoch]),
          0);
    });

    test('microsecondsSinceEpoch', () {
      final epoch = DateTime.utc(1970, 1, 1);
      expect(invoke('dart:core::DateTime::microsecondsSinceEpoch#0', [epoch]),
          0);
    });

    test('hashCode', () {
      final hash = invoke('dart:core::DateTime::hashCode#0', [ref]);
      expect(hash, isA<int>());
      expect(hash, ref.hashCode);
    });
  });

  // ── Methods ──

  group('methods', () {
    final base = DateTime.utc(2024, 1, 1);

    test('add(Duration)', () {
      final result = invoke(
          'dart:core::DateTime::add#1', [base, const Duration(days: 31)]);
      final d = result as DateTime;
      expect(d.month, 2);
      expect(d.day, 1);
    });

    test('subtract(Duration)', () {
      final result = invoke(
          'dart:core::DateTime::subtract#1', [base, const Duration(days: 1)]);
      final d = result as DateTime;
      expect(d.year, 2023);
      expect(d.month, 12);
      expect(d.day, 31);
    });

    test('difference(DateTime)', () {
      final other = DateTime.utc(2024, 1, 2);
      final result =
          invoke('dart:core::DateTime::difference#1', [other, base]);
      expect(result, isA<Duration>());
      expect((result as Duration).inDays, 1);
    });

    test('compareTo(DateTime)', () {
      final later = DateTime.utc(2024, 6, 1);
      expect(invoke('dart:core::DateTime::compareTo#1', [base, later]),
          lessThan(0));
      expect(invoke('dart:core::DateTime::compareTo#1', [later, base]),
          greaterThan(0));
      expect(invoke('dart:core::DateTime::compareTo#1', [base, base]), 0);
    });

    test('isAfter(DateTime)', () {
      final later = DateTime.utc(2024, 6, 1);
      expect(invoke('dart:core::DateTime::isAfter#1', [later, base]), true);
      expect(invoke('dart:core::DateTime::isAfter#1', [base, later]), false);
    });

    test('isBefore(DateTime)', () {
      final later = DateTime.utc(2024, 6, 1);
      expect(invoke('dart:core::DateTime::isBefore#1', [base, later]), true);
      expect(invoke('dart:core::DateTime::isBefore#1', [later, base]), false);
    });

    test('isAtSameMomentAs(DateTime)', () {
      final same = DateTime.utc(2024, 1, 1);
      expect(
          invoke('dart:core::DateTime::isAtSameMomentAs#1', [base, same]),
          true);
      final different = DateTime.utc(2024, 1, 2);
      expect(
          invoke(
              'dart:core::DateTime::isAtSameMomentAs#1', [base, different]),
          false);
    });

    test('toLocal()', () {
      final utc = DateTime.utc(2024, 6, 15);
      final local =
          invoke('dart:core::DateTime::toLocal#0', [utc]) as DateTime;
      expect(local.isUtc, false);
    });

    test('toUtc()', () {
      final local = DateTime(2024, 6, 15);
      final utc = invoke('dart:core::DateTime::toUtc#0', [local]) as DateTime;
      expect(utc.isUtc, true);
    });

    test('toIso8601String()', () {
      final dt = DateTime.utc(2024, 1, 15, 10, 30, 0);
      final s = invoke('dart:core::DateTime::toIso8601String#0', [dt]);
      expect(s, '2024-01-15T10:30:00.000Z');
    });

    test('toString()', () {
      final dt = DateTime.utc(2024, 1, 15);
      final s = invoke('dart:core::DateTime::toString#0', [dt]);
      expect(s, isA<String>());
      expect((s as String).contains('2024'), true);
    });

    test('== (equal)', () {
      final a = DateTime.utc(2024, 1, 1);
      final b = DateTime.utc(2024, 1, 1);
      expect(invoke('dart:core::DateTime::==#1', [a, b]), true);
    });

    test('== (not equal)', () {
      final a = DateTime.utc(2024, 1, 1);
      final b = DateTime.utc(2024, 1, 2);
      expect(invoke('dart:core::DateTime::==#1', [a, b]), false);
    });
  });

  // ── E2E tests (compile and run) ──

  group('e2e', () {
    test('DateTime(2024, 6, 15).month returns 6', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return DateTime(2024, 6, 15).month;
}
''');
      expect(result, 6);
    });

    test('DateTime(2024, 1, 1).add(Duration(days: 31)).month returns 2',
        () async {
      final result = await compileAndRunWithHost('''
int main() {
  return DateTime(2024, 1, 1).add(Duration(days: 31)).month;
}
''');
      expect(result, 2);
    });

    test('DateTime.parse("2024-01-15").year returns 2024', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return DateTime.parse('2024-01-15').year;
}
''');
      expect(result, 2024);
    });

    test('DateTime.utc(2024, 3, 20).isUtc returns true', () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return DateTime.utc(2024, 3, 20).isUtc;
}
''');
      expect(result, true);
    });

    test('DateTime comparison: isBefore', () async {
      final result = await compileAndRunWithHost('''
bool main() {
  final a = DateTime(2024, 1, 1);
  final b = DateTime(2024, 6, 1);
  return a.isBefore(b);
}
''');
      expect(result, true);
    });

    test('DateTime.toIso8601String()', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return DateTime.utc(2024, 1, 15, 10, 30).toIso8601String();
}
''');
      expect(result, '2024-01-15T10:30:00.000Z');
    });

    test('DateTime difference in days', () async {
      final result = await compileAndRunWithHost('''
int main() {
  final a = DateTime(2024, 1, 1);
  final b = DateTime(2024, 1, 11);
  return b.difference(a).inDays;
}
''');
      expect(result, 10);
    });

    test('DateTime.tryParse with invalid string returns null check', () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return DateTime.tryParse('not-a-date') == null;
}
''');
      expect(result, true);
    });
  });
}
