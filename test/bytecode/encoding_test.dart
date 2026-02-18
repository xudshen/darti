import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:test/test.dart';

void main() {
  group('ABC encoding', () {
    test('roundtrip with zero values', () {
      final instr = encodeABC(Opcode.nop.code, 0, 0, 0);
      expect(decodeOp(instr), Opcode.nop.code);
      expect(decodeA(instr), 0);
      expect(decodeB(instr), 0);
      expect(decodeC(instr), 0);
    });

    test('roundtrip with max values', () {
      final instr = encodeABC(0xFF, 0xFF, 0xFF, 0xFF);
      expect(decodeOp(instr), 0xFF);
      expect(decodeA(instr), 0xFF);
      expect(decodeB(instr), 0xFF);
      expect(decodeC(instr), 0xFF);
    });

    test('operands are independent', () {
      final instr = encodeABC(Opcode.addInt.code, 1, 2, 3);
      expect(decodeOp(instr), Opcode.addInt.code);
      expect(decodeA(instr), 1);
      expect(decodeB(instr), 2);
      expect(decodeC(instr), 3);
    });

    test('bit layout: op in low 8 bits, A next 8, B next 8, C top 8', () {
      // op=0x10, A=0x20, B=0x30, C=0x40
      final instr = encodeABC(0x10, 0x20, 0x30, 0x40);
      expect(instr, 0x40302010);
    });
  });

  group('ABx encoding', () {
    test('roundtrip with zero values', () {
      final instr = encodeABx(Opcode.loadConst.code, 0, 0);
      expect(decodeOp(instr), Opcode.loadConst.code);
      expect(decodeA(instr), 0);
      expect(decodeBx(instr), 0);
    });

    test('roundtrip with max values', () {
      final instr = encodeABx(0xFF, 0xFF, 0xFFFF);
      expect(decodeOp(instr), 0xFF);
      expect(decodeA(instr), 0xFF);
      expect(decodeBx(instr), 0xFFFF);
    });

    test('Bx uses full 16-bit range', () {
      final instr = encodeABx(Opcode.loadConstInt.code, 5, 12345);
      expect(decodeOp(instr), Opcode.loadConstInt.code);
      expect(decodeA(instr), 5);
      expect(decodeBx(instr), 12345);
    });
  });

  group('AsBx encoding (excess-K, K=0x7FFF)', () {
    test('roundtrip zero', () {
      final instr = encodeAsBx(Opcode.jump.code, 0, 0);
      expect(decodeOp(instr), Opcode.jump.code);
      expect(decodeA(instr), 0);
      expect(decodesBx(instr), 0);
    });

    test('roundtrip positive max: +32768', () {
      final instr = encodeAsBx(Opcode.jumpIfTrue.code, 1, 32768);
      expect(decodesBx(instr), 32768);
    });

    test('roundtrip negative min: -32767', () {
      final instr = encodeAsBx(Opcode.jumpIfFalse.code, 2, -32767);
      expect(decodesBx(instr), -32767);
    });

    test('roundtrip negative one', () {
      final instr = encodeAsBx(Opcode.jump.code, 0, -1);
      expect(decodesBx(instr), -1);
    });

    test('excess-K encoding: value 0 encodes as 0x7FFF', () {
      final instr = encodeAsBx(Opcode.jump.code, 0, 0);
      expect(decodeBx(instr), 0x7FFF);
    });

    test('excess-K encoding: value -32767 encodes as 0', () {
      final instr = encodeAsBx(Opcode.jump.code, 0, -32767);
      expect(decodeBx(instr), 0);
    });

    test('excess-K encoding: value +32768 encodes as 0xFFFF', () {
      final instr = encodeAsBx(Opcode.jump.code, 0, 32768);
      expect(decodeBx(instr), 0xFFFF);
    });
  });

  group('Ax encoding', () {
    test('roundtrip zero', () {
      final instr = encodeAx(Opcode.nop.code, 0);
      expect(decodeOp(instr), Opcode.nop.code);
      expect(decodeAx(instr), 0);
    });

    test('roundtrip max: 0xFFFFFF (16777215)', () {
      final instr = encodeAx(0x01, 0xFFFFFF);
      expect(decodeAx(instr), 0xFFFFFF);
    });

    test('roundtrip mid value', () {
      final instr = encodeAx(Opcode.nop.code, 123456);
      expect(decodeAx(instr), 123456);
    });
  });

  group('sAx encoding (excess-K, K=0x7FFFFF)', () {
    test('roundtrip zero', () {
      final instr = encodesAx(Opcode.jumpAx.code, 0);
      expect(decodeOp(instr), Opcode.jumpAx.code);
      expect(decodesAx(instr), 0);
    });

    test('roundtrip positive max: +8388608', () {
      final instr = encodesAx(Opcode.jumpAx.code, 8388608);
      expect(decodesAx(instr), 8388608);
    });

    test('roundtrip negative min: -8388607', () {
      final instr = encodesAx(Opcode.jumpAx.code, -8388607);
      expect(decodesAx(instr), -8388607);
    });

    test('roundtrip negative one', () {
      final instr = encodesAx(Opcode.jumpAx.code, -1);
      expect(decodesAx(instr), -1);
    });

    test('excess-K encoding: value 0 encodes as 0x7FFFFF', () {
      final instr = encodesAx(Opcode.jumpAx.code, 0);
      expect(decodeAx(instr), 0x7FFFFF);
    });

    test('excess-K encoding: value -8388607 encodes as 0', () {
      final instr = encodesAx(Opcode.jumpAx.code, -8388607);
      expect(decodeAx(instr), 0);
    });

    test('excess-K encoding: value +8388608 encodes as 0xFFFFFF', () {
      final instr = encodesAx(Opcode.jumpAx.code, 8388608);
      expect(decodeAx(instr), 0xFFFFFF);
    });
  });

  group('cross-format operand extraction', () {
    test('decodeA consistent across ABC and ABx', () {
      final abc = encodeABC(0x10, 42, 0, 0);
      final abx = encodeABx(0x10, 42, 0);
      expect(decodeA(abc), 42);
      expect(decodeA(abx), 42);
    });

    test('decodeOp extracts low 8 bits only', () {
      // Even with all other bits set, op should be just low 8
      final instr = 0xFFFFFFFF;
      expect(decodeOp(instr), 0xFF);
    });
  });
}
