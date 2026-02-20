import 'package:dartic/src/bridge/host_bindings.dart';
import 'package:test/test.dart';

void main() {
  group('HostBindings', () {
    late HostBindings bindings;

    setUp(() {
      bindings = HostBindings();
    });

    test('register returns allocated ID', () {
      final id = bindings.register('dart:core::::print#1', (args) => null);
      expect(id, greaterThanOrEqualTo(0));
    });

    test('register same name returns same ID (idempotent)', () {
      final id1 = bindings.register('dart:core::::print#1', (args) => null);
      final id2 = bindings.register('dart:core::::print#1', (args) => null);
      expect(id1, equals(id2));
    });

    test('register different names returns different IDs', () {
      final id1 = bindings.register('dart:core::::print#1', (args) => null);
      final id2 =
          bindings.register('dart:core::int::toString#0', (args) => '42');
      expect(id1, isNot(equals(id2)));
    });

    test('invoke calls registered wrapper and returns result', () {
      final id = bindings.register(
        'dart:core::int::abs#0',
        (args) => (args[0] as int).abs(),
      );
      final result = bindings.invoke(id, [-42]);
      expect(result, equals(42));
    });

    test('invoke with no-arg function', () {
      final id = bindings.register(
        'dart:core::Object::hashCode#0',
        (args) => 12345,
      );
      final result = bindings.invoke(id, []);
      expect(result, equals(12345));
    });

    test('invoke with multiple args', () {
      final id = bindings.register(
        'dart:core::int::clamp#2',
        (args) => (args[0] as int).clamp(args[1] as int, args[2] as int),
      );
      final result = bindings.invoke(id, [15, 0, 10]);
      expect(result, equals(10));
    });

    test('lookupByName returns ID for registered binding', () {
      final id = bindings.register('dart:core::::print#1', (args) => null);
      expect(bindings.lookupByName('dart:core::::print#1'), equals(id));
    });

    test('lookupByName returns -1 for unregistered binding', () {
      expect(bindings.lookupByName('dart:core::nonexistent#0'), equals(-1));
    });

    test('resolveBindingTable maps symbol names to runtime IDs', () {
      bindings.register('dart:core::::print#1', (args) => null);
      bindings.register('dart:core::int::toString#0', (args) => '');
      bindings.register('dart:core::String::length#0', (args) => 0);

      final names = [
        'dart:core::String::length#0',
        'dart:core::::print#1',
        'dart:core::int::toString#0',
      ];
      final ids = bindings.resolveBindingTable(names);

      expect(ids.length, equals(3));
      expect(ids[0], equals(bindings.lookupByName('dart:core::String::length#0')));
      expect(ids[1], equals(bindings.lookupByName('dart:core::::print#1')));
      expect(ids[2], equals(bindings.lookupByName('dart:core::int::toString#0')));
    });

    test('resolveBindingTable with unresolved name returns -1', () {
      bindings.register('dart:core::::print#1', (args) => null);

      final ids = bindings.resolveBindingTable([
        'dart:core::::print#1',
        'dart:core::missing#0',
      ]);

      expect(ids[0], greaterThanOrEqualTo(0));
      expect(ids[1], equals(-1));
    });

    test('invoke throws on invalid ID', () {
      expect(
        () => bindings.invoke(999, []),
        throwsA(isA<RangeError>()),
      );
    });
  });
}
