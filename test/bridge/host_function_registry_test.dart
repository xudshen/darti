import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:test/test.dart';

void main() {
  group('HostFunctionRegistry', () {
    late HostFunctionRegistry registry;

    setUp(() {
      registry = HostFunctionRegistry();
    });

    test('register returns allocated ID', () {
      final id = registry.register('dart:core::::print#1', (args) => null);
      expect(id, greaterThanOrEqualTo(0));
    });

    test('register same name returns same ID (idempotent)', () {
      final id1 = registry.register('dart:core::::print#1', (args) => null);
      final id2 = registry.register('dart:core::::print#1', (args) => null);
      expect(id1, equals(id2));
    });

    test('register different names returns different IDs', () {
      final id1 = registry.register('dart:core::::print#1', (args) => null);
      final id2 =
          registry.register('dart:core::int::toString#0', (args) => '42');
      expect(id1, isNot(equals(id2)));
    });

    test('invoke calls registered wrapper and returns result', () {
      final id = registry.register(
        'dart:core::int::abs#0',
        (args) => (args[0] as int).abs(),
      );
      final result = registry.invoke(id, [-42]);
      expect(result, equals(42));
    });

    test('invoke with no-arg function', () {
      final id = registry.register(
        'dart:core::Object::hashCode#0',
        (args) => 12345,
      );
      final result = registry.invoke(id, []);
      expect(result, equals(12345));
    });

    test('invoke with multiple args', () {
      final id = registry.register(
        'dart:core::int::clamp#2',
        (args) => (args[0] as int).clamp(args[1] as int, args[2] as int),
      );
      final result = registry.invoke(id, [15, 0, 10]);
      expect(result, equals(10));
    });

    test('lookupByName returns ID for registered binding', () {
      final id = registry.register('dart:core::::print#1', (args) => null);
      expect(registry.lookupByName('dart:core::::print#1'), equals(id));
    });

    test('lookupByName returns -1 for unregistered binding', () {
      expect(registry.lookupByName('dart:core::nonexistent#0'), equals(-1));
    });

    test('resolveBindingTable maps symbol names to runtime IDs', () {
      registry.register('dart:core::::print#1', (args) => null);
      registry.register('dart:core::int::toString#0', (args) => '');
      registry.register('dart:core::String::length#0', (args) => 0);

      final names = [
        'dart:core::String::length#0',
        'dart:core::::print#1',
        'dart:core::int::toString#0',
      ];
      final ids = registry.resolveBindingTable(names);

      expect(ids.length, equals(3));
      expect(ids[0], equals(registry.lookupByName('dart:core::String::length#0')));
      expect(ids[1], equals(registry.lookupByName('dart:core::::print#1')));
      expect(ids[2], equals(registry.lookupByName('dart:core::int::toString#0')));
    });

    test('resolveBindingTable with unresolved name returns -1', () {
      registry.register('dart:core::::print#1', (args) => null);

      final ids = registry.resolveBindingTable([
        'dart:core::::print#1',
        'dart:core::missing#0',
      ]);

      expect(ids[0], greaterThanOrEqualTo(0));
      expect(ids[1], equals(-1));
    });

    test('invoke throws on invalid ID', () {
      expect(
        () => registry.invoke(999, []),
        throwsA(isA<RangeError>()),
      );
    });
  });
}
