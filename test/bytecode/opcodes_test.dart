import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:test/test.dart';

void main() {
  group('Opcode values', () {
    test('all opcode values are in 0-255 range', () {
      for (final op in Opcode.values) {
        expect(op.code, inInclusiveRange(0, 255),
            reason: '${op.name} should be in 0-255 range');
      }
    });

    test('all opcode values are unique', () {
      final seen = <int>{};
      for (final op in Opcode.values) {
        expect(seen.add(op.code), isTrue,
            reason: '${op.name} (0x${op.code.toRadixString(16)}) is duplicate');
      }
    });

    // Load/Store group: 0x00-0x0F
    test('load/store opcodes are in correct range', () {
      expect(Opcode.nop.code, 0x00);
      expect(Opcode.loadConst.code, 0x01);
      expect(Opcode.loadNull.code, 0x02);
      expect(Opcode.loadTrue.code, 0x03);
      expect(Opcode.loadFalse.code, 0x04);
      expect(Opcode.loadInt.code, 0x05);
      expect(Opcode.loadConstInt.code, 0x06);
      expect(Opcode.loadConstDbl.code, 0x07);
      expect(Opcode.moveRef.code, 0x08);
      expect(Opcode.moveVal.code, 0x09);
      expect(Opcode.loadUpvalue.code, 0x0A);
      expect(Opcode.storeUpvalue.code, 0x0B);
      expect(Opcode.boxInt.code, 0x0C);
      expect(Opcode.boxDouble.code, 0x0D);
      expect(Opcode.unboxInt.code, 0x0E);
      expect(Opcode.unboxDouble.code, 0x0F);
    });

    // Integer arithmetic group: 0x10-0x1F
    test('integer arithmetic opcodes are in correct range', () {
      expect(Opcode.addInt.code, 0x10);
      expect(Opcode.subInt.code, 0x11);
      expect(Opcode.mulInt.code, 0x12);
      expect(Opcode.divInt.code, 0x13);
      expect(Opcode.modInt.code, 0x14);
      expect(Opcode.negInt.code, 0x15);
      expect(Opcode.bitAnd.code, 0x16);
      expect(Opcode.bitOr.code, 0x17);
      expect(Opcode.bitXor.code, 0x18);
      expect(Opcode.bitNot.code, 0x19);
      expect(Opcode.shl.code, 0x1A);
      expect(Opcode.shr.code, 0x1B);
      expect(Opcode.ushr.code, 0x1C);
      expect(Opcode.addIntImm.code, 0x1D);
    });

    // Float arithmetic group: 0x20-0x2F
    test('float arithmetic opcodes are in correct range', () {
      expect(Opcode.addDbl.code, 0x20);
      expect(Opcode.subDbl.code, 0x21);
      expect(Opcode.mulDbl.code, 0x22);
      expect(Opcode.divDbl.code, 0x23);
      expect(Opcode.negDbl.code, 0x24);
      expect(Opcode.intToDbl.code, 0x25);
      expect(Opcode.dblToInt.code, 0x26);
    });

    // Comparison group: 0x30-0x3F
    test('comparison opcodes are in correct range', () {
      expect(Opcode.ltInt.code, 0x30);
      expect(Opcode.leInt.code, 0x31);
      expect(Opcode.gtInt.code, 0x32);
      expect(Opcode.geInt.code, 0x33);
      expect(Opcode.eqInt.code, 0x34);
      expect(Opcode.ltDbl.code, 0x35);
      expect(Opcode.leDbl.code, 0x36);
      expect(Opcode.gtDbl.code, 0x37);
      expect(Opcode.geDbl.code, 0x38);
      expect(Opcode.eqDbl.code, 0x39);
      expect(Opcode.eqRef.code, 0x3A);
      expect(Opcode.eqGeneric.code, 0x3B);
    });

    // Control flow group: 0x40-0x4F
    test('control flow opcodes are in correct range', () {
      expect(Opcode.jump.code, 0x40);
      expect(Opcode.jumpIfTrue.code, 0x41);
      expect(Opcode.jumpIfFalse.code, 0x42);
      expect(Opcode.jumpIfNull.code, 0x43);
      expect(Opcode.jumpIfNnull.code, 0x44);
      expect(Opcode.jumpAx.code, 0x45);
    });

    // Call/Return group: 0x50-0x5F
    test('call and return opcodes are in correct range', () {
      expect(Opcode.call.code, 0x50);
      expect(Opcode.callStatic.code, 0x51);
      expect(Opcode.callHost.code, 0x52);
      expect(Opcode.callVirtual.code, 0x53);
      expect(Opcode.callSuper.code, 0x54);
      expect(Opcode.returnRef.code, 0x55);
      expect(Opcode.returnVal.code, 0x56);
      expect(Opcode.returnNull.code, 0x57);
    });

    // Object operations group: 0x60-0x6F
    test('object opcodes are in correct range', () {
      expect(Opcode.getFieldRef.code, 0x60);
      expect(Opcode.setFieldRef.code, 0x61);
      expect(Opcode.getFieldVal.code, 0x62);
      expect(Opcode.setFieldVal.code, 0x63);
      expect(Opcode.newInstance.code, 0x64);
      expect(Opcode.instanceOf.code, 0x65);
      expect(Opcode.cast.code, 0x66);
      expect(Opcode.getFieldDyn.code, 0x67);
      expect(Opcode.setFieldDyn.code, 0x68);
    });

    // Closure group: 0x70-0x77
    test('closure opcodes are in correct range', () {
      expect(Opcode.closure.code, 0x70);
      expect(Opcode.closeUpvalue.code, 0x71);
    });

    // Generics group: 0x78-0x7F
    test('generics opcodes are in correct range', () {
      expect(Opcode.pushIta.code, 0x78);
      expect(Opcode.pushFta.code, 0x79);
      expect(Opcode.loadTypeArg.code, 0x7A);
      expect(Opcode.instantiateType.code, 0x7B);
      expect(Opcode.createTypeArgs.code, 0x7C);
      expect(Opcode.allocGeneric.code, 0x7D);
      expect(Opcode.checkCovariant.code, 0x7E);
    });

    // Async group: 0x80-0x8F
    test('async opcodes are in correct range', () {
      expect(Opcode.initAsync.code, 0x80);
      expect(Opcode.await_.code, 0x81);
      expect(Opcode.asyncReturn.code, 0x82);
      expect(Opcode.asyncThrow.code, 0x83);
      expect(Opcode.initAsyncStar.code, 0x84);
      expect(Opcode.yield_.code, 0x85);
      expect(Opcode.yieldStar.code, 0x86);
      expect(Opcode.initSyncStar.code, 0x87);
      expect(Opcode.awaitStreamNext.code, 0x88);
    });

    // Collection group: 0x90-0x97
    test('collection opcodes are in correct range', () {
      expect(Opcode.createList.code, 0x90);
      expect(Opcode.createMap.code, 0x91);
      expect(Opcode.createSet.code, 0x92);
      expect(Opcode.createRecord.code, 0x93);
    });

    // String/Dynamic group: 0x98-0x9F
    test('string and dynamic opcodes are in correct range', () {
      expect(Opcode.stringInterp.code, 0x98);
      expect(Opcode.addGeneric.code, 0x99);
      expect(Opcode.invokeDyn.code, 0x9A);
    });

    // Global variable group: 0xA0-0xA3
    test('global variable opcodes are in correct range', () {
      expect(Opcode.loadGlobal.code, 0xA0);
      expect(Opcode.storeGlobal.code, 0xA1);
    });

    // Exception/Assert group: 0xA4-0xA7
    test('exception and assert opcodes are in correct range', () {
      expect(Opcode.throw_.code, 0xA4);
      expect(Opcode.rethrow_.code, 0xA5);
      expect(Opcode.assert_.code, 0xA6);
      expect(Opcode.nullCheck.code, 0xA7);
    });

    // System opcodes
    test('system opcodes WIDE and HALT at correct positions', () {
      expect(Opcode.wide.code, 0xFE);
      expect(Opcode.halt.code, 0xFF);
    });

    test('ILLEGAL opcodes fill reserved slots', () {
      // All reserved/unused slots should map to ILLEGAL
      final definedCodes = Opcode.values
          .where((op) => !op.name.startsWith('illegal'))
          .map((op) => op.code)
          .toSet();

      for (var i = 0; i <= 0xFF; i++) {
        if (!definedCodes.contains(i)) {
          final op = Opcode.byCode(i);
          expect(op.name, startsWith('illegal'),
              reason:
                  'Slot 0x${i.toRadixString(16)} should be ILLEGAL but is ${op.name}');
        }
      }
    });

    test('total defined (non-ILLEGAL) opcodes is 105', () {
      final defined = Opcode.values
          .where((op) => !op.name.startsWith('illegal'))
          .length;
      expect(defined, 105);
    });

    test('byCode returns correct opcode for all codes', () {
      for (var i = 0; i <= 0xFF; i++) {
        final op = Opcode.byCode(i);
        expect(op.code, i);
      }
    });
  });
}
