import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/closure.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Upvalue', () {
    test('open upvalue has correct stackIndex', () {
      final uv = Upvalue.open(5);
      expect(uv.isOpen, true);
      expect(uv.stackIndex, 5);
    });

    test('closed upvalue holds value directly', () {
      final uv = Upvalue.closed(42);
      expect(uv.isOpen, false);
      expect(uv.value, 42);
    });

    test('close transitions open to closed', () {
      final uv = Upvalue.open(3);
      expect(uv.isOpen, true);

      uv.close('captured');
      expect(uv.isOpen, false);
      expect(uv.value, 'captured');
    });

    test('closed upvalue value can be updated via setter', () {
      final uv = Upvalue.closed(10);
      expect(uv.value, 10);

      uv.value = 20;
      expect(uv.value, 20);
    });

    test('close with null value', () {
      final uv = Upvalue.open(0);
      uv.close(null);
      expect(uv.isOpen, false);
      expect(uv.value, isNull);
    });
  });

  group('DarticClosure', () {
    test('holds funcProto and upvalues', () {
      final proto = DarticFuncProto(
        funcId: 1,
        name: 'inner',
        bytecode: Uint32List(0),
        valueRegCount: 0,
        refRegCount: 0,
        paramCount: 0,
      );
      final upvalues = [Upvalue.closed(42), Upvalue.open(3)];
      final closure = DarticClosure(funcProto: proto, upvalues: upvalues);

      expect(closure.funcProto.funcId, 1);
      expect(closure.funcProto.name, 'inner');
      expect(closure.upvalues.length, 2);
      expect(closure.upvalues[0].value, 42);
      expect(closure.upvalues[1].isOpen, true);
    });

    test('toString includes name and upvalue count', () {
      final proto = DarticFuncProto(
        funcId: 5,
        name: 'myClosure',
        bytecode: Uint32List(0),
        valueRegCount: 0,
        refRegCount: 0,
        paramCount: 0,
      );
      final closure = DarticClosure(funcProto: proto, upvalues: []);
      expect(closure.toString(), contains('myClosure'));
      expect(closure.toString(), contains('upvalues=0'));
    });

    test('upvalues are shared references', () {
      // Two closures sharing the same upvalue cell see each other's writes.
      final shared = Upvalue.closed(100);
      final proto = DarticFuncProto(
        funcId: 0,
        bytecode: Uint32List(0),
        valueRegCount: 0,
        refRegCount: 0,
        paramCount: 0,
      );
      final c1 = DarticClosure(funcProto: proto, upvalues: [shared]);
      final c2 = DarticClosure(funcProto: proto, upvalues: [shared]);

      c1.upvalues[0].value = 200;
      expect(c2.upvalues[0].value, 200);
    });
  });

  group('CLOSURE + CALL + LOAD_UPVALUE interpreter', () {
    late DarticInterpreter interp;

    setUp(() {
      interp = DarticInterpreter();
    });

    test('CLOSURE creates closure and CALL invokes it', () {
      // Scenario: main creates a closure over inner function, then calls it.
      // inner returns a constant 42.
      //
      // inner (funcId=1): LOAD_INT v0=42, RETURN_VAL v0
      //   valueRegCount=1, refRegCount=0, paramCount=0, no upvalues
      //
      // main (funcId=0): refRegCount=1 (r0 = closure)
      //   CLOSURE r0, funcId=1    — create closure from funcProto[1]
      //   CALL A=0, B=0, C=0     — call closure in r0, result to v0
      //   HALT
      //
      // Expected: v0 = 42

      final innerProto = DarticFuncProto(
        funcId: 1,
        name: 'inner',
        bytecode: Uint32List.fromList([
          encodeAsBx(Op.loadInt, 0, 42),
          encodeABC(Op.returnVal, 0, 0, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 0,
        paramCount: 0,
        upvalueDescriptors: [],
      );

      final mainProto = DarticFuncProto(
        funcId: 0,
        name: 'main',
        bytecode: Uint32List.fromList([
          encodeABx(Op.closure, 0, 1), // r0 = closure(funcProto[1])
          encodeABC(Op.call, 0, 0, 0), // call r0, result → v0
          encodeAx(Op.halt, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 1,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [mainProto, innerProto],
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

      interp.execute(module);
      expect(interp.valueStack.readInt(0), 42);
    });

    test('LOAD_UPVALUE reads captured variable', () {
      // Scenario: main captures a ref variable (boxed int) into a closure.
      // The closure reads it via LOAD_UPVALUE and returns it.
      //
      // inner (funcId=1):
      //   upvalueDescriptors: [{isLocal: true, index: 0}]
      //   LOAD_UPVALUE r0, 0     — load upvalue[0] into r0
      //   UNBOX_INT v0, r0       — unbox to get int
      //   RETURN_VAL v0
      //
      // main (funcId=0):
      //   BOX_INT r0, v0=99      — box 99 to ref stack
      //   CLOSURE r1, funcId=1   — create closure capturing r0
      //   CALL A=1, B=1, C=0     — call closure in r1, result → v1
      //   HALT
      //
      // Expected: v1 = 99

      final innerProto = DarticFuncProto(
        funcId: 1,
        name: 'inner',
        bytecode: Uint32List.fromList([
          encodeABx(Op.loadUpvalue, 0, 0), // r0 = upvalue[0]
          encodeABC(Op.unboxInt, 0, 0, 0), // v0 = unbox(r0)
          encodeABC(Op.returnVal, 0, 0, 0), // return v0
        ]),
        valueRegCount: 1,
        refRegCount: 1,
        paramCount: 0,
        upvalueDescriptors: [
          const UpvalueDescriptor(isLocal: true, index: 0),
        ],
      );

      final mainProto = DarticFuncProto(
        funcId: 0,
        name: 'main',
        bytecode: Uint32List.fromList([
          encodeAsBx(Op.loadInt, 0, 99), // v0 = 99
          encodeABC(Op.boxInt, 0, 0, 0), // r0 = box(v0)
          encodeABx(Op.closure, 1, 1), // r1 = closure(funcProto[1], upvals)
          encodeABC(Op.call, 1, 1, 0), // call r1, result → v1
          encodeAx(Op.halt, 0),
        ]),
        valueRegCount: 2,
        refRegCount: 2,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [mainProto, innerProto],
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

      interp.execute(module);
      expect(interp.valueStack.readInt(1), 99);
    });

    test('STORE_UPVALUE writes to captured variable (mutation sharing)', () {
      // Scenario: main captures an int variable. The closure increments it
      // via STORE_UPVALUE. After the call, main reads the updated value.
      //
      // inner (funcId=1):
      //   upvalueDescriptors: [{isLocal: true, index: 0}]
      //   LOAD_UPVALUE r0, 0     — load upvalue[0] → r0 (boxed int)
      //   UNBOX_INT v0, r0       — v0 = current value
      //   ADD_INT_IMM v0, v0, 1  — v0 = v0 + 1
      //   BOX_INT r0, v0         — r0 = box(v0)
      //   STORE_UPVALUE r0, 0    — upvalue[0] = r0
      //   RETURN_NULL
      //
      // main (funcId=0):
      //   LOAD_INT v0, 0         — x = 0
      //   BOX_INT r0, v0         — r0 = box(x)
      //   CLOSURE r1, funcId=1   — create closure capturing r0
      //   CALL A=0, B=1, C=0     — call closure (result discarded)
      //   CALL A=0, B=1, C=0     — call closure again
      //   --- Now r0 should hold boxed 2 ---
      //   LOAD_UPVALUE reads from the stack slot, so we just read r0:
      //   Actually, for the open upvalue: the upvalue points to main's r0.
      //   After the calls, the upvalue at main's r0 should be updated.
      //   UNBOX_INT v0, r0       — v0 = unbox(r0) = 2
      //   HALT
      //
      // Expected: v0 = 2

      final innerProto = DarticFuncProto(
        funcId: 1,
        name: 'inc',
        bytecode: Uint32List.fromList([
          encodeABx(Op.loadUpvalue, 0, 0), // r0 = upvalue[0]
          encodeABC(Op.unboxInt, 0, 0, 0), // v0 = unbox(r0)
          encodeABC(Op.addIntImm, 0, 0, 1), // v0 = v0 + 1
          encodeABC(Op.boxInt, 0, 0, 0), // r0 = box(v0)
          encodeABx(Op.storeUpvalue, 0, 0), // upvalue[0] = r0
          encodeABC(Op.returnNull, 0, 0, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 1,
        paramCount: 0,
        upvalueDescriptors: [
          const UpvalueDescriptor(isLocal: true, index: 0),
        ],
      );

      final mainProto = DarticFuncProto(
        funcId: 0,
        name: 'main',
        bytecode: Uint32List.fromList([
          encodeAsBx(Op.loadInt, 0, 0), // v0 = 0
          encodeABC(Op.boxInt, 0, 0, 0), // r0 = box(0)
          encodeABx(Op.closure, 1, 1), // r1 = closure(funcProto[1])
          encodeABC(Op.call, 2, 1, 0), // call r1, result→r2 (discarded)
          encodeABC(Op.call, 2, 1, 0), // call r1 again, result→r2
          // After two inc() calls, the upvalue at r0 should be box(2)
          // Read r0 which has been mutated by STORE_UPVALUE
          // Since the upvalue is open, r0 in main's frame was modified.
          encodeABC(Op.unboxInt, 0, 0, 0), // v0 = unbox(r0)
          encodeAx(Op.halt, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 3, // r0=captured, r1=closure, r2=call result
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [mainProto, innerProto],
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

      interp.execute(module);
      expect(interp.valueStack.readInt(0), 2);
    });

    test('CLOSE_UPVALUE closes open upvalues at or above register', () {
      // Scenario: main creates a closure, then CLOSE_UPVALUE forces the
      // upvalue to be closed. The closure can still read the value after
      // the original stack slot is gone.
      //
      // inner (funcId=1):
      //   upvalueDescriptors: [{isLocal: true, index: 0}]
      //   LOAD_UPVALUE r0, 0     — load upvalue[0]
      //   UNBOX_INT v0, r0       — unbox
      //   RETURN_VAL v0
      //
      // main (funcId=0):
      //   LOAD_INT v0, 77        — x = 77
      //   BOX_INT r0, v0         — r0 = box(77)
      //   CLOSURE r1, funcId=1   — create closure
      //   CLOSE_UPVALUE r0       — close all upvalues at r0 and above
      //   CALL A=0, B=1, C=0     — call closure (reads closed upvalue)
      //   HALT
      //
      // Expected: v0 = 77

      final innerProto = DarticFuncProto(
        funcId: 1,
        name: 'inner',
        bytecode: Uint32List.fromList([
          encodeABx(Op.loadUpvalue, 0, 0), // r0 = upvalue[0]
          encodeABC(Op.unboxInt, 0, 0, 0), // v0 = unbox(r0)
          encodeABC(Op.returnVal, 0, 0, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 1,
        paramCount: 0,
        upvalueDescriptors: [
          const UpvalueDescriptor(isLocal: true, index: 0),
        ],
      );

      final mainProto = DarticFuncProto(
        funcId: 0,
        name: 'main',
        bytecode: Uint32List.fromList([
          encodeAsBx(Op.loadInt, 0, 77), // v0 = 77
          encodeABC(Op.boxInt, 0, 0, 0), // r0 = box(77)
          encodeABx(Op.closure, 1, 1), // r1 = closure
          encodeABC(Op.closeUpvalue, 0, 0, 0), // close upvalue at r0
          encodeABC(Op.call, 0, 1, 0), // call closure
          encodeAx(Op.halt, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 2,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [mainProto, innerProto],
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

      interp.execute(module);
      expect(interp.valueStack.readInt(0), 77);
    });

    test('transitive upvalue (nested closure)', () {
      // Scenario: main -> mid -> inner, where inner captures a variable
      // from main via mid as a transitive upvalue.
      //
      // inner (funcId=2):
      //   upvalueDescriptors: [{isLocal: false, index: 0}]
      //   LOAD_UPVALUE r0, 0     — load from upvalue[0] (transitive)
      //   UNBOX_INT v0, r0
      //   RETURN_VAL v0
      //
      // mid (funcId=1):
      //   upvalueDescriptors: [{isLocal: true, index: 0}]
      //   CLOSURE r0, funcId=2   — create inner closure
      //   CALL A=0, B=0, C=0     — call inner, result → v0
      //   RETURN_VAL v0
      //
      // main (funcId=0):
      //   LOAD_INT v0, 55
      //   BOX_INT r0, v0
      //   CLOSURE r1, funcId=1   — create mid closure
      //   CALL A=0, B=1, C=0     — call mid, result → v0
      //   HALT
      //
      // Expected: v0 = 55

      final innerProto = DarticFuncProto(
        funcId: 2,
        name: 'inner',
        bytecode: Uint32List.fromList([
          encodeABx(Op.loadUpvalue, 0, 0), // r0 = upvalue[0]
          encodeABC(Op.unboxInt, 0, 0, 0), // v0 = unbox(r0)
          encodeABC(Op.returnVal, 0, 0, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 1,
        paramCount: 0,
        upvalueDescriptors: [
          const UpvalueDescriptor(isLocal: false, index: 0),
        ],
      );

      final midProto = DarticFuncProto(
        funcId: 1,
        name: 'mid',
        bytecode: Uint32List.fromList([
          encodeABx(Op.closure, 0, 2), // r0 = closure(funcProto[2])
          encodeABC(Op.call, 0, 0, 0), // call r0, result → v0
          encodeABC(Op.returnVal, 0, 0, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 1,
        paramCount: 0,
        upvalueDescriptors: [
          const UpvalueDescriptor(isLocal: true, index: 0),
        ],
      );

      final mainProto = DarticFuncProto(
        funcId: 0,
        name: 'main',
        bytecode: Uint32List.fromList([
          encodeAsBx(Op.loadInt, 0, 55), // v0 = 55
          encodeABC(Op.boxInt, 0, 0, 0), // r0 = box(55)
          encodeABx(Op.closure, 1, 1), // r1 = closure(funcProto[1])
          encodeABC(Op.call, 0, 1, 0), // call r1, result → v0
          encodeAx(Op.halt, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 2,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [mainProto, midProto, innerProto],
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

      interp.execute(module);
      expect(interp.valueStack.readInt(0), 55);
    });

    test('CALL with parameters passes args to closure', () {
      // Scenario: closure takes one int parameter and adds it to a
      // captured upvalue.
      //
      // inner (funcId=1): paramCount=1
      //   upvalueDescriptors: [{isLocal: true, index: 0}]
      //   v0 = param (pre-laid by caller)
      //   LOAD_UPVALUE r0, 0     — load captured value
      //   UNBOX_INT v1, r0       — v1 = captured int
      //   ADD_INT v0, v0, v1     — v0 = param + captured
      //   RETURN_VAL v0
      //
      // main (funcId=0):
      //   LOAD_INT v0, 10
      //   BOX_INT r0, v0         — captured value = 10
      //   CLOSURE r1, funcId=1
      //   MOVE_VAL arg0, v0=5    — pass 5 as arg
      //   Actually, we need to put arg at callee's v0.
      //   callee's vBase = main.vs.sp, callee's v0 = main.vs.sp + 0
      //   main's valueRegCount = 2, so main.vs.sp = 2.
      //   To write to callee's v0, write to absolute pos 2, which is
      //   main's v2 (beyond main's frame).
      //   LOAD_INT v2, 5         — callee's v0 = 5
      //   CALL A=0, B=1, C=0     — result → v0
      //   HALT
      //
      // Expected: v0 = 5 + 10 = 15

      final innerProto = DarticFuncProto(
        funcId: 1,
        name: 'add_captured',
        bytecode: Uint32List.fromList([
          encodeABx(Op.loadUpvalue, 0, 0), // r0 = upvalue[0]
          encodeABC(Op.unboxInt, 1, 0, 0), // v1 = unbox(r0)
          encodeABC(Op.addInt, 0, 0, 1), // v0 = param + captured
          encodeABC(Op.returnVal, 0, 0, 0),
        ]),
        valueRegCount: 2,
        refRegCount: 1,
        paramCount: 1,
        upvalueDescriptors: [
          const UpvalueDescriptor(isLocal: true, index: 0),
        ],
      );

      final mainProto = DarticFuncProto(
        funcId: 0,
        name: 'main',
        bytecode: Uint32List.fromList([
          encodeAsBx(Op.loadInt, 0, 10), // v0 = 10
          encodeABC(Op.boxInt, 0, 0, 0), // r0 = box(10)
          encodeABx(Op.closure, 1, 1), // r1 = closure(funcProto[1])
          encodeAsBx(Op.loadInt, 2, 5), // v2 = callee's v0 = 5
          encodeABC(Op.call, 0, 1, 0), // call r1, result → v0
          encodeAx(Op.halt, 0),
        ]),
        valueRegCount: 2,
        refRegCount: 2,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [mainProto, innerProto],
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

      interp.execute(module);
      expect(interp.valueStack.readInt(0), 15);
    });
  });
}
