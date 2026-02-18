import '../bytecode/module.dart';
import 'call_stack.dart';
import 'error.dart';
import 'ref_stack.dart';
import 'value_stack.dart';

/// Bytecode interpreter with register-based dispatch loop.
///
/// Phase 1: synchronous single-frame execution with fuel counting.
/// No async, no `_runQueue` scheduling.
///
/// See: docs/design/03-execution-engine.md
class DarticInterpreter {
  DarticInterpreter({
    ValueStack? valueStack,
    RefStack? refStack,
    CallStack? callStack,
    this.fuelBudget = defaultFuelBudget,
  })  : valueStack = valueStack ?? ValueStack(),
        refStack = refStack ?? RefStack(),
        callStack = callStack ?? CallStack();

  static const int defaultFuelBudget = 50000;

  final ValueStack valueStack;
  final RefStack refStack;
  final CallStack callStack;
  final int fuelBudget;

  /// Executes [module] starting from its entry function.
  ///
  /// Runs the dispatch loop until HALT is reached or fuel is exhausted.
  void execute(DarticModule module) {
    final entryFunc = module.functions[module.entryFuncId];
    final cp = module.constantPool;
    final vs = valueStack;
    final rs = refStack;

    // Set up initial frame.
    var vBase = vs.sp;
    var rBase = rs.sp;

    callStack.pushFrame(
      funcId: entryFunc.funcId,
      returnPC: 0,
      savedFP: callStack.fp,
      savedVSP: vBase,
      savedRSP: rBase,
      resultReg: 0,
    );

    vs.sp += entryFunc.valueRegCount;
    rs.sp += entryFunc.refRegCount;

    // Dispatch loop — hot-path locals.
    var code = entryFunc.bytecode;
    var pc = 0;
    var fuel = fuelBudget;

    while (fuel-- > 0) {
      final instr = code[pc++];
      final op = instr & 0xFF;

      switch (op) {
        // ── Load/Store (0x00-0x0F) ──

        case 0x00: // NOP
          break;

        case 0x01: // LOAD_CONST A, Bx — refStack[A] = constPool.refs[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          rs.write(rBase + a, cp.getRef(bx));

        case 0x02: // LOAD_NULL A — refStack[A] = null
          rs.write(rBase + ((instr >> 8) & 0xFF), null);

        case 0x03: // LOAD_TRUE A — valueStack[A] = 1
          vs.writeInt(vBase + ((instr >> 8) & 0xFF), 1);

        case 0x04: // LOAD_FALSE A — valueStack[A] = 0
          vs.writeInt(vBase + ((instr >> 8) & 0xFF), 0);

        case 0x05: // LOAD_INT A, sBx — valueStack[A] = sBx
          final a = (instr >> 8) & 0xFF;
          final sbx = ((instr >> 16) & 0xFFFF) - 0x7FFF;
          vs.writeInt(vBase + a, sbx);

        case 0x06: // LOAD_CONST_INT A, Bx — valueStack[A] = intPool[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          vs.writeInt(vBase + a, cp.getInt(bx));

        case 0x07: // LOAD_CONST_DBL A, Bx — doubleView[A] = dblPool[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          vs.writeDouble(vBase + a, cp.getDouble(bx));

        case 0x08: // MOVE_REF A, B — refStack[A] = refStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          rs.write(rBase + a, rs.read(rBase + b));

        case 0x09: // MOVE_VAL A, B — valueStack[A] = valueStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b));

        case 0x0A: // LOAD_UPVALUE A, Bx — deferred (closure support)
          throw DarticError('Unimplemented opcode: 0x0a (LOAD_UPVALUE)');

        case 0x0B: // STORE_UPVALUE A, Bx — deferred (closure support)
          throw DarticError('Unimplemented opcode: 0x0b (STORE_UPVALUE)');

        case 0x0C: // BOX_INT A, B — refStack[A] = valueStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          rs.write(rBase + a, vs.readInt(vBase + b));

        case 0x0D: // BOX_DOUBLE A, B — refStack[A] = doubleView[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          rs.write(rBase + a, vs.readDouble(vBase + b));

        case 0x0E: // UNBOX_INT A, B — valueStack[A] = refStack[B] as int
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, rs.read(rBase + b) as int);

        case 0x0F: // UNBOX_DOUBLE A, B — doubleView[A] = refStack[B] as double
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeDouble(vBase + a, rs.read(rBase + b) as double);

        // ── Integer Arithmetic (0x10-0x1F) ──

        case 0x10: // ADD_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) + vs.readInt(vBase + c));

        case 0x11: // SUB_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) - vs.readInt(vBase + c));

        case 0x12: // MUL_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) * vs.readInt(vBase + c));

        case 0x13: // DIV_INT A, B, C (truncating ~/)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) ~/ vs.readInt(vBase + c));

        case 0x14: // MOD_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) % vs.readInt(vBase + c));

        case 0x15: // NEG_INT A, B
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, -vs.readInt(vBase + b));

        case 0x16: // BIT_AND A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) & vs.readInt(vBase + c));

        case 0x17: // BIT_OR A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) | vs.readInt(vBase + c));

        case 0x18: // BIT_XOR A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) ^ vs.readInt(vBase + c));

        case 0x19: // BIT_NOT A, B
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, ~vs.readInt(vBase + b));

