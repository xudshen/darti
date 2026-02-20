import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:test/test.dart';

void main() {
  group('Op values', () {
    // Load/Store group: 0x00-0x0B
    test('load/store opcodes are in correct range', () {
      expect(Op.nop, 0x00);
      expect(Op.loadConst, 0x01);
      expect(Op.loadNull, 0x02);
      expect(Op.loadTrue, 0x03);
      expect(Op.loadFalse, 0x04);
      expect(Op.loadInt, 0x05);
      expect(Op.loadConstInt, 0x06);
      expect(Op.loadConstDbl, 0x07);
      expect(Op.moveRef, 0x08);
      expect(Op.moveVal, 0x09);
      expect(Op.loadUpvalue, 0x0A);
      expect(Op.storeUpvalue, 0x0B);
    });

    // Integer arithmetic group: 0x10-0x1F
    test('integer arithmetic opcodes are in correct range', () {
      expect(Op.addInt, 0x10);
      expect(Op.subInt, 0x11);
      expect(Op.mulInt, 0x12);
      expect(Op.divInt, 0x13);
      expect(Op.modInt, 0x14);
      expect(Op.negInt, 0x15);
      expect(Op.bitAnd, 0x16);
      expect(Op.bitOr, 0x17);
      expect(Op.bitXor, 0x18);
      expect(Op.bitNot, 0x19);
      expect(Op.shl, 0x1A);
      expect(Op.shr, 0x1B);
      expect(Op.ushr, 0x1C);
      expect(Op.addIntImm, 0x1D);
    });

    // Float arithmetic group: 0x20-0x24
    test('float arithmetic opcodes are in correct range', () {
      expect(Op.addDbl, 0x20);
      expect(Op.subDbl, 0x21);
      expect(Op.mulDbl, 0x22);
      expect(Op.divDbl, 0x23);
      expect(Op.negDbl, 0x24);
    });

    // Type Conversion & Boxing group: 0x25-0x2D
    test('type conversion and boxing opcodes are in correct range', () {
      expect(Op.intToDbl, 0x25);
      expect(Op.dblToInt, 0x26);
      expect(Op.boxInt, 0x27);
      expect(Op.boxDouble, 0x28);
      expect(Op.boxBool, 0x29);
      expect(Op.unboxInt, 0x2A);
      expect(Op.unboxDouble, 0x2B);
      expect(Op.unboxBool, 0x2C);
      expect(Op.notBool, 0x2D);
    });

    // Comparison group: 0x30-0x3F
    test('comparison opcodes are in correct range', () {
      expect(Op.ltInt, 0x30);
      expect(Op.leInt, 0x31);
      expect(Op.gtInt, 0x32);
      expect(Op.geInt, 0x33);
      expect(Op.eqInt, 0x34);
      expect(Op.ltDbl, 0x35);
      expect(Op.leDbl, 0x36);
      expect(Op.gtDbl, 0x37);
      expect(Op.geDbl, 0x38);
      expect(Op.eqDbl, 0x39);
      expect(Op.eqRef, 0x3A);
      expect(Op.eqGeneric, 0x3B);
    });

    // Control flow group: 0x40-0x4F
    test('control flow opcodes are in correct range', () {
      expect(Op.jump, 0x40);
      expect(Op.jumpIfTrue, 0x41);
      expect(Op.jumpIfFalse, 0x42);
      expect(Op.jumpIfNull, 0x43);
      expect(Op.jumpIfNnull, 0x44);
      expect(Op.jumpAx, 0x45);
    });

    // Call/Return group: 0x50-0x5F
    test('call and return opcodes are in correct range', () {
      expect(Op.call, 0x50);
      expect(Op.callStatic, 0x51);
      expect(Op.callHost, 0x52);
      expect(Op.callVirtual, 0x53);
      expect(Op.callSuper, 0x54);
      expect(Op.returnRef, 0x55);
      expect(Op.returnVal, 0x56);
      expect(Op.returnNull, 0x57);
    });

    // Object operations group: 0x60-0x6F
    test('object opcodes are in correct range', () {
      expect(Op.getFieldRef, 0x60);
      expect(Op.setFieldRef, 0x61);
      expect(Op.getFieldVal, 0x62);
      expect(Op.setFieldVal, 0x63);
      expect(Op.newInstance, 0x64);
      expect(Op.instanceOf, 0x65);
      expect(Op.cast, 0x66);
      expect(Op.getFieldDyn, 0x67);
      expect(Op.setFieldDyn, 0x68);
    });

    // Closure group: 0x70-0x77
    test('closure opcodes are in correct range', () {
      expect(Op.closure, 0x70);
      expect(Op.closeUpvalue, 0x71);
    });

    // Generics group: 0x78-0x7F
    test('generics opcodes are in correct range', () {
      expect(Op.pushIta, 0x78);
      expect(Op.pushFta, 0x79);
      expect(Op.loadTypeArg, 0x7A);
      expect(Op.instantiateType, 0x7B);
      expect(Op.createTypeArgs, 0x7C);
      expect(Op.allocGeneric, 0x7D);
      expect(Op.checkCovariant, 0x7E);
    });

    // Async group: 0x80-0x8F
    test('async opcodes are in correct range', () {
      expect(Op.initAsync, 0x80);
      expect(Op.await_, 0x81);
      expect(Op.asyncReturn, 0x82);
      expect(Op.asyncThrow, 0x83);
      expect(Op.initAsyncStar, 0x84);
      expect(Op.yield_, 0x85);
      expect(Op.yieldStar, 0x86);
      expect(Op.initSyncStar, 0x87);
      expect(Op.awaitStreamNext, 0x88);
    });

    // Collection group: 0x90-0x97
    test('collection opcodes are in correct range', () {
      expect(Op.createList, 0x90);
      expect(Op.createMap, 0x91);
      expect(Op.createSet, 0x92);
      expect(Op.createRecord, 0x93);
    });

    // String/Dynamic group: 0x98-0x9F
    test('string and dynamic opcodes are in correct range', () {
      expect(Op.stringInterp, 0x98);
      expect(Op.addGeneric, 0x99);
      expect(Op.invokeDyn, 0x9A);
    });

    // Global variable group: 0xA0-0xA3
    test('global variable opcodes are in correct range', () {
      expect(Op.loadGlobal, 0xA0);
      expect(Op.storeGlobal, 0xA1);
    });

    // Exception/Assert group: 0xA4-0xA7
    test('exception and assert opcodes are in correct range', () {
      expect(Op.throw_, 0xA4);
      expect(Op.rethrow_, 0xA5);
      expect(Op.assert_, 0xA6);
      expect(Op.nullCheck, 0xA7);
    });

    // System opcodes
    test('system opcodes WIDE and HALT at correct positions', () {
      expect(Op.wide, 0xFE);
      expect(Op.halt, 0xFF);
    });
  });
}
