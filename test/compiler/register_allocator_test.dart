import 'package:dartic/src/compiler/register_allocator.dart';
import 'package:test/test.dart';

void main() {
  group('RegisterAllocator', () {
    late RegisterAllocator alloc;

    setUp(() {
      alloc = RegisterAllocator();
    });

    test('allocates sequentially from 0', () {
      expect(alloc.alloc(), 0);
      expect(alloc.alloc(), 1);
      expect(alloc.alloc(), 2);
    });

    test('maxUsed tracks high-water mark', () {
      alloc.alloc(); // 0
      alloc.alloc(); // 1
      alloc.alloc(); // 2
      expect(alloc.maxUsed, 3);
    });

    test('freed registers are reused', () {
      final r0 = alloc.alloc(); // 0
      alloc.alloc(); // 1
      alloc.free(r0);
      // Next alloc should reuse r0 from free pool.
      expect(alloc.alloc(), r0);
    });

    test('free does not lower maxUsed', () {
      alloc.alloc(); // 0
      alloc.alloc(); // 1
      alloc.free(0);
      alloc.free(1);
      expect(alloc.maxUsed, 2, reason: 'maxUsed is a high-water mark');
    });

    test('batch free returns multiple registers', () {
      final r0 = alloc.alloc();
      final r1 = alloc.alloc();
      final r2 = alloc.alloc();
      alloc.freeAll([r0, r1, r2]);
      // Next 3 allocs should come from the free pool.
      final reused = {alloc.alloc(), alloc.alloc(), alloc.alloc()};
      expect(reused, {r0, r1, r2});
    });

    test('starts with initial offset', () {
      final alloc = RegisterAllocator(initialOffset: 3);
      expect(alloc.alloc(), 3);
      expect(alloc.alloc(), 4);
      expect(alloc.maxUsed, 5);
    });

    test('maxUsed with initialOffset reflects total count', () {
      final alloc = RegisterAllocator(initialOffset: 3);
      alloc.alloc(); // 3
      // maxUsed should be 4 (slots 0-3 are in use, count = 4).
      expect(alloc.maxUsed, 4);
    });

    test('empty allocator has maxUsed equal to initialOffset', () {
      final alloc = RegisterAllocator(initialOffset: 5);
      expect(alloc.maxUsed, 5);
    });

    test('alternating alloc and free reuses efficiently', () {
      final r0 = alloc.alloc(); // 0
      alloc.free(r0);
      final r1 = alloc.alloc(); // should reuse 0
      expect(r1, r0);
      expect(alloc.maxUsed, 1);
    });
  });
}
