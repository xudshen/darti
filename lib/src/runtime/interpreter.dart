import '../bytecode/module.dart';
import '../bytecode/opcodes.dart';
import 'call_stack.dart';
import 'error.dart';
import 'global_table.dart';
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

  /// Global variable table — initialized per-module in [execute].
  DarticGlobalTable? _globalTable;

  /// Remaining fuel — shared across initializer and main execution.
  int _fuel = 0;

  /// Executes [module] starting from its entry function.
  ///
  /// Runs the dispatch loop until HALT is reached or fuel is exhausted.
  void execute(DarticModule module) {
    _fuel = fuelBudget;

    // Set up global table and run initializers.
    if (module.globalCount > 0) {
      _globalTable = DarticGlobalTable(module.globalCount);
      // Run initializers (each ends with STORE_GLOBAL + HALT).
      for (var i = 0; i < module.globalCount; i++) {
        final initFuncId = module.globalInitializerIds[i];
        if (initFuncId >= 0) {
          _executeEntry(module, initFuncId);
        }
      }
    }

    // Run main.
    _executeEntry(module, module.entryFuncId);
  }

  /// Runs the dispatch loop for a single entry function within [module].
  ///
  /// Used for both global initializer functions and the main entry point.
  void _executeEntry(DarticModule module, int entryFuncId) {
    final entryFunc = module.functions[entryFuncId];
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

    while (_fuel-- > 0) {
      final instr = code[pc++];
      final op = instr & 0xFF;

      switch (op) {
        // ── Load/Store (0x00-0x0F) ──

        case Op.nop: // NOP
          break;

        case Op.loadConst: // LOAD_CONST A, Bx — refStack[A] = constPool.refs[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          rs.write(rBase + a, cp.getRef(bx));

        case Op.loadNull: // LOAD_NULL A — refStack[A] = null
          rs.write(rBase + ((instr >> 8) & 0xFF), null);

        case Op.loadTrue: // LOAD_TRUE A — valueStack[A] = 1
          vs.writeInt(vBase + ((instr >> 8) & 0xFF), 1);

        case Op.loadFalse: // LOAD_FALSE A — valueStack[A] = 0
          vs.writeInt(vBase + ((instr >> 8) & 0xFF), 0);

        case Op.loadInt: // LOAD_INT A, sBx — valueStack[A] = sBx
          final a = (instr >> 8) & 0xFF;
          final sbx = ((instr >> 16) & 0xFFFF) - 0x7FFF;
          vs.writeInt(vBase + a, sbx);

        case Op.loadConstInt: // LOAD_CONST_INT A, Bx — valueStack[A] = intPool[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          vs.writeInt(vBase + a, cp.getInt(bx));

        case Op.loadConstDbl: // LOAD_CONST_DBL A, Bx — doubleView[A] = dblPool[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          vs.writeDouble(vBase + a, cp.getDouble(bx));

        case Op.moveRef: // MOVE_REF A, B — refStack[A] = refStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          rs.write(rBase + a, rs.read(rBase + b));

        case Op.moveVal: // MOVE_VAL A, B — valueStack[A] = valueStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b));

        case Op.loadUpvalue: // LOAD_UPVALUE A, Bx — deferred (closure support)
          throw DarticError('Unimplemented opcode: 0x0a (LOAD_UPVALUE)');

        case Op.storeUpvalue: // STORE_UPVALUE A, Bx — deferred (closure support)
          throw DarticError('Unimplemented opcode: 0x0b (STORE_UPVALUE)');

        case Op.boxInt: // BOX_INT A, B — refStack[A] = valueStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          rs.write(rBase + a, vs.readInt(vBase + b));

        case Op.boxDouble: // BOX_DOUBLE A, B — refStack[A] = doubleView[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          rs.write(rBase + a, vs.readDouble(vBase + b));

        case Op.unboxInt: // UNBOX_INT A, B — valueStack[A] = refStack[B] as int
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, rs.read(rBase + b) as int);

        case Op.unboxDouble: // UNBOX_DOUBLE A, B — doubleView[A] = refStack[B] as double
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeDouble(vBase + a, rs.read(rBase + b) as double);

        // ── Integer Arithmetic (0x10-0x1F) ──

        case Op.addInt: // ADD_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) + vs.readInt(vBase + c));

        case Op.subInt: // SUB_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) - vs.readInt(vBase + c));

        case Op.mulInt: // MUL_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) * vs.readInt(vBase + c));

        case Op.divInt: // DIV_INT A, B, C (truncating ~/)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) ~/ vs.readInt(vBase + c));

        case Op.modInt: // MOD_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) % vs.readInt(vBase + c));

        case Op.negInt: // NEG_INT A, B
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, -vs.readInt(vBase + b));

        case Op.bitAnd: // BIT_AND A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) & vs.readInt(vBase + c));

        case Op.bitOr: // BIT_OR A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) | vs.readInt(vBase + c));

        case Op.bitXor: // BIT_XOR A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) ^ vs.readInt(vBase + c));

        case Op.bitNot: // BIT_NOT A, B
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, ~vs.readInt(vBase + b));

        case Op.shl: // SHL A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) << vs.readInt(vBase + c));

        case Op.shr: // SHR A, B, C (arithmetic)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) >> vs.readInt(vBase + c));

        case Op.ushr: // USHR A, B, C (unsigned / logical)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) >>> vs.readInt(vBase + c));

        case Op.addIntImm: // ADD_INT_IMM A, B, C (C is unsigned 8-bit immediate)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) + c);

        // ── Comparison (0x30-0x3F) ──

        case Op.ltInt: // LT_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) < vs.readInt(vBase + c) ? 1 : 0);

        case Op.leInt: // LE_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readInt(vBase + b) <= vs.readInt(vBase + c) ? 1 : 0);

        case Op.gtInt: // GT_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) > vs.readInt(vBase + c) ? 1 : 0);

        case Op.geInt: // GE_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readInt(vBase + b) >= vs.readInt(vBase + c) ? 1 : 0);

        case Op.eqInt: // EQ_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readInt(vBase + b) == vs.readInt(vBase + c) ? 1 : 0);

        case Op.eqRef: // EQ_REF A, B, C — identical(refStack[B], refStack[C])
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              identical(rs.read(rBase + b), rs.read(rBase + c)) ? 1 : 0);

        // ── Control Flow (0x40-0x4F) ──

        case Op.jump: // JUMP sBx — PC += sBx (A unused)
          pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;

        case Op.jumpIfTrue: // JUMP_IF_TRUE A, sBx — if valueStack[A] != 0
          if (vs.readInt(vBase + ((instr >> 8) & 0xFF)) != 0) {
            pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
          }

        case Op.jumpIfFalse: // JUMP_IF_FALSE A, sBx — if valueStack[A] == 0
          if (vs.readInt(vBase + ((instr >> 8) & 0xFF)) == 0) {
            pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
          }

        case Op.jumpIfNull: // JUMP_IF_NULL A, sBx — if refStack[A] == null
          if (rs.read(rBase + ((instr >> 8) & 0xFF)) == null) {
            pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
          }

        case Op.jumpIfNnull: // JUMP_IF_NNULL A, sBx — if refStack[A] != null
          if (rs.read(rBase + ((instr >> 8) & 0xFF)) != null) {
            pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
          }

        case Op.jumpAx: // JUMP_AX sAx — PC += sAx (24-bit signed)
          pc += ((instr >> 8) & 0xFFFFFF) - 0x7FFFFF;

        // ── Call/Return (0x50-0x5F) ──

        case Op.callStatic: // CALL_STATIC A, Bx — call functions[Bx], result→reg A
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

        case Op.returnRef: // RETURN_REF A — return refStack[A] to caller
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

        case Op.returnVal: // RETURN_VAL A — return valueStack[A] to caller
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

        case Op.returnNull: // RETURN_NULL — return null to caller's refStack[resultReg]
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

        // ── Global Variables (0xA0-0xA1) ──

        case Op.loadGlobal: // LOAD_GLOBAL A, Bx — refStack[A] = globals[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          rs.write(rBase + a, _globalTable!.load(bx));

        case Op.storeGlobal: // STORE_GLOBAL A, Bx — globals[Bx] = refStack[A]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          _globalTable!.store(bx, rs.read(rBase + a));

        // ── Null Safety (0xA7) ──

        case Op.nullCheck: // NULL_CHECK A — if refStack[A] == null → throw
          if (rs.read(rBase + ((instr >> 8) & 0xFF)) == null) {
            throw DarticError(
                'Null check operator used on a null value');
          }

        // ── System ──

        case Op.halt: // HALT
          // Ref slots [rBase, rs.sp) are intentionally NOT cleared here.
          // HALT ends the entire execution; the caller may read results.
          // GC-safe clearing applies to RETURN (callee frame cleanup).
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
