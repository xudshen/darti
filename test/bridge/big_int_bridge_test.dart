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

  // ── Helper to invoke a binding by symbolic name ──
  Object? invoke(String name, List<Object?> args) {
    final id = registry.lookupByName(name);
    if (id == -1) fail('Binding not found: $name');
    return registry.invoke(id, args);
  }

  // ════════════════════════════════════════════════════════════════════
  // Registration tests
  // ════════════════════════════════════════════════════════════════════

  group('BigIntBindings registration', () {
    test('factory constructors are registered', () {
      expect(
          registry.lookupByName('dart:core::BigInt::from#1'), isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::parse#2'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::tryParse#2'),
          isNot(equals(-1)));
    });

    test('static constants are registered', () {
      expect(registry.lookupByName('dart:core::BigInt::zero#0'),
          isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::one#0'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::two#0'), isNot(equals(-1)));
    });

    test('getters are registered', () {
      expect(registry.lookupByName('dart:core::BigInt::isEven#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::isOdd#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::isNegative#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::isValidInt#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::bitLength#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::sign#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::hashCode#0'),
          isNot(equals(-1)));
    });

    test('methods are registered', () {
      expect(
          registry.lookupByName('dart:core::BigInt::abs#0'), isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::compareTo#1'),
          isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::gcd#1'), isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::modInverse#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::modPow#2'),
          isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::pow#1'), isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::remainder#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::toInt#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::toDouble#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::toRadixString#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::toString#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::toSigned#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::toUnsigned#1'),
          isNot(equals(-1)));
    });

    test('operators are registered', () {
      expect(
          registry.lookupByName('dart:core::BigInt::+#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::-#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::*#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::~/#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::%#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::<<#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::>>#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::&#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::|#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::^#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::~#0'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::<#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::<=#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::>#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::>=#1'), isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::BigInt::unary-#0'),
          isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::BigInt::==#1'), isNot(equals(-1)));
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Direct invoke tests
  // ════════════════════════════════════════════════════════════════════

  group('BigIntBindings invoke — factory constructors', () {
    test('BigInt.from(42)', () {
      final result = invoke('dart:core::BigInt::from#1', [42]);
      expect(result, BigInt.from(42));
    });

    test('BigInt.parse large number', () {
      final result = invoke('dart:core::BigInt::parse#2',
          ['123456789012345678901234567890', null]);
      expect(result, BigInt.parse('123456789012345678901234567890'));
    });

    test('BigInt.parse with radix', () {
      final result = invoke('dart:core::BigInt::parse#2', ['ff', 16]);
      expect(result, BigInt.from(255));
    });

    test('BigInt.tryParse valid', () {
      final result = invoke('dart:core::BigInt::tryParse#2', ['42', null]);
      expect(result, BigInt.from(42));
    });

    test('BigInt.tryParse invalid returns null', () {
      final result = invoke('dart:core::BigInt::tryParse#2', ['abc', null]);
      expect(result, isNull);
    });

    test('BigInt.tryParse with radix', () {
      final result = invoke('dart:core::BigInt::tryParse#2', ['ff', 16]);
      expect(result, BigInt.from(255));
    });
  });

  group('BigIntBindings invoke — static constants', () {
    test('BigInt.zero', () {
      expect(invoke('dart:core::BigInt::zero#0', []), BigInt.zero);
    });

    test('BigInt.one', () {
      expect(invoke('dart:core::BigInt::one#0', []), BigInt.one);
    });

    test('BigInt.two', () {
      expect(invoke('dart:core::BigInt::two#0', []), BigInt.two);
    });
  });

  group('BigIntBindings invoke — getters', () {
    test('isEven', () {
      expect(invoke('dart:core::BigInt::isEven#0', [BigInt.from(4)]), true);
      expect(invoke('dart:core::BigInt::isEven#0', [BigInt.from(3)]), false);
    });

    test('isOdd', () {
      expect(invoke('dart:core::BigInt::isOdd#0', [BigInt.from(3)]), true);
      expect(invoke('dart:core::BigInt::isOdd#0', [BigInt.from(4)]), false);
    });

    test('isNegative', () {
      expect(
          invoke('dart:core::BigInt::isNegative#0', [BigInt.from(-1)]), true);
      expect(
          invoke('dart:core::BigInt::isNegative#0', [BigInt.from(1)]), false);
    });

    test('isValidInt', () {
      expect(
          invoke('dart:core::BigInt::isValidInt#0', [BigInt.from(42)]), true);
    });

    test('bitLength', () {
      expect(
          invoke('dart:core::BigInt::bitLength#0', [BigInt.from(255)]), 8);
    });

    test('sign', () {
      // BigInt.sign returns int in modern Dart.
      expect(invoke('dart:core::BigInt::sign#0', [BigInt.from(42)]), 1);
      expect(invoke('dart:core::BigInt::sign#0', [BigInt.from(-42)]), -1);
      expect(invoke('dart:core::BigInt::sign#0', [BigInt.zero]), 0);
    });

    test('hashCode', () {
      final v = BigInt.from(42);
      expect(invoke('dart:core::BigInt::hashCode#0', [v]), v.hashCode);
    });
  });

  group('BigIntBindings invoke — methods', () {
    test('abs', () {
      expect(invoke('dart:core::BigInt::abs#0', [BigInt.from(-42)]),
          BigInt.from(42));
    });

    test('compareTo', () {
      expect(
          invoke('dart:core::BigInt::compareTo#1',
              [BigInt.from(1), BigInt.from(2)]),
          lessThan(0));
      expect(
          invoke('dart:core::BigInt::compareTo#1',
              [BigInt.from(2), BigInt.from(1)]),
          greaterThan(0));
      expect(
          invoke('dart:core::BigInt::compareTo#1',
              [BigInt.from(1), BigInt.from(1)]),
          0);
    });

    test('gcd', () {
      expect(
          invoke('dart:core::BigInt::gcd#1',
              [BigInt.from(12), BigInt.from(8)]),
          BigInt.from(4));
    });

    test('modInverse', () {
      expect(
          invoke('dart:core::BigInt::modInverse#1',
              [BigInt.from(3), BigInt.from(7)]),
          BigInt.from(5));
    });

    test('modPow', () {
      expect(
          invoke('dart:core::BigInt::modPow#2',
              [BigInt.from(2), BigInt.from(10), BigInt.from(1000)]),
          BigInt.from(24));
    });

    test('pow', () {
      expect(invoke('dart:core::BigInt::pow#1', [BigInt.from(2), 10]),
          BigInt.from(1024));
    });

    test('remainder', () {
      expect(
          invoke('dart:core::BigInt::remainder#1',
              [BigInt.from(10), BigInt.from(3)]),
          BigInt.from(1));
    });

    test('toInt', () {
      expect(invoke('dart:core::BigInt::toInt#0', [BigInt.from(42)]), 42);
    });

    test('toDouble', () {
      expect(
          invoke('dart:core::BigInt::toDouble#0', [BigInt.from(42)]), 42.0);
    });

    test('toRadixString', () {
      expect(invoke('dart:core::BigInt::toRadixString#1',
          [BigInt.from(255), 16]), 'ff');
    });

    test('toString', () {
      expect(invoke('dart:core::BigInt::toString#0', [BigInt.from(42)]),
          '42');
    });

    test('toSigned', () {
      expect(invoke('dart:core::BigInt::toSigned#1',
          [BigInt.from(128), 8]), BigInt.from(-128));
    });

    test('toUnsigned', () {
      expect(invoke('dart:core::BigInt::toUnsigned#1',
          [BigInt.from(-1), 8]), BigInt.from(255));
    });
  });

  group('BigIntBindings invoke — operators', () {
    test('+ operator', () {
      expect(
          invoke('dart:core::BigInt::+#1',
              [BigInt.from(10), BigInt.from(20)]),
          BigInt.from(30));
    });

    test('- operator', () {
      expect(
          invoke('dart:core::BigInt::-#1',
              [BigInt.from(20), BigInt.from(5)]),
          BigInt.from(15));
    });

    test('* operator', () {
      expect(
          invoke('dart:core::BigInt::*#1',
              [BigInt.from(6), BigInt.from(7)]),
          BigInt.from(42));
    });

    test('~/ operator', () {
      expect(
          invoke('dart:core::BigInt::~/#1',
              [BigInt.from(10), BigInt.from(3)]),
          BigInt.from(3));
    });

    test('% operator', () {
      expect(
          invoke('dart:core::BigInt::%#1',
              [BigInt.from(10), BigInt.from(3)]),
          BigInt.from(1));
    });

    test('<< operator', () {
      expect(
          invoke('dart:core::BigInt::<<#1', [BigInt.from(1), 10]),
          BigInt.from(1024));
    });

    test('>> operator', () {
      expect(
          invoke('dart:core::BigInt::>>#1', [BigInt.from(1024), 5]),
          BigInt.from(32));
    });

    test('& operator', () {
      expect(
          invoke('dart:core::BigInt::&#1',
              [BigInt.from(0xFF), BigInt.from(0x0F)]),
          BigInt.from(0x0F));
    });

    test('| operator', () {
      expect(
          invoke('dart:core::BigInt::|#1',
              [BigInt.from(0xF0), BigInt.from(0x0F)]),
          BigInt.from(0xFF));
    });

    test('^ operator', () {
      expect(
          invoke('dart:core::BigInt::^#1',
              [BigInt.from(0xFF), BigInt.from(0x0F)]),
          BigInt.from(0xF0));
    });

    test('~ operator', () {
      expect(invoke('dart:core::BigInt::~#0', [BigInt.from(0)]),
          BigInt.from(-1));
    });

    test('< operator', () {
      expect(
          invoke('dart:core::BigInt::<#1',
              [BigInt.from(1), BigInt.from(2)]),
          true);
      expect(
          invoke('dart:core::BigInt::<#1',
              [BigInt.from(2), BigInt.from(1)]),
          false);
    });

    test('<= operator', () {
      expect(
          invoke('dart:core::BigInt::<=#1',
              [BigInt.from(1), BigInt.from(1)]),
          true);
      expect(
          invoke('dart:core::BigInt::<=#1',
              [BigInt.from(2), BigInt.from(1)]),
          false);
    });

    test('> operator', () {
      expect(
          invoke('dart:core::BigInt::>#1',
              [BigInt.from(2), BigInt.from(1)]),
          true);
      expect(
          invoke('dart:core::BigInt::>#1',
              [BigInt.from(1), BigInt.from(2)]),
          false);
    });

    test('>= operator', () {
      expect(
          invoke('dart:core::BigInt::>=#1',
              [BigInt.from(1), BigInt.from(1)]),
          true);
      expect(
          invoke('dart:core::BigInt::>=#1',
              [BigInt.from(0), BigInt.from(1)]),
          false);
    });

    test('unary- operator', () {
      expect(invoke('dart:core::BigInt::unary-#0', [BigInt.from(42)]),
          BigInt.from(-42));
    });

    test('== operator', () {
      expect(
          invoke('dart:core::BigInt::==#1',
              [BigInt.from(42), BigInt.from(42)]),
          true);
      expect(
          invoke('dart:core::BigInt::==#1',
              [BigInt.from(42), BigInt.from(43)]),
          false);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // E2e tests (compile Dart source → bytecode → interpreter)
  // ════════════════════════════════════════════════════════════════════

  group('BigInt e2e', () {
    test('BigInt addition', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return (BigInt.from(10) + BigInt.from(20)).toString();
}
''');
      expect(result, '30');
    });

    test('BigInt.parse large number', () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return BigInt.parse('999999999999999999').isValidInt;
}
''');
      expect(result, isA<bool>());
    });

    test('BigInt.from and toInt round-trip', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return BigInt.from(42).toInt();
}
''');
      expect(result, 42);
    });

    test('BigInt multiplication', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return (BigInt.from(6) * BigInt.from(7)).toString();
}
''');
      expect(result, '42');
    });

    test('BigInt comparison', () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return BigInt.from(10) > BigInt.from(5);
}
''');
      expect(result, true);
    });

    test('BigInt.zero constant', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return BigInt.zero.toString();
}
''');
      expect(result, '0');
    });

    test('BigInt pow', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return BigInt.from(2).pow(10).toString();
}
''');
      expect(result, '1024');
    });

    test('BigInt abs of negative', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return BigInt.from(-42).abs().toString();
}
''');
      expect(result, '42');
    });

    test('BigInt toRadixString hex', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return BigInt.from(255).toRadixString(16);
}
''');
      expect(result, 'ff');
    });

    test('BigInt isEven', () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return BigInt.from(4).isEven;
}
''');
      expect(result, true);
    });
  });
}
