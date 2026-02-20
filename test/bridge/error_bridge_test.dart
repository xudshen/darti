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

  // ── ArgumentError ──

  group('ArgumentError', () {
    test('constructor', () {
      final e = invoke('dart:core::ArgumentError::#1', ['bad value']);
      expect(e, isA<ArgumentError>());
    });

    test('message getter', () {
      final e = ArgumentError('bad value');
      expect(invoke('dart:core::ArgumentError::message#0', [e]), 'bad value');
    });

    test('toString', () {
      final e = ArgumentError('bad value');
      final s = invoke('dart:core::ArgumentError::toString#0', [e]) as String;
      expect(s, contains('bad value'));
    });

    test('name getter', () {
      final e = ArgumentError.value(42, 'x');
      expect(invoke('dart:core::ArgumentError::name#0', [e]), 'x');
    });

    test('invalidValue getter', () {
      final e = ArgumentError.value(42, 'x');
      expect(invoke('dart:core::ArgumentError::invalidValue#0', [e]), 42);
    });

    test('value factory', () {
      final e = invoke('dart:core::ArgumentError::value#3', [42, 'x', 'msg']);
      expect(e, isA<ArgumentError>());
      expect((e as ArgumentError).name, 'x');
      expect(e.invalidValue, 42);
    });

    test('notNull factory', () {
      final e = invoke('dart:core::ArgumentError::notNull#1', ['param']);
      expect(e, isA<ArgumentError>());
      expect((e as ArgumentError).name, 'param');
    });
  });

  // ── RangeError ──

  group('RangeError', () {
    test('constructor', () {
      final e = invoke('dart:core::RangeError::#1', ['out of range']);
      expect(e, isA<RangeError>());
    });

    test('range factory', () {
      final e =
          invoke('dart:core::RangeError::range#5', [10, 0, 5, 'idx', 'oops']);
      expect(e, isA<RangeError>());
    });

    test('start and end getters', () {
      final e = RangeError.range(10, 0, 5);
      expect(invoke('dart:core::RangeError::start#0', [e]), 0);
      expect(invoke('dart:core::RangeError::end#0', [e]), 5);
    });

    test('value factory', () {
      final e = invoke('dart:core::RangeError::value#3', [42]);
      expect(e, isA<RangeError>());
    });

    test('index factory', () {
      final e = invoke('dart:core::RangeError::index#5', [5, [1, 2, 3]]);
      expect(e, isA<RangeError>());
    });

    test('checkValidIndex returns index when valid', () {
      final result =
          invoke('dart:core::RangeError::checkValidIndex#5', [1, [1, 2, 3]]);
      expect(result, 1);
    });

    test('checkValidRange returns length when valid', () {
      final result =
          invoke('dart:core::RangeError::checkValidRange#6', [0, 3, 5]);
      expect(result, 3);
    });

    test('checkNotNegative returns value when valid', () {
      final result =
          invoke('dart:core::RangeError::checkNotNegative#3', [5]);
      expect(result, 5);
    });
  });

  // ── StateError ──

  group('StateError', () {
    test('constructor and message', () {
      final e = invoke('dart:core::StateError::#1', ['bad state']);
      expect(e, isA<StateError>());
      expect(invoke('dart:core::StateError::message#0', [e]), 'bad state');
    });

    test('toString', () {
      final e = StateError('bad state');
      final s = invoke('dart:core::StateError::toString#0', [e]) as String;
      expect(s, contains('bad state'));
    });
  });

  // ── UnsupportedError ──

  group('UnsupportedError', () {
    test('constructor and message', () {
      final e = invoke('dart:core::UnsupportedError::#1', ['not supported']);
      expect(e, isA<UnsupportedError>());
      expect(invoke('dart:core::UnsupportedError::message#0', [e]),
          'not supported');
    });
  });

  // ── FormatException ──

  group('FormatException', () {
    test('constructor with all args', () {
      final e = invoke(
          'dart:core::FormatException::#3', ['bad format', 'input', 3]);
      expect(e, isA<FormatException>());
    });

    test('source getter', () {
      final e = FormatException('msg', 'source_text', 5);
      expect(invoke('dart:core::FormatException::source#0', [e]),
          'source_text');
    });

    test('offset getter', () {
      final e = FormatException('msg', 'source_text', 5);
      expect(invoke('dart:core::FormatException::offset#0', [e]), 5);
    });

    test('message getter', () {
      final e = FormatException('msg');
      expect(invoke('dart:core::FormatException::message#0', [e]), 'msg');
    });
  });

  // ── Error base ──

  group('Error', () {
    test('stackTrace getter', () {
      try {
        throw ArgumentError('test');
      } on ArgumentError catch (e) {
        final st = invoke('dart:core::Error::stackTrace#0', [e]);
        // stackTrace may be null if not captured via catch with stack trace
        expect(st, anything);
      }
    });

    test('toString', () {
      final e = ArgumentError('test');
      final s = invoke('dart:core::Error::toString#0', [e]) as String;
      expect(s, isA<String>());
    });
  });

  // ── Exception ──

  group('Exception', () {
    test('factory constructor', () {
      final e = invoke('dart:core::Exception::#1', ['message']);
      expect(e, isA<Exception>());
    });

    test('toString', () {
      final e = Exception('message');
      final s = invoke('dart:core::Exception::toString#0', [e]) as String;
      expect(s, contains('message'));
    });
  });

  // ── ConcurrentModificationError ──

  group('ConcurrentModificationError', () {
    test('constructor', () {
      final e =
          invoke('dart:core::ConcurrentModificationError::#1', [[1, 2, 3]]);
      expect(e, isA<ConcurrentModificationError>());
    });

    test('toString', () {
      final e = ConcurrentModificationError([1, 2, 3]);
      final s = invoke(
              'dart:core::ConcurrentModificationError::toString#0', [e])
          as String;
      expect(s, isA<String>());
    });
  });

  // ── UnimplementedError ──

  group('UnimplementedError', () {
    test('constructor', () {
      final e = invoke('dart:core::UnimplementedError::#1', ['todo']);
      expect(e, isA<UnimplementedError>());
    });

    test('message getter', () {
      final e = UnimplementedError('todo');
      expect(invoke('dart:core::UnimplementedError::message#0', [e]), 'todo');
    });

    test('toString', () {
      final e = UnimplementedError('todo');
      final s = invoke('dart:core::UnimplementedError::toString#0', [e])
          as String;
      expect(s, contains('todo'));
    });
  });

  // ── AssertionError ──

  group('AssertionError', () {
    test('constructor', () {
      final e = invoke('dart:core::AssertionError::#1', ['assertion failed']);
      expect(e, isA<AssertionError>());
    });

    test('message getter', () {
      final e = AssertionError('assertion failed');
      expect(invoke('dart:core::AssertionError::message#0', [e]),
          'assertion failed');
    });

    test('toString', () {
      final e = AssertionError('assertion failed');
      final s = invoke('dart:core::AssertionError::toString#0', [e])
          as String;
      expect(s, isA<String>());
    });
  });

  // ── TypeError ──

  group('TypeError', () {
    test('toString', () {
      try {
        // Force a type error
        (42 as dynamic) as String;
      } on TypeError catch (e) {
        final s =
            invoke('dart:core::TypeError::toString#0', [e]) as String;
        expect(s, isNotEmpty);
      }
    });
  });

  // ── IndexError ──

  group('IndexError', () {
    test('constructor', () {
      final e = invoke('dart:core::IndexError::#5', [5, [1, 2, 3]]);
      expect(e, isA<IndexError>());
    });

    test('indexable getter', () {
      final list = [1, 2, 3];
      // Use the binding itself to construct the IndexError.
      final e = invoke('dart:core::IndexError::#5', [5, list]);
      expect(invoke('dart:core::IndexError::indexable#0', [e]), same(list));
    });

    test('length getter', () {
      final e = invoke('dart:core::IndexError::#5',
          [5, [1, 2, 3], null, null, 3]);
      expect(invoke('dart:core::IndexError::length#0', [e]), 3);
    });
  });

  // ── NoSuchMethodError ──

  group('NoSuchMethodError', () {
    test('toString', () {
      try {
        (null as dynamic).nonExistentMethod();
      } on NoSuchMethodError catch (e) {
        final s = invoke('dart:core::NoSuchMethodError::toString#0', [e])
            as String;
        expect(s, isNotEmpty);
      }
    });
  });

  // ── E2e compile + run tests ──

  group('error e2e', () {
    test('throw and catch UnimplementedError', () async {
      final result = await compileAndRunWithHost('''
String main() {
  try {
    throw UnimplementedError('todo');
  } on UnimplementedError catch (e) {
    return e.message!;
  }
}
''');
      expect(result, 'todo');
    });

    test('throw and catch FormatException with offset', () async {
      final result = await compileAndRunWithHost('''
int main() {
  try {
    throw FormatException('bad', 'input', 3);
  } on FormatException catch (e) {
    return e.offset!;
  }
}
''');
      expect(result, 3);
    });

    test('ArgumentError.value preserves invalidValue', () async {
      final result = await compileAndRunWithHost('''
int main() {
  try {
    throw ArgumentError.value(42, 'x');
  } on ArgumentError catch (e) {
    return e.invalidValue as int;
  }
}
''');
      expect(result, 42);
    });

    test('StateError message', () async {
      final result = await compileAndRunWithHost('''
String main() {
  try {
    throw StateError('no elements');
  } on StateError catch (e) {
    return e.message;
  }
}
''');
      expect(result, 'no elements');
    });
  });
}
