import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:test/test.dart';

void main() {
  late ConstantPool pool;

  setUp(() {
    pool = ConstantPool();
  });

  group('refs partition', () {
    test('add and get string', () {
      final idx = pool.addRef('hello');
      expect(pool.getRef(idx), 'hello');
    });

    test('add and get null', () {
      final idx = pool.addRef(null);
      expect(pool.getRef(idx), isNull);
    });

    test('indices are independent and sequential', () {
      final i0 = pool.addRef('a');
      final i1 = pool.addRef('b');
      expect(i0, 0);
      expect(i1, 1);
    });

    test('deduplication returns same index for same value', () {
      final i0 = pool.addRef('hello');
      final i1 = pool.addRef('hello');
      expect(i0, i1);
    });

    test('null deduplication', () {
      final i0 = pool.addRef(null);
      final i1 = pool.addRef(null);
      expect(i0, i1);
    });

    test('refCount tracks entries', () {
      pool.addRef('a');
      pool.addRef('b');
      pool.addRef('a'); // dedup
      expect(pool.refCount, 2);
    });
  });

  group('ints partition', () {
    test('add and get int', () {
      final idx = pool.addInt(42);
      expect(pool.getInt(idx), 42);
    });

    test('64-bit int precision', () {
      const large = 0x7FFFFFFFFFFFFFFF; // max int64
      final idx = pool.addInt(large);
      expect(pool.getInt(idx), large);
    });

    test('negative int', () {
      final idx = pool.addInt(-1);
      expect(pool.getInt(idx), -1);
    });

    test('zero', () {
      final idx = pool.addInt(0);
      expect(pool.getInt(idx), 0);
    });

    test('deduplication', () {
      final i0 = pool.addInt(100);
      final i1 = pool.addInt(100);
      expect(i0, i1);
    });

    test('indices are sequential', () {
      final i0 = pool.addInt(1);
      final i1 = pool.addInt(2);
      expect(i0, 0);
      expect(i1, 1);
    });

    test('intCount tracks entries', () {
      pool.addInt(1);
      pool.addInt(2);
      pool.addInt(1); // dedup
      expect(pool.intCount, 2);
    });
  });

  group('doubles partition', () {
    test('add and get double', () {
      final idx = pool.addDouble(3.14);
      expect(pool.getDouble(idx), 3.14);
    });

    test('negative double', () {
      final idx = pool.addDouble(-2.5);
      expect(pool.getDouble(idx), -2.5);
    });

    test('zero', () {
      final idx = pool.addDouble(0.0);
      expect(pool.getDouble(idx), 0.0);
    });

    test('infinity', () {
      final idx = pool.addDouble(double.infinity);
      expect(pool.getDouble(idx), double.infinity);
    });

    test('NaN is deduplicated', () {
      final i0 = pool.addDouble(double.nan);
      final i1 = pool.addDouble(double.nan);
      expect(i0, i1);
      expect(pool.getDouble(i0).isNaN, isTrue);
    });

    test('deduplication', () {
      final i0 = pool.addDouble(1.5);
      final i1 = pool.addDouble(1.5);
      expect(i0, i1);
    });

    test('doubleCount tracks entries', () {
      pool.addDouble(1.0);
      pool.addDouble(2.0);
      pool.addDouble(1.0); // dedup
      expect(pool.doubleCount, 2);
    });
  });

  group('names partition', () {
    test('add and get name', () {
      final idx = pool.addName('toString');
      expect(pool.getName(idx), 'toString');
    });

    test('deduplication', () {
      final i0 = pool.addName('foo');
      final i1 = pool.addName('foo');
      expect(i0, i1);
    });

    test('indices are sequential', () {
      final i0 = pool.addName('a');
      final i1 = pool.addName('b');
      expect(i0, 0);
      expect(i1, 1);
    });

    test('nameCount tracks entries', () {
      pool.addName('x');
      pool.addName('y');
      pool.addName('x'); // dedup
      expect(pool.nameCount, 2);
    });
  });

  group('partition independence', () {
    test('indices are independent across partitions', () {
      final refIdx = pool.addRef('hello');
      final intIdx = pool.addInt(42);
      final dblIdx = pool.addDouble(3.14);
      final nameIdx = pool.addName('method');

      // All partitions start from 0
      expect(refIdx, 0);
      expect(intIdx, 0);
      expect(dblIdx, 0);
      expect(nameIdx, 0);

      // Each can be retrieved independently
      expect(pool.getRef(0), 'hello');
      expect(pool.getInt(0), 42);
      expect(pool.getDouble(0), 3.14);
      expect(pool.getName(0), 'method');
    });
  });
}
