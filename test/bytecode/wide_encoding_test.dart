import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:test/test.dart';

void main() {
  group('WIDE ABC encoding', () {
    test('roundtrip with small values (fits in low bits)', () {
      final words = encodeWideABC(Opcode.addInt.code, 1, 2, 3);
      expect(words.length, 3);
      expect(decodeOp(words[0]), Opcode.wide.code);
      final (a, b, c) = decodeWideABC(words[1], words[2]);
      expect(a, 1);
      expect(b, 2);
      expect(c, 3);
    });

    test('roundtrip with max 16-bit values', () {
      final words = encodeWideABC(Opcode.addInt.code, 0xFFFF, 0xFFFF, 0xFFFF);
      final (a, b, c) = decodeWideABC(words[1], words[2]);
      expect(a, 0xFFFF);
      expect(b, 0xFFFF);
      expect(c, 0xFFFF);
    });

    test('A extends to 16-bit range', () {
      final words = encodeWideABC(Opcode.addInt.code, 300, 0, 0);
      final (a, b, c) = decodeWideABC(words[1], words[2]);
      expect(a, 300);
      expect(b, 0);
      expect(c, 0);
    });

    test('B extends to 16-bit range', () {
      final words = encodeWideABC(Opcode.addInt.code, 0, 500, 0);
      final (a, b, c) = decodeWideABC(words[1], words[2]);
      expect(a, 0);
      expect(b, 500);
      expect(c, 0);
    });

    test('C extends to 16-bit range', () {
      final words = encodeWideABC(Opcode.addInt.code, 0, 0, 1000);
      final (a, b, c) = decodeWideABC(words[1], words[2]);
      expect(a, 0);
      expect(b, 0);
      expect(c, 1000);
    });

    test('opcode preserved in third word', () {
      final words = encodeWideABC(Opcode.mulInt.code, 256, 257, 258);
      expect(decodeOp(words[2]), Opcode.mulInt.code);
    });

    test('total instruction length is 3 words', () {
      final words = encodeWideABC(Opcode.addInt.code, 0, 0, 0);
      expect(words.length, 3);
    });
  });

  group('WIDE ABx encoding', () {
    test('roundtrip with small values', () {
      final words = encodeWideABx(Opcode.loadConst.code, 1, 100);
      expect(words.length, 3);
      expect(decodeOp(words[0]), Opcode.wide.code);
      final (a, bx) = decodeWideABx(words[1], words[2]);
      expect(a, 1);
      expect(bx, 100);
    });

    test('A extends to 16-bit range', () {
      final words = encodeWideABx(Opcode.loadConst.code, 300, 0);
      final (a, bx) = decodeWideABx(words[1], words[2]);
      expect(a, 300);
      expect(bx, 0);
    });

    test('Bx extends to 32-bit range', () {
      final words = encodeWideABx(Opcode.loadConstInt.code, 0, 100000);
      final (a, bx) = decodeWideABx(words[1], words[2]);
      expect(a, 0);
      expect(bx, 100000);
    });

    test('max ranges: A=0xFFFF, Bx=0xFFFFFFFF', () {
      final words =
          encodeWideABx(Opcode.loadConst.code, 0xFFFF, 0xFFFFFFFF);
      final (a, bx) = decodeWideABx(words[1], words[2]);
      expect(a, 0xFFFF);
      expect(bx, 0xFFFFFFFF);
    });

    test('opcode preserved in third word', () {
      final words = encodeWideABx(Opcode.loadConstInt.code, 0, 70000);
      expect(decodeOp(words[2]), Opcode.loadConstInt.code);
    });
  });

  group('WIDE AsBx encoding', () {
    test('roundtrip positive', () {
      final words = encodeWideAsBx(Opcode.jump.code, 0, 100000);
      final (a, sbx) = decodeWideAsBx(words[1], words[2]);
      expect(a, 0);
      expect(sbx, 100000);
    });

    test('roundtrip negative', () {
      final words = encodeWideAsBx(Opcode.jump.code, 0, -100000);
      final (a, sbx) = decodeWideAsBx(words[1], words[2]);
      expect(a, 0);
      expect(sbx, -100000);
    });

    test('roundtrip zero', () {
      final words = encodeWideAsBx(Opcode.jump.code, 0, 0);
      final (a, sbx) = decodeWideAsBx(words[1], words[2]);
      expect(a, 0);
      expect(sbx, 0);
    });

    test('A extends to 16-bit range', () {
      final words = encodeWideAsBx(Opcode.jumpIfTrue.code, 500, 0);
      final (a, sbx) = decodeWideAsBx(words[1], words[2]);
      expect(a, 500);
      expect(sbx, 0);
    });

    test('max positive sBx: 2^31 - 1 range (excess-K)', () {
      // 32-bit unsigned max = 0xFFFFFFFF, K = 0x7FFFFFFF
      // max positive = 0xFFFFFFFF - 0x7FFFFFFF = 0x80000000 = 2147483648
      final words = encodeWideAsBx(Opcode.jump.code, 0, 2147483648);
      final (_, sbx) = decodeWideAsBx(words[1], words[2]);
      expect(sbx, 2147483648);
    });

    test('min negative sBx: -(2^31 - 1)', () {
      // min negative = 0 - 0x7FFFFFFF = -2147483647
      final words = encodeWideAsBx(Opcode.jump.code, 0, -2147483647);
      final (_, sbx) = decodeWideAsBx(words[1], words[2]);
      expect(sbx, -2147483647);
    });
  });

  group('WIDE Ax encoding', () {
    test('roundtrip small value', () {
      final words = encodeWideAx(Opcode.nop.code, 42);
      expect(words.length, 3);
      expect(decodeOp(words[0]), Opcode.wide.code);
      final ax = decodeWideAx(words[1], words[2]);
      expect(ax, 42);
    });

    test('extends to 48-bit range', () {
      // 24 bits from ext + 24 bits from original = 48 bits total
      const large = (1 << 40); // 2^40, well within 48-bit range
      final words = encodeWideAx(Opcode.nop.code, large);
      final ax = decodeWideAx(words[1], words[2]);
      expect(ax, large);
    });

    test('max 48-bit value', () {
      const max48 = (1 << 48) - 1;
      final words = encodeWideAx(Opcode.nop.code, max48);
      final ax = decodeWideAx(words[1], words[2]);
      expect(ax, max48);
    });

    test('opcode preserved', () {
      final words = encodeWideAx(Opcode.jumpAx.code, 0);
      expect(decodeOp(words[2]), Opcode.jumpAx.code);
    });
  });

  group('WIDE sAx encoding', () {
    test('roundtrip positive', () {
      final words = encodeWidesAx(Opcode.jumpAx.code, 100000);
      expect(words.length, 3);
      final sax = decodeWidesAx(words[1], words[2]);
      expect(sax, 100000);
    });

    test('roundtrip negative', () {
      final words = encodeWidesAx(Opcode.jumpAx.code, -100000);
      final sax = decodeWidesAx(words[1], words[2]);
      expect(sax, -100000);
    });

    test('roundtrip zero', () {
      final words = encodeWidesAx(Opcode.jumpAx.code, 0);
      final sax = decodeWidesAx(words[1], words[2]);
      expect(sax, 0);
    });

    test('large positive value', () {
      const large = (1 << 40);
      final words = encodeWidesAx(Opcode.jumpAx.code, large);
      final sax = decodeWidesAx(words[1], words[2]);
      expect(sax, large);
    });

    test('large negative value', () {
      const large = -(1 << 40);
      final words = encodeWidesAx(Opcode.jumpAx.code, large);
      final sax = decodeWidesAx(words[1], words[2]);
      expect(sax, large);
    });
  });
}
