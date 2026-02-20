import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_bindings.dart';
import 'package:dartic/src/bridge/dynamic_dispatch.dart';
import 'package:test/test.dart';

void main() {
  late HostBindings bindings;
  late HostDispatchRegistry registry;

  setUp(() {
    bindings = HostBindings();
    CoreBindings.registerAll(bindings);
    registry = HostDispatchRegistry(bindings);
  });

  group('HostDispatchRegistry.lookup', () {
    test('returns wrapper for String', () {
      expect(registry.lookup('hello'), isNotNull);
    });
    test('returns wrapper for int', () {
      expect(registry.lookup(42), isNotNull);
    });
    test('returns wrapper for double', () {
      expect(registry.lookup(3.14), isNotNull);
    });
    test('returns wrapper for bool', () {
      expect(registry.lookup(true), isNotNull);
    });
    test('returns wrapper for List', () {
      expect(registry.lookup([1, 2, 3]), isNotNull);
    });
    test('returns wrapper for Map', () {
      expect(registry.lookup({'a': 1}), isNotNull);
    });
    test('returns wrapper for Set', () {
      expect(registry.lookup({1, 2, 3}), isNotNull);
    });
    test('returns wrapper for Duration', () {
      expect(registry.lookup(const Duration(seconds: 1)), isNotNull);
    });
    test('returns null for unregistered type', () {
      expect(registry.lookup(Object()), isNull);
    });
  });

  group('BindingLookupDispatcher.getProperty', () {
    test('String.length', () {
      final wrapper = registry.lookup('hello')!;
      expect(wrapper.getProperty('hello', 'length'), equals(5));
    });
    test('List.length', () {
      final wrapper = registry.lookup([1, 2, 3])!;
      expect(wrapper.getProperty([1, 2, 3], 'length'), equals(3));
    });
    test('List.isEmpty', () {
      final wrapper = registry.lookup(<int>[])!;
      expect(wrapper.getProperty(<int>[], 'isEmpty'), equals(true));
    });
    test('Map.isEmpty', () {
      final wrapper = registry.lookup(<String, int>{})!;
      expect(wrapper.getProperty(<String, int>{}, 'isEmpty'), equals(true));
    });
    test('Map.length', () {
      final wrapper = registry.lookup({'a': 1, 'b': 2})!;
      expect(wrapper.getProperty({'a': 1, 'b': 2}, 'length'), equals(2));
    });
    test('int.isEven', () {
      final wrapper = registry.lookup(42)!;
      expect(wrapper.getProperty(42, 'isEven'), equals(true));
    });
    test('int.isOdd', () {
      final wrapper = registry.lookup(3)!;
      expect(wrapper.getProperty(3, 'isOdd'), equals(true));
    });
  });

  group('BindingLookupDispatcher.invokeMethod', () {
    test('List.contains', () {
      final list = [1, 2, 3];
      final wrapper = registry.lookup(list)!;
      expect(wrapper.invokeMethod(list, 'contains', [2]), equals(true));
      expect(wrapper.invokeMethod(list, 'contains', [5]), equals(false));
    });
    test('Map.containsKey', () {
      final map = {'a': 1};
      final wrapper = registry.lookup(map)!;
      expect(wrapper.invokeMethod(map, 'containsKey', ['a']), equals(true));
      expect(wrapper.invokeMethod(map, 'containsKey', ['b']), equals(false));
    });
    test('String.substring', () {
      final wrapper = registry.lookup('hello world')!;
      expect(wrapper.invokeMethod('hello world', 'substring', [0, 5]),
          equals('hello'));
    });
    test('String.contains', () {
      final wrapper = registry.lookup('hello')!;
      // contains is registered with #2 (Pattern other, [int startIndex])
      expect(
          wrapper.invokeMethod('hello', 'contains', ['ell', 0]), equals(true));
    });
  });
}
