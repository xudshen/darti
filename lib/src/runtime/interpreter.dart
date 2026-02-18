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

        // ── Float Arithmetic (0x20-0x2F) ──

        case Op.addDbl: // ADD_DBL A, B, C — doubleView[A] = doubleView[B] + doubleView[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeDouble(
              vBase + a, vs.readDouble(vBase + b) + vs.readDouble(vBase + c));

        case Op.subDbl: // SUB_DBL A, B, C — doubleView[A] = doubleView[B] - doubleView[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeDouble(
              vBase + a, vs.readDouble(vBase + b) - vs.readDouble(vBase + c));

        case Op.mulDbl: // MUL_DBL A, B, C — doubleView[A] = doubleView[B] * doubleView[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeDouble(
              vBase + a, vs.readDouble(vBase + b) * vs.readDouble(vBase + c));

        case Op.divDbl: // DIV_DBL A, B, C — doubleView[A] = doubleView[B] / doubleView[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeDouble(
              vBase + a, vs.readDouble(vBase + b) / vs.readDouble(vBase + c));

        case Op.negDbl: // NEG_DBL A, B — doubleView[A] = -doubleView[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeDouble(vBase + a, -vs.readDouble(vBase + b));

        case Op.intToDbl: // INT_TO_DBL A, B — doubleView[A] = intView[B].toDouble()
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeDouble(vBase + a, vs.readInt(vBase + b).toDouble());

        case Op.dblToInt: // DBL_TO_INT A, B — intView[A] = doubleView[B].toInt()
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, vs.readDouble(vBase + b).toInt());

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

        case Op.ltDbl: // LT_DBL A, B, C — valueStack[A] = doubleView[B] < doubleView[C] ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readDouble(vBase + b) < vs.readDouble(vBase + c) ? 1 : 0);

        case Op.leDbl: // LE_DBL A, B, C — valueStack[A] = doubleView[B] <= doubleView[C] ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readDouble(vBase + b) <= vs.readDouble(vBase + c) ? 1 : 0);

        case Op.gtDbl: // GT_DBL A, B, C — valueStack[A] = doubleView[B] > doubleView[C] ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readDouble(vBase + b) > vs.readDouble(vBase + c) ? 1 : 0);

        case Op.geDbl: // GE_DBL A, B, C — valueStack[A] = doubleView[B] >= doubleView[C] ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readDouble(vBase + b) >= vs.readDouble(vBase + c) ? 1 : 0);

        case Op.eqDbl: // EQ_DBL A, B, C — valueStack[A] = doubleView[B] == doubleView[C] ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readDouble(vBase + b) == vs.readDouble(vBase + c) ? 1 : 0);

        case Op.eqRef: // EQ_REF A, B, C — identical(refStack[B], refStack[C])
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              identical(rs.read(rBase + b), rs.read(rBase + c)) ? 1 : 0);

        case Op.eqGeneric: // EQ_GENERIC A, B, C — valueStack[A] = refStack[B] == refStack[C] ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              rs.read(rBase + b) == rs.read(rBase + c) ? 1 : 0);

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

          // Overflow and call depth checks.
          if (vs.sp + callee.valueRegCount > vs.capacity ||
              rs.sp + callee.refRegCount > rs.capacity) {
            throw DarticError('Stack overflow');
          }
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

        // RETURN_REF / RETURN_VAL / RETURN_NULL share identical frame-restore
        // logic. The only difference: what is captured before and written after.
        case Op.returnRef: // RETURN_REF A — return refStack[A] to caller
        case Op.returnVal: // RETURN_VAL A — return valueStack[A] to caller
        case Op.returnNull: // RETURN_NULL — return null to caller
          // Capture return value before frame teardown.
          final Object? retRef;
          final int retVal;
          if (op == Op.returnRef) {
            retRef = rs.read(rBase + ((instr >> 8) & 0xFF));
            retVal = 0;
          } else if (op == Op.returnVal) {
            retRef = null;
            retVal = vs.readInt(vBase + ((instr >> 8) & 0xFF));
          } else {
            retRef = null;
            retVal = 0;
          }

          // Read caller state from current (callee) frame.
          final callerVSP = callStack.savedVSP;
          final callerRSP = callStack.savedRSP;
          final retPC = callStack.returnPC;
          final resReg = callStack.resultReg;

          // Clear callee's ref slots for GC safety.
          rs.clearRange(rBase, rs.sp);

          // Restore stack pointers (deallocate callee frame).
          vs.sp = vBase;
          rs.sp = rBase;
          vBase = callerVSP;
          rBase = callerRSP;

          // Pop callee frame, then look up caller's bytecode.
          callStack.popFrame();
          code = module.functions[callStack.funcId].bytecode;
          pc = retPC;

          // Write return value to caller's register.
          if (op == Op.returnVal) {
            vs.writeInt(callerVSP + resReg, retVal);
          } else {
            rs.write(callerRSP + resReg, retRef);
          }

        // ── Global Variables (0xA0-0xA1) ──

        case Op.loadGlobal: // LOAD_GLOBAL A, Bx — refStack[A] = globals[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          rs.write(rBase + a, _globalTable!.load(bx));

        case Op.storeGlobal: // STORE_GLOBAL A, Bx — globals[Bx] = refStack[A]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          _globalTable!.store(bx, rs.read(rBase + a));

        // ── Type Operations (0x65-0x66) ──

        case Op.instanceOf: // INSTANCEOF A, B, C — valueStack[A] = checker(refStack[B]) ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final checker = cp.getRef(c) as bool Function(Object?);
          final value = rs.read(rBase + b);
          vs.writeInt(vBase + a, checker(value) ? 1 : 0);

        case Op.cast: // CAST A, B, C — refStack[A] = caster(refStack[B]); throws TypeError on failure
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final caster = cp.getRef(c) as Object? Function(Object?);
          final value = rs.read(rBase + b);
          rs.write(rBase + a, caster(value));

        // ── Exception Handling (0xA4-0xA5) ──

        case Op.throw_: // THROW A — throw refStack[A]
          final a = (instr >> 8) & 0xFF;
          final exception = rs.read(rBase + a);
          final stackTrace = StackTrace.current;

          // Search for matching handler in the current function.
          final funcProto = module.functions[callStack.funcId];
          final handlerResult = _findHandler(funcProto, pc - 1);
          if (handlerResult != null) {
            // Unwind stacks to handler's saved depths.
            rs.clearRange(rBase + handlerResult.refStackDP, rs.sp);
            vs.sp = vBase + handlerResult.valStackDP;
            rs.sp = rBase + handlerResult.refStackDP;

            // Bind exception variable.
            rs.write(rBase + handlerResult.exceptionReg, exception);
            if (handlerResult.stackTraceReg >= 0) {
              rs.write(rBase + handlerResult.stackTraceReg, stackTrace);
            }

            // Jump to handler.
            pc = handlerResult.handlerPC;
          } else {
            // No handler — propagate through call stack.
            // For now, simply rethrow as a Dart exception.
            // The Dart VM will unwind the call stack.
            throw exception!;
          }

        case Op.rethrow_: // RETHROW A, B — rethrow refStack[A] with stackTrace refStack[B]
          final a = (instr >> 8) & 0xFF;
          final exception = rs.read(rBase + a);
          // B operand is the stackTrace register — preserved from original throw.
          // For Phase 2 we simply rethrow; full stackTrace handling in later phases.

          final funcProto = module.functions[callStack.funcId];
          final handlerResult = _findHandler(funcProto, pc - 1);
          if (handlerResult != null) {
            rs.clearRange(rBase + handlerResult.refStackDP, rs.sp);
            vs.sp = vBase + handlerResult.valStackDP;
            rs.sp = rBase + handlerResult.refStackDP;

            rs.write(rBase + handlerResult.exceptionReg, exception);
            if (handlerResult.stackTraceReg >= 0) {
              final b = (instr >> 16) & 0xFF;
              rs.write(
                  rBase + handlerResult.stackTraceReg, rs.read(rBase + b));
            }

            pc = handlerResult.handlerPC;
          } else {
            throw exception!;
          }

        case Op.assert_: // ASSERT A, Bx — if valueStack[A] == 0 → throw AssertionError
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          if (vs.readInt(vBase + a) == 0) {
            final message =
                bx != 0xFFFF ? module.constantPool.getRef(bx) : null;
            final exception = AssertionError(message?.toString());
            final stackTrace = StackTrace.current;

            final funcProto = module.functions[callStack.funcId];
            final handler = _findHandler(funcProto, pc - 1);
            if (handler != null) {
              rs.clearRange(rBase + handler.refStackDP, rs.sp);
              vs.sp = vBase + handler.valStackDP;
              rs.sp = rBase + handler.refStackDP;

              rs.write(rBase + handler.exceptionReg, exception);
              if (handler.stackTraceReg >= 0) {
                rs.write(rBase + handler.stackTraceReg, stackTrace);
              }

              pc = handler.handlerPC;
            } else {
              throw exception;
            }
          }

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

  /// Searches [funcProto]'s exception table for a handler matching [pc].
  ///
  /// Returns the first matching [ExceptionHandler] where
  /// `startPC <= pc < endPC`, or null if no handler matches.
  /// Phase 2: only supports catch-all (catchType == -1).
  ExceptionHandler? _findHandler(DarticFuncProto funcProto, int pc) {
    for (final handler in funcProto.exceptionTable) {
      if (pc >= handler.startPC && pc < handler.endPC) {
        // Phase 2: only catch-all handlers.
        if (handler.catchType == -1) return handler;
      }
    }
    return null;
  }
}
