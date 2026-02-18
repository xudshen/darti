import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/error.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

void main() {
  late DarticInterpreter interp;

  setUp(() {
    interp = DarticInterpreter();
  });

  group('CALL_STATIC + RETURN_VAL', () {
    test('calls function and returns int value', () {
      // func 0 (main): LOAD_INT v0=10, LOAD_INT v1=20,
      //   move args to callee frame, CALL_STATIC A=2 Bx=1, HALT
      //   After call: v2 = return value from add
      //
      // func 1 (add): v0 = param a, v1 = param b (pre-laid by caller)
      //   ADD_INT v2=v0+v1, RETURN_VAL v2
      //
      // Calling convention: caller pre-lays args at callee's vBase.
      // main's frame: vBase=0, valueRegCount=4
      //   v0=10, v1=20
      //   Before CALL_STATIC: copy v0→callee v0, v1→callee v1
      //   Actually, caller pre-lays args at (caller.vBase + caller.valueRegCount + offset).
      //   Wait — the design says caller puts args at the callee's register positions.
      //   callee vBase = caller.vs.sp = caller.vBase + caller.valueRegCount = 0+4 = 4
      //   So caller writes: vs[4]=10, vs[5]=20 (callee's v0, v1)
      //   But those are outside the caller's frame!
      //
      // Actually, per the calling convention:
      //   "编译器在调用者帧的栈顶预先将参数放置在被调用者帧的对应寄存器位置"
      //   The caller writes beyond its own frame (at vs.sp + offset).
      //   For simplicity, we allocate extra valueRegCount in the caller to cover args.
      //
      // Simpler approach: caller's valueRegCount includes space for callee args.
      // main: valueRegCount = 3 (v0=10, v1=20, v2=result)
      //   The callee's frame starts at vs.sp = 0 + 3 = 3.
      //   Caller pre-lays: vs[3]=10, vs[4]=20 (these are callee's v0, v1).
      //   Use MOVE_VAL to copy: v0→slot3, v1→slot4?
      //   No — MOVE_VAL uses frame-relative addressing (vBase+A).
      //   We need to write to absolute positions beyond our frame.
      //
      // Hmm, this is a problem with frame-relative addressing.
      // Let me re-read the calling convention more carefully.
      //
      // The design says: "调用者在 CALL 之前已通过 MOVE_REF / MOVE_VAL 等指令
      //   将参数写入被调用者帧的寄存器区域（编译器分配的连续槽位）"
      //
      // This means the compiler allocates the callee's parameter slots as part
      // of the caller's frame! So if main needs 2 local vars + 2 arg slots for
      // the call, main's valueRegCount = 4:
      //   v0 = local (10)
      //   v1 = local (20)
      //   v2 = result slot
      //   v3 = arg0 for callee (not used as local)
      //
      // Wait, that doesn't work either. The callee needs its own frame with its
      // own valueRegCount for its locals.
      //
      // Let me think differently. The key insight:
      //   - Caller's sp = caller.vBase + caller.valueRegCount
      //   - Callee's vBase = caller's sp (where the new frame starts)
      //   - Before CALL, caller writes args to positions that will become
      //     callee's registers (callee.vBase + paramIndex)
      //   - These positions are at: caller.vBase + caller.valueRegCount + paramIndex
      //   - The compiler ensures caller.valueRegCount is large enough that
      //     these writes are within caller's frame OR the compiler accounts
      //     for this in sp management.
      //
      // Actually, the compiler simply makes the caller's valueRegCount include
      // the space for outgoing args. So if main has 1 local + needs to pass
      // 2 args, main.valueRegCount = 3 (1 local + 2 arg slots).
      // The arg slots v1 and v2 are at vBase+1 and vBase+2.
      // These become the callee's v0 and v1 when CALL_STATIC advances vBase.
      //
      // Wait, that's not right either. CALL_STATIC pushes a new frame with
      // the callee's valueRegCount. The callee's vBase = current vs.sp.
      // The caller writes args to absolute positions [vs.sp, vs.sp+paramCount).
      // These are beyond the caller's frame.
      //
      // The simplest interpretation: the compiler allocates extra regs in the
      // caller's valueRegCount so that the argument area overlaps with the
      // caller's frame. When CALL happens, the callee's vBase starts where
      // the args are, and the callee sees them as its v0, v1, etc.
      //
      // For our test, let's use this layout:
      //
      // main (funcId=0): valueRegCount=4, refRegCount=0
      //   v0 = 10 (arg for callee, which becomes callee's v0)
      //   v1 = 20 (arg for callee, which becomes callee's v1)
      //   v2 = result register (CALL_STATIC A=2)
      //   -- actually, the result goes to the CALLER's frame at resultReg.
      //   -- After RETURN_VAL, the return value is written to caller's
      //      valueStack[resultReg] where resultReg = A from CALL_STATIC.
      //
      // Hmm wait. CALL_STATIC A, Bx:
      //   A = the caller's register to receive the return value
      //   Bx = funcId of the callee
      //
      // RETURN_VAL A:
      //   A = the callee's register containing the return value
      //   The runtime writes it to: caller's valueStack[savedVSP + resultReg]
      //   where resultReg is the A from the original CALL_STATIC.
      //
      // So the flow:
      //   1. Caller has v0=10, v1=20
      //   2. Caller's vs.sp = vBase + valueRegCount = 0 + 4 = 4
      //   3. Caller writes args beyond its frame: vs[4]=10, vs[5]=20
      //      But we can't use MOVE_VAL for this (it's frame-relative)!
      //
      // OK I think I'm overcomplicating this. Let me look at it from the
      // CALL_STATIC implementation perspective:
      //
      // CALL_STATIC A, Bx:
      //   1. Look up callee = module.functions[Bx]
      //   2. Check stack overflow
      //   3. Check call depth
      //   4. Push frame: funcId=callee.funcId, returnPC=pc, savedFP=cs.fp,
      //      savedVSP=vBase, savedRSP=rBase, resultReg=A
      //   5. Set new vBase = vs.sp, rBase = rs.sp
      //   6. vs.sp += callee.valueRegCount, rs.sp += callee.refRegCount
      //   7. Set code = callee.bytecode, pc = 0
      //
      // The callee's v0, v1 start at the new vBase = old vs.sp.
      // The caller must write the arguments to [old vs.sp, old vs.sp + paramCount)
      // BEFORE executing CALL_STATIC.
      //
      // But MOVE_VAL is frame-relative (vBase + A). To write to positions beyond
      // the caller's frame, the compiler could:
      //   a) Include the arg space in the caller's valueRegCount (making it larger)
      //   b) Use a different addressing mode
      //
      // I believe option (a) is what's intended. The compiler allocates the
      // caller's valueRegCount to include space for outgoing arguments.
      // So the last N registers of the caller's frame overlap with the
      // callee's first N registers (the parameters).
      //
      // Example layout:
      //   main.valueRegCount = 5 (v0=result, v1=local1, v2=local2, v3=arg0, v4=arg1)
      //   main writes: v3=10, v4=20
      //   main executes CALL_STATIC A=0, Bx=1 (result in v0)
      //
      //   CALL_STATIC sets new vBase = vs.sp = 0+5 = 5
      //   But wait — callee's v0 would be at vBase=5, not at position 3!
      //
      // That doesn't work either. The args at v3=pos3, v4=pos4 would be
      // at absolute positions 3 and 4, but the callee starts at vBase=5.
      //
      // I think the actual convention is:
      //   The args are placed at positions [vs.sp, vs.sp + paramCount) which
      //   is AFTER the caller's frame. Then CALL advances vBase to vs.sp,
      //   and the callee sees the args as its v0, v1, etc.
      //
      //   To write to these positions, the caller uses:
      //   - vs.sp + 0 = vBase + valueRegCount + 0 for arg0
      //   - vs.sp + 1 = vBase + valueRegCount + 1 for arg1
      //
      //   With frame-relative MOVE_VAL: if valueRegCount = N, then writing
      //   to register N, N+1 would go to vs[vBase+N], vs[vBase+N+1] which
      //   is exactly vs.sp, vs.sp+1!
      //
      //   So the compiler sets valueRegCount to include the arg space.
      //   Register indices beyond (valueRegCount - paramCount) are the arg slots.
      //
      //   main.valueRegCount = 3 (v0=result, v1=arg0_out, v2=arg1_out)
      //   main: LOAD_INT v1=10, LOAD_INT v2=20
      //   main: CALL_STATIC A=0, Bx=1  (result→v0)
      //
      //   After CALL_STATIC: new vBase = 0+3 = 3
      //   But the args are at abs pos 1 and 2, not 3 and 4!
      //   That's still wrong.
      //
      // I think I need to re-read the design doc more carefully.
      // The key: "vs.sp += funcProto.valueRegCount"
      // CALL_STATIC sets:
      //   new vBase = old vs.sp  (this is caller.vBase + caller.valueRegCount)
      //   new vs.sp = new vBase + callee.valueRegCount
      //
      // So callee's v0 starts at position (caller.vBase + caller.valueRegCount).
      // To place args there BEFORE the call, using MOVE_VAL with frame-relative
      // addressing, the caller would write to register indices >= valueRegCount.
      // But that's "out of bounds" from the frame's perspective.
      //
      // Wait — there's nothing preventing the caller from writing to register
      // indices beyond its valueRegCount. The sp just marks the "allocated" region.
      // Writes to vs[vBase + idx] for any idx are valid as long as the underlying
      // buffer has space.
      //
      // So the convention is:
      //   - The compiler generates MOVE_VAL instructions with A >= valueRegCount
      //     to place args in the callee's parameter positions.
      //   - These writes go to vs[vBase + A] which equals vs[caller_vBase + A].
      //   - For A = valueRegCount + 0, this is vs[vs.sp + 0] = callee's v0.
      //
      // But LOAD_INT is AsBx format: LOAD_INT A, sBx → vs[vBase+A] = sBx.
      // If we use A = valueRegCount (e.g., 3), then vs[0+3] = value.
      // After CALL_STATIC: new vBase = vs.sp = 3.
      // callee's v0 = vs[3] = the value we just wrote. Correct!
      //
      // So for our test:
      //   main.valueRegCount = 3 (v0=result reg, v1..v2=local use)
      //   callee.valueRegCount = 3 (v0=param a, v1=param b, v2=temp)
      //   callee.paramCount = 2
      //
      //   main bytecode:
      //     LOAD_INT v3=10  (writes to vBase+3 = callee's future v0)
      //     LOAD_INT v4=20  (writes to vBase+4 = callee's future v1)
      //     CALL_STATIC A=0 Bx=1  (result → v0)
      //     HALT
      //
      //   callee bytecode:
      //     ADD_INT v2=v0+v1  (10+20=30)
      //     RETURN_VAL v2
      //
      //   After RETURN_VAL v2:
      //     returnValue = callee.vs[callee.vBase + 2] = 30
      //     Write to caller.vs[caller.vBase + resultReg] = caller.vs[0 + 0] = 30
      //     Restore vBase, rBase, pc, code
      //     main continues after CALL_STATIC
      //     v0 = 30
      //     HALT
      //
      // This should work!

      final mainProto = DarticFuncProto(
        funcId: 0,
        bytecode: Uint32List.fromList([
          encodeAsBx(Opcode.loadInt.code, 3, 10), // callee arg0
          encodeAsBx(Opcode.loadInt.code, 4, 20), // callee arg1
          encodeABx(Opcode.callStatic.code, 0, 1), // call add, result→v0
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 3,
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

      interp.execute(module);
      // main's v0 should be 30
      expect(interp.valueStack.readInt(0), 30);
    });
  });

  group('RETURN_REF', () {
    test('returns reference value to caller', () {
      final cp = ConstantPool();
      final idx = cp.addRef('hello');

      final mainProto = DarticFuncProto(
        funcId: 0,
        bytecode: Uint32List.fromList([
          encodeABx(Opcode.callStatic.code, 0, 1), // call getStr, result→r0
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 0,
        refRegCount: 1,
        paramCount: 0,
      );

      final getStrProto = DarticFuncProto(
        funcId: 1,
        bytecode: Uint32List.fromList([
          encodeABx(Opcode.loadConst.code, 0, idx), // r0 = 'hello'
          encodeABC(Opcode.returnRef.code, 0, 0, 0), // return r0
        ]),
        valueRegCount: 0,
        refRegCount: 1,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [mainProto, getStrProto],
        constantPool: cp,
        entryFuncId: 0,
      );

      interp.execute(module);
      expect(interp.refStack.read(0), 'hello');
    });
  });

  group('RETURN_NULL', () {
    test('returns null to caller', () {
      final cp = ConstantPool();
      cp.addRef('pre-existing');

      final mainProto = DarticFuncProto(
        funcId: 0,
        bytecode: Uint32List.fromList([
          // Pre-fill r0 with non-null to verify it gets overwritten
          encodeABx(Opcode.loadConst.code, 0, 0),
          encodeABx(Opcode.callStatic.code, 0, 1), // call, result→r0
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 0,
        refRegCount: 1,
        paramCount: 0,
      );

      final nullFuncProto = DarticFuncProto(
        funcId: 1,
        bytecode: Uint32List.fromList([
          encodeAx(Opcode.returnNull.code, 0), // return null
        ]),
        valueRegCount: 0,
        refRegCount: 0,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [mainProto, nullFuncProto],
        constantPool: cp,
        entryFuncId: 0,
      );

      interp.execute(module);
      expect(interp.refStack.read(0), isNull);
    });
  });

  group('nested calls', () {
    test('A calls B calls C, each returns correctly', () {
      // A (main): calls B, gets result in v0
      // B: LOAD_INT v2=100, calls C with args (v2), result in v0, returns v0+v2
      // C: returns param v0 * 2
      //
      // Simplified:
      // main (f0): calls f1, result→v0, HALT. Expects v0=42.
      // f1: LOAD_INT v0=40, calls f2, result→v1. ADD v0=v0+v1. RETURN_VAL v0.
      // f2: LOAD_INT v0=2, RETURN_VAL v0.
      //
      // f1 result = 40 + 2 = 42

      final mainProto = DarticFuncProto(
        funcId: 0,
        bytecode: Uint32List.fromList([
          encodeABx(Opcode.callStatic.code, 0, 1), // call f1, result→v0
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 0,
        paramCount: 0,
      );

      final f1Proto = DarticFuncProto(
        funcId: 1,
        bytecode: Uint32List.fromList([
          encodeAsBx(Opcode.loadInt.code, 0, 40), // v0 = 40
          encodeABx(Opcode.callStatic.code, 1, 2), // call f2, result→v1
          encodeABC(Opcode.addInt.code, 0, 0, 1), // v0 = v0 + v1 = 40 + 2
          encodeABC(Opcode.returnVal.code, 0, 0, 0), // return v0
        ]),
        valueRegCount: 2,
        refRegCount: 0,
        paramCount: 0,
      );

      final f2Proto = DarticFuncProto(
        funcId: 2,
        bytecode: Uint32List.fromList([
          encodeAsBx(Opcode.loadInt.code, 0, 2), // v0 = 2
          encodeABC(Opcode.returnVal.code, 0, 0, 0), // return v0
        ]),
        valueRegCount: 1,
        refRegCount: 0,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [mainProto, f1Proto, f2Proto],
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

      interp.execute(module);
      expect(interp.valueStack.readInt(0), 42);
    });
  });

  group('stack overflow', () {
    test('exceeds value stack capacity throws DarticError', () {
      // Create function with huge valueRegCount that exceeds stack capacity
      final mainProto = DarticFuncProto(
        funcId: 0,
        bytecode: Uint32List.fromList([
          encodeABx(Opcode.callStatic.code, 0, 1),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 0,
        paramCount: 0,
      );

      final bigProto = DarticFuncProto(
        funcId: 1,
        bytecode: Uint32List.fromList([
          encodeABC(Opcode.returnVal.code, 0, 0, 0),
        ]),
        valueRegCount: 100000, // exceeds default capacity of 10240
        refRegCount: 0,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [mainProto, bigProto],
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

      expect(
        () => interp.execute(module),
        throwsA(isA<DarticError>().having(
          (e) => e.message,
          'message',
          contains('Stack overflow'),
        )),
      );
    });
  });

  group('call depth', () {
    test('exceeds maxCallDepth throws DarticError', () {
      // Create a recursive function that calls itself until depth limit
      // f0 (main): calls f1
      // f1: calls f1 (infinite recursion)

      final mainProto = DarticFuncProto(
        funcId: 0,
        bytecode: Uint32List.fromList([
          encodeABx(Opcode.callStatic.code, 0, 1),
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 0,
        paramCount: 0,
      );

      final recurseProto = DarticFuncProto(
        funcId: 1,
        bytecode: Uint32List.fromList([
          encodeABx(Opcode.callStatic.code, 0, 1), // call self
          encodeABC(Opcode.returnVal.code, 0, 0, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 0,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [mainProto, recurseProto],
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

      expect(
        () => interp.execute(module),
        throwsA(isA<DarticError>().having(
          (e) => e.message,
          'message',
          contains('call depth'),
        )),
      );
    });
  });
}