        case 0x1A: // SHL A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) << vs.readInt(vBase + c));

        case 0x1B: // SHR A, B, C (arithmetic)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) >> vs.readInt(vBase + c));

        case 0x1C: // USHR A, B, C (unsigned / logical)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) >>> vs.readInt(vBase + c));

        case 0x1D: // ADD_INT_IMM A, B, C (C is unsigned 8-bit immediate)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) + c);

        // ── Comparison (0x30-0x3F) ──

        case 0x30: // LT_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) < vs.readInt(vBase + c) ? 1 : 0);

        case 0x31: // LE_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readInt(vBase + b) <= vs.readInt(vBase + c) ? 1 : 0);

        case 0x32: // GT_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) > vs.readInt(vBase + c) ? 1 : 0);

        case 0x33: // GE_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readInt(vBase + b) >= vs.readInt(vBase + c) ? 1 : 0);

        case 0x34: // EQ_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readInt(vBase + b) == vs.readInt(vBase + c) ? 1 : 0);

        case 0x3A: // EQ_REF A, B, C — identical(refStack[B], refStack[C])
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              identical(rs.read(rBase + b), rs.read(rBase + c)) ? 1 : 0);

        // ── Control Flow (0x40-0x4F) ──

        case 0x40: // JUMP sBx — PC += sBx (A unused)
          pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;

        case 0x41: // JUMP_IF_TRUE A, sBx — if valueStack[A] != 0
          if (vs.readInt(vBase + ((instr >> 8) & 0xFF)) != 0) {
            pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
          }

        case 0x42: // JUMP_IF_FALSE A, sBx — if valueStack[A] == 0
          if (vs.readInt(vBase + ((instr >> 8) & 0xFF)) == 0) {
            pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
          }

        case 0x43: // JUMP_IF_NULL A, sBx — if refStack[A] == null
          if (rs.read(rBase + ((instr >> 8) & 0xFF)) == null) {
            pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
          }

        case 0x44: // JUMP_IF_NNULL A, sBx — if refStack[A] != null
          if (rs.read(rBase + ((instr >> 8) & 0xFF)) != null) {
            pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
          }

        case 0x45: // JUMP_AX sAx — PC += sAx (24-bit signed)
          pc += ((instr >> 8) & 0xFFFFFF) - 0x7FFFFF;

        // ── Call/Return (0x50-0x5F) ──

        case 0x51: // CALL_STATIC A, Bx — call functions[Bx], result→reg A
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          final callee = module.functions[bx];

          // Overflow check.
          if (vs.sp + callee.valueRegCount > vs.capacity) {
            throw DarticError('Stack overflow');
          }
          if (rs.sp + callee.refRegCount > rs.capacity) {
            throw DarticError('Stack overflow');
          }
          // Call depth check.
          if (callStack.depth >= callStack.maxFrames) {
            throw DarticError('Maximum call depth exceeded');
          }

          // Push frame — save caller state.
          callStack.pushFrame(
            funcId: callee.funcId,
            returnPC: pc,
            savedFP: callStack.fp,
            savedVSP: vBase,
            savedRSP: rBase,
            resultReg: a,
          );

          // Advance to callee frame.
          vBase = vs.sp;
          rBase = rs.sp;
          vs.sp += callee.valueRegCount;
          rs.sp += callee.refRegCount;

          // Switch to callee bytecode.
          code = callee.bytecode;
          pc = 0;

        case 0x55: // RETURN_REF A — return refStack[A] to caller
          final retRef = rs.read(rBase + ((instr >> 8) & 0xFF));

          // Read caller state from current (callee) frame.
          final rrCallerVSP = callStack.savedVSP;
          final rrCallerRSP = callStack.savedRSP;
          final rrRetPC = callStack.returnPC;
          final rrResReg = callStack.resultReg;

          // Clear callee's ref slots for GC safety.
          rs.clearRange(rBase, rs.sp);

          // Restore stack pointers (deallocate callee frame).
          vs.sp = vBase;
          rs.sp = rBase;
          vBase = rrCallerVSP;
          rBase = rrCallerRSP;

          // Pop callee frame, then look up caller's bytecode.
          callStack.popFrame();
          code = module.functions[callStack.funcId].bytecode;
          pc = rrRetPC;

          // Write return value to caller's ref register.
          rs.write(rrCallerRSP + rrResReg, retRef);

        case 0x56: // RETURN_VAL A — return valueStack[A] to caller
          final retVal = vs.readInt(vBase + ((instr >> 8) & 0xFF));

          // Read caller state from current (callee) frame.
          final rvCallerVSP = callStack.savedVSP;
          final rvCallerRSP = callStack.savedRSP;
          final rvRetPC = callStack.returnPC;
          final rvResReg = callStack.resultReg;

          // Clear callee's ref slots for GC safety.
          rs.clearRange(rBase, rs.sp);

          // Restore stack pointers (deallocate callee frame).
          vs.sp = vBase;
          rs.sp = rBase;
          vBase = rvCallerVSP;
          rBase = rvCallerRSP;

          // Pop callee frame, then look up caller's bytecode.
          callStack.popFrame();
          code = module.functions[callStack.funcId].bytecode;
          pc = rvRetPC;

          // Write return value to caller's value register.
          vs.writeInt(rvCallerVSP + rvResReg, retVal);

        case 0x57: // RETURN_NULL — return null to caller's refStack[resultReg]
          // Read caller state from current (callee) frame.
          final rnCallerVSP = callStack.savedVSP;
          final rnCallerRSP = callStack.savedRSP;
          final rnRetPC = callStack.returnPC;
          final rnResReg = callStack.resultReg;

          // Clear callee's ref slots for GC safety.
          rs.clearRange(rBase, rs.sp);

          // Restore stack pointers (deallocate callee frame).
          vs.sp = vBase;
          rs.sp = rBase;
          vBase = rnCallerVSP;
          rBase = rnCallerRSP;

          // Pop callee frame, then look up caller's bytecode.
          callStack.popFrame();
          code = module.functions[callStack.funcId].bytecode;
          pc = rnRetPC;

          // Write null to caller's ref register.
          rs.write(rnCallerRSP + rnResReg, null);

        // ── System ──

        case 0xFF: // HALT
          vs.sp = vBase;
          rs.sp = rBase;
          callStack.popFrame();
          return;

        default:
          throw DarticError(
            'Unimplemented opcode: '
            '0x${op.toRadixString(16).padLeft(2, '0')}',
          );
      }
    }
    // Fuel exhausted — Phase 1: silently return.
  }
}
