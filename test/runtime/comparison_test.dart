import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

DarticModule _module(
  Uint32List bytecode, {
  int valueRegCount = 4,
  int refRegCount = 0,
  ConstantPool? constantPool,
}) {
  final proto = DarticFuncProto(
    funcId: 0,
    bytecode: bytecode,
    valueRegCount: valueRegCount,
    refRegCount: refRegCount,
    paramCount: 0,
  );
  return DarticModule(
    functions: [proto],
    constantPool: constantPool ?? ConstantPool(),
    entryFuncId: 0,
  );
}

/// Builds: LOAD_INT slot0=a, LOAD_INT slot1=b, cmp slot2, HALT.
Uint32List _cmpInt(int opcode, int a, int b) {
  return Uint32List.fromList([
    encodeAsBx(Opcode.loadInt.code, 0, a),
    encodeAsBx(Opcode.loadInt.code, 1, b),
    encodeABC(opcode, 2, 0, 1),
    encodeAx(Opcode.halt.code, 0),
  ]);
}

void main() {
  late DarticInterpreter interp;

  setUp(() {
    interp = DarticInterpreter();
  });

  // ── LT_INT (0x30) ──

  group('LT_INT', () {
    test('less than → 1', () {
      interp.execute(_module(_cmpInt(Opcode.ltInt.code, 3, 5)));
      expect(interp.valueStack.readInt(2), 1);
    });

    test('equal → 0', () {
      interp.execute(_module(_cmpInt(Opcode.ltInt.code, 5, 5)));
      expect(interp.valueStack.readInt(2), 0);
    });

    test('greater → 0', () {
      interp.execute(_module(_cmpInt(Opcode.ltInt.code, 7, 5)));
      expect(interp.valueStack.readInt(2), 0);
    });
  });

  // ── LE_INT (0x31) ──

  group('LE_INT', () {
    test('less than → 1', () {
      interp.execute(_module(_cmpInt(Opcode.leInt.code, 3, 5)));
      expect(interp.valueStack.readInt(2), 1);
    });

    test('equal → 1', () {
      interp.execute(_module(_cmpInt(Opcode.leInt.code, 5, 5)));
      expect(interp.valueStack.readInt(2), 1);
    });

    test('greater → 0', () {
      interp.execute(_module(_cmpInt(Opcode.leInt.code, 7, 5)));
      expect(interp.valueStack.readInt(2), 0);
    });
  });

  // ── GT_INT (0x32) ──

  group('GT_INT', () {
    test('greater → 1', () {
      interp.execute(_module(_cmpInt(Opcode.gtInt.code, 7, 5)));
      expect(interp.valueStack.readInt(2), 1);
    });

    test('equal → 0', () {
      interp.execute(_module(_cmpInt(Opcode.gtInt.code, 5, 5)));
      expect(interp.valueStack.readInt(2), 0);
    });
  });

  // ── GE_INT (0x33) ──

  group('GE_INT', () {
    test('greater → 1', () {
      interp.execute(_module(_cmpInt(Opcode.geInt.code, 7, 5)));
      expect(interp.valueStack.readInt(2), 1);
    });

    test('equal → 1', () {
      interp.execute(_module(_cmpInt(Opcode.geInt.code, 5, 5)));
      expect(interp.valueStack.readInt(2), 1);
    });

    test('less → 0', () {
      interp.execute(_module(_cmpInt(Opcode.geInt.code, 3, 5)));
      expect(interp.valueStack.readInt(2), 0);
    });
  });

  // ── EQ_INT (0x34) ──

  group('EQ_INT', () {
    test('equal → 1', () {
      interp.execute(_module(_cmpInt(Opcode.eqInt.code, 42, 42)));
      expect(interp.valueStack.readInt(2), 1);
    });

    test('not equal → 0', () {
      interp.execute(_module(_cmpInt(Opcode.eqInt.code, 42, 43)));
      expect(interp.valueStack.readInt(2), 0);
    });
  });

  // ── EQ_REF (0x3A): valueStack[A] = identical(refStack[B], refStack[C]) ? 1 : 0 ──

  group('EQ_REF', () {
    test('same reference → 1', () {
      final cp = ConstantPool();
      final idx = cp.addRef('same');

      final module = _module(
        Uint32List.fromList([
          encodeABx(Opcode.loadConst.code, 0, idx), // refStack[0] = 'same'
          encodeABx(Opcode.loadConst.code, 1, idx), // refStack[1] = 'same'
          encodeABC(Opcode.eqRef.code, 0, 0, 1), // valueStack[0] = identical?
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 2,
        constantPool: cp,
      );
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 1);
    });

    test('different references → 0', () {
      final cp = ConstantPool();
      final idx0 = cp.addRef('aaa');
      final idx1 = cp.addRef('bbb');

      final module = _module(
        Uint32List.fromList([
          encodeABx(Opcode.loadConst.code, 0, idx0),
          encodeABx(Opcode.loadConst.code, 1, idx1),
          encodeABC(Opcode.eqRef.code, 0, 0, 1),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 2,
        constantPool: cp,
      );
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 0);
    });

    test('both null → 1', () {
      final module = _module(
        Uint32List.fromList([
          encodeABC(Opcode.loadNull.code, 0, 0, 0),
          encodeABC(Opcode.loadNull.code, 1, 0, 0),
          encodeABC(Opcode.eqRef.code, 0, 0, 1),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 2,
      );
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 1);
    });
  });
}
