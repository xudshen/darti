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
  int refRegCount = 2,
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
    constantPool: ConstantPool(),
    entryFuncId: 0,
  );
}

void main() {
  late DarticInterpreter interp;

  setUp(() {
    interp = DarticInterpreter();
  });

  // ── JUMP (0x40): PC += sBx ──

  group('JUMP', () {
    test('forward jump skips instructions', () {
      // Instruction layout (indices):
      //   0: JUMP +2        → PC becomes 0+1+2 = 3
      //   1: LOAD_INT v0=99 (skipped)
      //   2: LOAD_INT v0=99 (skipped)
      //   3: LOAD_INT v0=42
      //   4: HALT
      final module = _module(Uint32List.fromList([
        encodeAsBx(Opcode.jump.code, 0, 2), // pc=0, after fetch pc=1, +2→3
        encodeAsBx(Opcode.loadInt.code, 0, 99),
        encodeAsBx(Opcode.loadInt.code, 0, 99),
        encodeAsBx(Opcode.loadInt.code, 0, 42),
        encodeAx(Opcode.halt.code, 0),
      ]));
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 42);
    });

    test('backward jump creates a loop', () {
      // Accumulate: v0 = 0, v1 = 3 (counter).
      // Loop body: v0 += 1, v1 -= 1, if v1 != 0 jump back.
      // Result: v0 = 3.
      //
      //   0: LOAD_INT v0=0         (accumulator)
      //   1: LOAD_INT v1=3         (counter)
      //   2: ADD_INT_IMM v0=v0+1   ← loop start
      //   3: ADD_INT_IMM v1=v1+(-1) — use SUB: we'll do v2=1, then SUB v1=v1-v2
      // Actually, ADD_INT_IMM C is unsigned [0,255], can't subtract.
      // Use a different approach: decrement via LOAD_INT + SUB_INT.
      //
      //   0: LOAD_INT v0=0         accumulator
      //   1: LOAD_INT v1=3         counter
      //   2: LOAD_INT v2=1         decrement constant
      //   3: ADD_INT  v0=v0+v2     ← loop body start (v0 += 1)
      //   4: SUB_INT  v1=v1-v2     (counter -= 1)
      //   5: JUMP_IF_TRUE v1, -3   if v1!=0 → pc=5+1+(-3)=3 (loop body)
      //   6: HALT
      final module = _module(Uint32List.fromList([
        encodeAsBx(Opcode.loadInt.code, 0, 0), // v0 = 0
        encodeAsBx(Opcode.loadInt.code, 1, 3), // v1 = 3
        encodeAsBx(Opcode.loadInt.code, 2, 1), // v2 = 1
        encodeABC(Opcode.addInt.code, 0, 0, 2), // v0 += v2
        encodeABC(Opcode.subInt.code, 1, 1, 2), // v1 -= v2
        encodeAsBx(Opcode.jumpIfTrue.code, 1, -3), // if v1 != 0 → pc=3
        encodeAx(Opcode.halt.code, 0),
      ]));
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 3);
      expect(interp.valueStack.readInt(1), 0);
    });
  });

  // ── JUMP_IF_TRUE (0x41): if valueStack[A] != 0 then PC += sBx ──

  group('JUMP_IF_TRUE', () {
    test('jumps when condition is true (non-zero)', () {
      //   0: LOAD_TRUE v0
      //   1: JUMP_IF_TRUE v0, +1  → pc = 1+1+1 = 3
      //   2: LOAD_INT v1=99       (skipped)
      //   3: LOAD_INT v1=42
      //   4: HALT
      final module = _module(Uint32List.fromList([
        encodeABC(Opcode.loadTrue.code, 0, 0, 0),
        encodeAsBx(Opcode.jumpIfTrue.code, 0, 1),
        encodeAsBx(Opcode.loadInt.code, 1, 99),
        encodeAsBx(Opcode.loadInt.code, 1, 42),
        encodeAx(Opcode.halt.code, 0),
      ]));
      interp.execute(module);
      expect(interp.valueStack.readInt(1), 42);
    });

    test('falls through when condition is false (zero)', () {
      //   0: LOAD_FALSE v0
      //   1: JUMP_IF_TRUE v0, +1  → no jump
      //   2: LOAD_INT v1=42       (executed)
      //   3: HALT
      final module = _module(Uint32List.fromList([
        encodeABC(Opcode.loadFalse.code, 0, 0, 0),
        encodeAsBx(Opcode.jumpIfTrue.code, 0, 1),
        encodeAsBx(Opcode.loadInt.code, 1, 42),
        encodeAx(Opcode.halt.code, 0),
      ]));
      interp.execute(module);
      expect(interp.valueStack.readInt(1), 42);
    });
  });

  // ── JUMP_IF_FALSE (0x42): if valueStack[A] == 0 then PC += sBx ──

  group('JUMP_IF_FALSE', () {
    test('jumps when condition is false (zero)', () {
      final module = _module(Uint32List.fromList([
        encodeABC(Opcode.loadFalse.code, 0, 0, 0),
        encodeAsBx(Opcode.jumpIfFalse.code, 0, 1),
        encodeAsBx(Opcode.loadInt.code, 1, 99),
        encodeAsBx(Opcode.loadInt.code, 1, 42),
        encodeAx(Opcode.halt.code, 0),
      ]));
      interp.execute(module);
      expect(interp.valueStack.readInt(1), 42);
    });

    test('falls through when condition is true (non-zero)', () {
      final module = _module(Uint32List.fromList([
        encodeABC(Opcode.loadTrue.code, 0, 0, 0),
        encodeAsBx(Opcode.jumpIfFalse.code, 0, 1),
        encodeAsBx(Opcode.loadInt.code, 1, 42),
        encodeAx(Opcode.halt.code, 0),
      ]));
      interp.execute(module);
      expect(interp.valueStack.readInt(1), 42);
    });
  });

  // ── JUMP_IF_NULL (0x43): if refStack[A] == null then PC += sBx ──

  group('JUMP_IF_NULL', () {
    test('jumps when ref is null', () {
      final module = _module(Uint32List.fromList([
        encodeABC(Opcode.loadNull.code, 0, 0, 0),
        encodeAsBx(Opcode.jumpIfNull.code, 0, 1),
        encodeAsBx(Opcode.loadInt.code, 0, 99),
        encodeAsBx(Opcode.loadInt.code, 0, 42),
        encodeAx(Opcode.halt.code, 0),
      ]));
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 42);
    });

    test('falls through when ref is non-null', () {
      final cp = ConstantPool()..addRef('x');
      final module = _module(
        Uint32List.fromList([
          encodeABx(Opcode.loadConst.code, 0, 0),
          encodeAsBx(Opcode.jumpIfNull.code, 0, 1),
          encodeAsBx(Opcode.loadInt.code, 0, 42),
          encodeAx(Opcode.halt.code, 0),
        ]),
      );
      // Override constantPool by creating module manually.
      final proto = DarticFuncProto(
        funcId: 0,
        bytecode: Uint32List.fromList([
          encodeABx(Opcode.loadConst.code, 0, 0),
          encodeAsBx(Opcode.jumpIfNull.code, 0, 1),
          encodeAsBx(Opcode.loadInt.code, 0, 42),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 4,
        refRegCount: 2,
        paramCount: 0,
      );
      final mod = DarticModule(
        functions: [proto],
        constantPool: cp,
        entryFuncId: 0,
      );
      interp.execute(mod);
      // Falls through, so v0 = 42
      expect(interp.valueStack.readInt(0), 42);
    });
  });

  // ── JUMP_IF_NNULL (0x44): if refStack[A] != null then PC += sBx ──

  group('JUMP_IF_NNULL', () {
    test('jumps when ref is non-null', () {
      final cp = ConstantPool()..addRef('x');
      final proto = DarticFuncProto(
        funcId: 0,
        bytecode: Uint32List.fromList([
          encodeABx(Opcode.loadConst.code, 0, 0),
          encodeAsBx(Opcode.jumpIfNnull.code, 0, 1),
          encodeAsBx(Opcode.loadInt.code, 0, 99),
          encodeAsBx(Opcode.loadInt.code, 0, 42),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 4,
        refRegCount: 2,
        paramCount: 0,
      );
      final mod = DarticModule(
        functions: [proto],
        constantPool: cp,
        entryFuncId: 0,
      );
      interp.execute(mod);
      expect(interp.valueStack.readInt(0), 42);
    });

    test('falls through when ref is null', () {
      final module = _module(Uint32List.fromList([
        encodeABC(Opcode.loadNull.code, 0, 0, 0),
        encodeAsBx(Opcode.jumpIfNnull.code, 0, 1),
        encodeAsBx(Opcode.loadInt.code, 0, 42),
        encodeAx(Opcode.halt.code, 0),
      ]));
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 42);
    });
  });

  // ── JUMP_AX (0x45): PC += sAx (24-bit signed offset) ──

  group('JUMP_AX', () {
    test('forward jump with 24-bit offset', () {
      //   0: JUMP_AX +2  → pc=0+1+2=3
      //   1: LOAD_INT v0=99
      //   2: LOAD_INT v0=99
      //   3: LOAD_INT v0=42
      //   4: HALT
      final module = _module(Uint32List.fromList([
        encodesAx(Opcode.jumpAx.code, 2),
        encodeAsBx(Opcode.loadInt.code, 0, 99),
        encodeAsBx(Opcode.loadInt.code, 0, 99),
        encodeAsBx(Opcode.loadInt.code, 0, 42),
        encodeAx(Opcode.halt.code, 0),
      ]));
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 42);
    });
  });

  // ── Integration: loop summing 1 to 10 ──

  group('loop integration', () {
    test('sum 1 to 10 using backward jump', () {
      // v0 = sum (accumulator), v1 = i (counter), v2 = 10 (limit), v3 = 1
      //
      //   0: LOAD_INT v0=0
      //   1: LOAD_INT v1=0
      //   2: LOAD_INT v2=10
      //   3: LOAD_INT v3=1
      //   4: ADD_INT  v1=v1+v3    ← loop: i++
      //   5: ADD_INT  v0=v0+v1    sum += i
      //   6: LT_INT   v3=v1<v2 (reuse v3 as temp bool) — wait, v3 is our "1" constant!
      // Better: use 5 regs.
      //   0: LOAD_INT v0=0        sum
      //   1: LOAD_INT v1=1        i (start at 1)
      //   2: LOAD_INT v2=10       limit
      //   3: ADD_INT  v0=v0+v1    ← loop: sum += i
      //   4: ADD_INT_IMM v1=v1+1  i++
      //   5: LE_INT  v3=v1<=v2    v3 = (i <= 10) ? 1 : 0
      //   6: JUMP_IF_TRUE v3, -4  if v3 → pc = 6+1+(-4) = 3
      //   7: HALT
      final module = _module(
        Uint32List.fromList([
          encodeAsBx(Opcode.loadInt.code, 0, 0), // v0 = 0 (sum)
          encodeAsBx(Opcode.loadInt.code, 1, 1), // v1 = 1 (i)
          encodeAsBx(Opcode.loadInt.code, 2, 10), // v2 = 10
          encodeABC(Opcode.addInt.code, 0, 0, 1), // sum += i
          encodeABC(Opcode.addIntImm.code, 1, 1, 1), // i++
          encodeABC(Opcode.leInt.code, 3, 1, 2), // v3 = (i <= 10)
          encodeAsBx(Opcode.jumpIfTrue.code, 3, -4), // loop if true
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 5,
      );
      interp.execute(module);
      // sum = 1+2+3+4+5+6+7+8+9+10 = 55
      expect(interp.valueStack.readInt(0), 55);
    });
  });
}
