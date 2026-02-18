import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

/// Helper: builds a DarticModule with one function and optional constant pool.
DarticModule _module(
  Uint32List bytecode, {
  int valueRegCount = 0,
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

void main() {
  late DarticInterpreter interp;

  setUp(() {
    interp = DarticInterpreter();
  });

  // ── LOAD_CONST (0x01): refStack[A] = constPool.refs[Bx] ──

  group('LOAD_CONST', () {
    test('loads string from refs constant pool', () {
      final cp = ConstantPool();
      final idx = cp.addRef('hello');

      final module = _module(
        Uint32List.fromList([
          encodeABx(Opcode.loadConst.code, 0, idx),
          encodeAx(Opcode.halt.code, 0),
        ]),
        refRegCount: 1,
        constantPool: cp,
      );
      interp.execute(module);
      expect(interp.refStack.read(0), 'hello');
    });

    test('loads null from refs constant pool', () {
      final cp = ConstantPool();
      final idx = cp.addRef(null);

      final module = _module(
        Uint32List.fromList([
          encodeABx(Opcode.loadConst.code, 0, idx),
          encodeAx(Opcode.halt.code, 0),
        ]),
        refRegCount: 1,
        constantPool: cp,
      );
      interp.execute(module);
      expect(interp.refStack.read(0), isNull);
    });
  });

  // ── LOAD_NULL (0x02): refStack[A] = null ──

  group('LOAD_NULL', () {
    test('writes null to refStack', () {
      // Pre-fill slot with non-null to prove it gets overwritten.
      interp.refStack.write(0, 'old');
      interp.refStack.sp = 1;

      final module = _module(
        Uint32List.fromList([
          encodeABC(Opcode.loadNull.code, 0, 0, 0),
          encodeAx(Opcode.halt.code, 0),
        ]),
        refRegCount: 1,
      );
      // sp is already 1 from pre-fill; module adds refRegCount=1 → sp=2.
      // Slot 1 is the frame's register 0.
      // Wait — the frame base is the sp before execute, which is 1.
      // So register A=0 maps to refStack slot (rBase + A) = (1 + 0) = 1.
      interp.execute(module);
      expect(interp.refStack.read(1), isNull);
    });
  });

  // ── LOAD_TRUE (0x03): valueStack[A] = 1 ──
  // ── LOAD_FALSE (0x04): valueStack[A] = 0 ──

  group('LOAD_TRUE / LOAD_FALSE', () {
    test('LOAD_TRUE writes 1 to valueStack', () {
      final module = _module(
        Uint32List.fromList([
          encodeABC(Opcode.loadTrue.code, 0, 0, 0),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
      );
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 1);
    });

    test('LOAD_FALSE writes 0 to valueStack', () {
      // Pre-fill with non-zero.
      interp.valueStack.writeInt(0, 99);

      final module = _module(
        Uint32List.fromList([
          encodeABC(Opcode.loadFalse.code, 0, 0, 0),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
      );
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 0);
    });
  });

  // ── LOAD_INT (0x05): valueStack[A] = sBx ──

  group('LOAD_INT', () {
    test('loads positive immediate', () {
      final module = _module(
        Uint32List.fromList([
          encodeAsBx(Opcode.loadInt.code, 0, 42),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
      );
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 42);
    });

    test('loads negative immediate', () {
      final module = _module(
        Uint32List.fromList([
          encodeAsBx(Opcode.loadInt.code, 0, -100),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
      );
      interp.execute(module);
      expect(interp.valueStack.readInt(0), -100);
    });

    test('loads zero', () {
      final module = _module(
        Uint32List.fromList([
          encodeAsBx(Opcode.loadInt.code, 0, 0),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
      );
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 0);
    });

    test('loads max sBx value (+32768)', () {
      final module = _module(
        Uint32List.fromList([
          encodeAsBx(Opcode.loadInt.code, 0, 32768),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
      );
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 32768);
    });

    test('loads min sBx value (-32767)', () {
      final module = _module(
        Uint32List.fromList([
          encodeAsBx(Opcode.loadInt.code, 0, -32767),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
      );
      interp.execute(module);
      expect(interp.valueStack.readInt(0), -32767);
    });
  });

  // ── LOAD_CONST_INT (0x06): valueStack[A] = intConstPool[Bx] ──

  group('LOAD_CONST_INT', () {
    test('loads from int constant pool', () {
      final cp = ConstantPool();
      final idx = cp.addInt(9999999999);

      final module = _module(
        Uint32List.fromList([
          encodeABx(Opcode.loadConstInt.code, 0, idx),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
        constantPool: cp,
      );
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 9999999999);
    });
  });

  // ── LOAD_CONST_DBL (0x07): doubleView[A] = dblConstPool[Bx] ──

  group('LOAD_CONST_DBL', () {
    test('loads from double constant pool', () {
      final cp = ConstantPool();
      final idx = cp.addDouble(3.14);

      final module = _module(
        Uint32List.fromList([
          encodeABx(Opcode.loadConstDbl.code, 0, idx),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
        constantPool: cp,
      );
      interp.execute(module);
      expect(interp.valueStack.readDouble(0), 3.14);
    });
  });

  // ── MOVE_REF (0x08): refStack[A] = refStack[B] ──

  group('MOVE_REF', () {
    test('copies reference between slots', () {
      final module = _module(
        Uint32List.fromList([
          encodeABx(Opcode.loadConst.code, 1, 0), // load 'world' to slot 1
          encodeABC(Opcode.moveRef.code, 0, 1, 0), // copy slot 1 → slot 0
          encodeAx(Opcode.halt.code, 0),
        ]),
        refRegCount: 2,
        constantPool: ConstantPool()..addRef('world'),
      );
      interp.execute(module);
      expect(interp.refStack.read(0), 'world');
      expect(interp.refStack.read(1), 'world');
    });
  });

  // ── MOVE_VAL (0x09): valueStack[A] = valueStack[B] ──

  group('MOVE_VAL', () {
    test('copies value between slots', () {
      final module = _module(
        Uint32List.fromList([
          encodeAsBx(Opcode.loadInt.code, 1, 77), // slot 1 = 77
          encodeABC(Opcode.moveVal.code, 0, 1, 0), // copy slot 1 → slot 0
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 2,
      );
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 77);
      expect(interp.valueStack.readInt(1), 77);
    });
  });

  // ── BOX_INT (0x0C): refStack[A] = valueStack[B] (box int) ──

  group('BOX_INT', () {
    test('boxes int from valueStack to refStack', () {
      final module = _module(
        Uint32List.fromList([
          encodeAsBx(Opcode.loadInt.code, 0, 42), // valueStack[0] = 42
          encodeABC(Opcode.boxInt.code, 0, 0, 0), // refStack[0] = box(42)
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 1,
      );
      interp.execute(module);
      expect(interp.refStack.read(0), 42);
      expect(interp.refStack.read(0), isA<int>());
    });
  });

  // ── BOX_DOUBLE (0x0D): refStack[A] = doubleView[B] (box double) ──

  group('BOX_DOUBLE', () {
    test('boxes double from valueStack to refStack', () {
      final cp = ConstantPool();
      final idx = cp.addDouble(2.718);

      final module = _module(
        Uint32List.fromList([
          encodeABx(Opcode.loadConstDbl.code, 0, idx), // doubleView[0] = 2.718
          encodeABC(Opcode.boxDouble.code, 0, 0, 0), // refStack[0] = box(2.718)
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 1,
        constantPool: cp,
      );
      interp.execute(module);
      expect(interp.refStack.read(0), 2.718);
      expect(interp.refStack.read(0), isA<double>());
    });
  });

  // ── UNBOX_INT (0x0E): valueStack[A] = (refStack[B] as int) ──

  group('UNBOX_INT', () {
    test('unboxes int from refStack to valueStack', () {
      final cp = ConstantPool();
      final idx = cp.addRef(123);

      final module = _module(
        Uint32List.fromList([
          encodeABx(Opcode.loadConst.code, 0, idx), // refStack[0] = 123
          encodeABC(Opcode.unboxInt.code, 0, 0, 0), // valueStack[0] = 123
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 1,
        constantPool: cp,
      );
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 123);
    });
  });

  // ── UNBOX_DOUBLE (0x0F): doubleView[A] = (refStack[B] as double) ──

  group('UNBOX_DOUBLE', () {
    test('unboxes double from refStack to valueStack', () {
      final cp = ConstantPool();
      final idx = cp.addRef(1.5);

      final module = _module(
        Uint32List.fromList([
          encodeABx(Opcode.loadConst.code, 0, idx), // refStack[0] = 1.5
          encodeABC(Opcode.unboxDouble.code, 0, 0, 0), // doubleView[0] = 1.5
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 1,
        constantPool: cp,
      );
      interp.execute(module);
      expect(interp.valueStack.readDouble(0), 1.5);
    });
  });

  // ── LOAD_UPVALUE / STORE_UPVALUE are deferred (need closure support) ──
  // Placeholder tests for 0x0A and 0x0B — tested in closure batch.
}
