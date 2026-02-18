import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

/// End-to-end test: hand-construct bytecode, execute through interpreter,
/// verify results. This exercises the full pipeline: module → dispatch loop →
/// load/store → arithmetic → call/return → HALT.
void main() {
  test('add(1, 2) returns 3', () {
    // ── Function prototypes ──
    //
    // main (funcId=0): valueRegCount=1, refRegCount=0
    //   v0 = result register
    //   Outgoing args: written at v1=1, v2=2 (beyond valueRegCount)
    //
    //   0: LOAD_INT  v1 = 1        // arg0 for add (callee's v0)
    //   1: LOAD_INT  v2 = 2        // arg1 for add (callee's v1)
    //   2: CALL_STATIC A=0, Bx=1   // call add, result → v0
    //   3: HALT
    //
    // add (funcId=1): valueRegCount=3, refRegCount=0, paramCount=2
    //   v0 = param a (pre-laid by caller)
    //   v1 = param b (pre-laid by caller)
    //   v2 = temp
    //
    //   0: ADD_INT v2 = v0 + v1    // a + b
    //   1: RETURN_VAL v2

    final mainProto = DarticFuncProto(
      funcId: 0,
      bytecode: Uint32List.fromList([
        encodeAsBx(Opcode.loadInt.code, 1, 1), // v1 = 1
        encodeAsBx(Opcode.loadInt.code, 2, 2), // v2 = 2
        encodeABx(Opcode.callStatic.code, 0, 1), // call add → v0
        encodeAx(Opcode.halt.code, 0),
      ]),
      valueRegCount: 1,
      refRegCount: 0,
      paramCount: 0,
    );

    final addProto = DarticFuncProto(
      funcId: 1,
      bytecode: Uint32List.fromList([
        encodeABC(Opcode.addInt.code, 2, 0, 1), // v2 = v0 + v1
        encodeABC(Opcode.returnVal.code, 2, 0, 0), // return v2
      ]),
      valueRegCount: 3,
      refRegCount: 0,
      paramCount: 2,
    );

    final module = DarticModule(
      functions: [mainProto, addProto],
      constantPool: ConstantPool(),
      entryFuncId: 0,
    );

    final interp = DarticInterpreter();
    interp.execute(module);

    expect(interp.valueStack.readInt(0), 3);
  });

  test('factorial(5) returns 120 via recursive calls', () {
    // ── Function prototypes ──
    //
    // main (funcId=0): valueRegCount=1
    //   Writes arg at v1=5, calls factorial, result → v0.
    //
    //   0: LOAD_INT v1 = 5
    //   1: CALL_STATIC A=0, Bx=1
    //   2: HALT
    //
    // factorial (funcId=1): valueRegCount=4, paramCount=1
    //   v0 = n (param), v1 = temp (n==0?), v2 = temp, v3 = n-1/result
    //
    //   0: LOAD_INT v1 = 0               // constant 0
    //   1: EQ_INT   v2 = (v0 == v1)      // v2 = (n == 0) ? 1 : 0
    //   2: JUMP_IF_FALSE v2, +2          // if n != 0, skip to recursive case
    //   3: LOAD_INT v0 = 1               // base case: return 1
    //   4: RETURN_VAL v0
    //   5: LOAD_INT v1 = 1               // constant 1
    //   6: SUB_INT  v3 = v0 - v1         // v3 = n - 1
    //   -- place arg for recursive call: callee's v0 = v3
    //   7: MOVE_VAL v4 = v3              // write arg at callee's v0 position
    //   8: CALL_STATIC A=3, Bx=1         // factorial(n-1), result → v3
    //   9: MUL_INT  v0 = v0 * v3         // n * factorial(n-1)
    //  10: RETURN_VAL v0

    final mainProto = DarticFuncProto(
      funcId: 0,
      bytecode: Uint32List.fromList([
        encodeAsBx(Opcode.loadInt.code, 1, 5), // arg = 5
        encodeABx(Opcode.callStatic.code, 0, 1), // call factorial → v0
        encodeAx(Opcode.halt.code, 0),
      ]),
      valueRegCount: 1,
      refRegCount: 0,
      paramCount: 0,
    );

    final factProto = DarticFuncProto(
      funcId: 1,
      bytecode: Uint32List.fromList([
        encodeAsBx(Opcode.loadInt.code, 1, 0), // v1 = 0
        encodeABC(Opcode.eqInt.code, 2, 0, 1), // v2 = (n == 0)
        encodeAsBx(Opcode.jumpIfFalse.code, 2, 2), // skip if n != 0
        encodeAsBx(Opcode.loadInt.code, 0, 1), // return 1
        encodeABC(Opcode.returnVal.code, 0, 0, 0),
        encodeAsBx(Opcode.loadInt.code, 1, 1), // v1 = 1
        encodeABC(Opcode.subInt.code, 3, 0, 1), // v3 = n - 1
        encodeABC(Opcode.moveVal.code, 4, 3, 0), // callee arg0 = v3
        encodeABx(Opcode.callStatic.code, 3, 1), // factorial(n-1) → v3
        encodeABC(Opcode.mulInt.code, 0, 0, 3), // v0 = n * factorial(n-1)
        encodeABC(Opcode.returnVal.code, 0, 0, 0),
      ]),
      valueRegCount: 4,
      refRegCount: 0,
      paramCount: 1,
    );

    final module = DarticModule(
      functions: [mainProto, factProto],
      constantPool: ConstantPool(),
      entryFuncId: 0,
    );

    final interp = DarticInterpreter();
    interp.execute(module);

    expect(interp.valueStack.readInt(0), 120);
  });

  test('string identity comparison via ref stack', () {
    // Tests ref stack + constant pool + comparison in a single flow.
    //
    // main: load two refs from constant pool, compare identity, store result.
    //   0: LOAD_CONST r0 = "hello"
    //   1: LOAD_CONST r1 = "hello"   (same pool index → identical)
    //   2: EQ_REF     v0 = identical(r0, r1)
    //   3: HALT

    final cp = ConstantPool();
    final idx = cp.addRef('hello');

    final mainProto = DarticFuncProto(
      funcId: 0,
      bytecode: Uint32List.fromList([
        encodeABx(Opcode.loadConst.code, 0, idx), // r0 = 'hello'
        encodeABx(Opcode.loadConst.code, 1, idx), // r1 = 'hello' (same ref)
        encodeABC(Opcode.eqRef.code, 0, 0, 1), // v0 = identical(r0, r1)
        encodeAx(Opcode.halt.code, 0),
      ]),
      valueRegCount: 1,
      refRegCount: 2,
      paramCount: 0,
    );

    final module = DarticModule(
      functions: [mainProto],
      constantPool: cp,
      entryFuncId: 0,
    );

    final interp = DarticInterpreter();
    interp.execute(module);

    expect(interp.valueStack.readInt(0), 1); // identical → true
  });
}
