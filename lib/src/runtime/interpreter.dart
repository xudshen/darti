import '../bytecode/module.dart';
import '../bytecode/opcodes.dart';
import '../compiler/type_template.dart';
import 'call_stack.dart';
import 'closure.dart';
import 'dartic_type.dart';
import 'error.dart';
import 'global_table.dart';
import 'object.dart';
import 'ref_stack.dart';
import 'subtype_checker.dart';
import 'type_resolver.dart';
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
    this.typeRegistry,
    this.fuelBudget = defaultFuelBudget,
  })  : valueStack = valueStack ?? ValueStack(),
        refStack = refStack ?? RefStack(),
        callStack = callStack ?? CallStack();

  static const int defaultFuelBudget = 50000;

  final ValueStack valueStack;
  final RefStack refStack;
  final CallStack callStack;
  final int fuelBudget;

  /// Type registry for generics support. If null, generics instructions throw.
  final TypeRegistry? typeRegistry;

  /// Global variable table — initialized per-module in [execute].
  DarticGlobalTable? _globalTable;

  /// Subtype checker for DarticType-based INSTANCEOF/CAST.
  SubtypeChecker? _subtypeChecker;

  /// Remaining fuel — shared across initializer and main execution.
  int _fuel = 0;

  /// Open upvalue tracking: maps absolute ref stack index to the open
  /// [Upvalue] cell. When CLOSURE captures a local variable, it looks up
  /// or creates an entry here. When CLOSE_UPVALUE fires, matching entries
  /// are removed and their cells transition to closed state.
  final Map<int, Upvalue> _openUpvalues = {};

  /// Parallel stack of upvalue lists for each call frame. Stores the
  /// current frame's closure upvalues (or null for non-closure calls).
  /// Pushed on CALL/CALL_STATIC, popped on RETURN.
  final List<List<Upvalue>?> _upvalueStack = [];

  /// The entry function's result after [execute], or `null` if void.
  Object? get entryResult => _lastEntryResult;
  Object? _lastEntryResult;

  /// Executes [module] starting from its entry function.
  ///
  /// Runs the dispatch loop until HALT is reached or fuel is exhausted.
  void execute(DarticModule module) {
    _fuel = fuelBudget;
    _lastEntryResult = null;
    _openUpvalues.clear();
    _upvalueStack.clear();

    // Auto-create TypeRegistry + SubtypeChecker from module metadata.
    _provisionTypeSystem(module);

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

  /// Creates TypeRegistry and SubtypeChecker from module metadata if available.
  void _provisionTypeSystem(DarticModule module) {
    final ids = module.coreTypeIds;
    if (ids != null && typeRegistry == null) {
      final reg = TypeRegistry(
        intClassId: ids.intId,
        doubleClassId: ids.doubleId,
        stringClassId: ids.stringId,
        boolClassId: ids.boolId,
        objectClassId: ids.objectId,
        numClassId: ids.numId,
      );
      // Store as the effective type registry for this execution.
      _effectiveTypeRegistry = reg;
    }
    final reg = _effectiveTypeRegistry ?? typeRegistry;
    if (reg != null) {
      _subtypeChecker = SubtypeChecker(
        classes: module.classes,
        registry: reg,
      );
    }
  }

  /// The effective type registry: either user-provided or auto-created from
  /// module metadata.
  TypeRegistry? _effectiveTypeRegistry;

  /// Returns the active TypeRegistry (user-provided or auto-provisioned).
  TypeRegistry? get _activeTypeRegistry => _effectiveTypeRegistry ?? typeRegistry;

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

    // Current frame's closure upvalues (null for top-level / CALL_STATIC).
    List<Upvalue>? currentUpvalues;

    // Push sentinel entry for the initial frame.
    _upvalueStack.add(null);

    // Helper: unwind frames searching for an exception handler starting at
    // [startPC]. If found, restores stacks, writes exception/stackTrace into
    // the handler's registers, and returns the handler PC. If no handler
    // exists, rethrows [exception] to the host VM.
    //
    // Side effects: mutates vBase, rBase, code, currentUpvalues via closure.
    int unwindToHandler(int startPC, Object? exception, Object? stackTrace) {
      var searchPC = startPC;
      while (true) {
        final funcProto = module.functions[callStack.funcId];
        final handler = _findHandler(funcProto, searchPC);
        if (handler != null) {
          rs.clearRange(rBase + handler.refStackDP, rs.sp);
          vs.sp = vBase + handler.valStackDP;
          rs.sp = rBase + handler.refStackDP;
          rs.write(rBase + handler.exceptionReg, exception);
          if (handler.stackTraceReg >= 0) {
            rs.write(rBase + handler.stackTraceReg, stackTrace);
          }
          return handler.handlerPC;
        }
        if (callStack.depth <= 1) throw exception!;
        rs.clearRange(rBase, rs.sp);
        vs.sp = vBase;
        rs.sp = rBase;
        final callerVSP = callStack.savedVSP;
        final callerRSP = callStack.savedRSP;
        searchPC = callStack.returnPC - 1;
        callStack.popFrame();
        vBase = callerVSP;
        rBase = callerRSP;
        code = module.functions[callStack.funcId].bytecode;
        currentUpvalues = _upvalueStack.removeLast();
      }
    }

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

        case Op.loadUpvalue: // LOAD_UPVALUE A, Bx — refStack[A] = upvalue[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          final uv = currentUpvalues![bx];
          rs.write(
            rBase + a,
            uv.isOpen ? rs.read(uv.stackIndex) : uv.value,
          );

        case Op.storeUpvalue: // STORE_UPVALUE A, Bx — upvalue[Bx] = refStack[A]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          final uv = currentUpvalues![bx];
          final val = rs.read(rBase + a);
          if (uv.isOpen) {
            rs.write(uv.stackIndex, val);
          } else {
            uv.value = val;
          }

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
          final ubVal = rs.read(rBase + b);
          // Bool values from generic fields are stored as Dart bool on the ref
          // stack but share int (0/1) representation on the value stack.
          vs.writeInt(vBase + a, ubVal is bool ? (ubVal ? 1 : 0) : ubVal as int);

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

        case Op.call: // CALL A, B, C — call closure in refStack[B], result→reg A
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final closure = rs.read(rBase + b) as DarticClosure;
          final callee = closure.funcProto;

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

          // Save caller's upvalues and switch to closure's upvalues.
          _upvalueStack.add(currentUpvalues);
          currentUpvalues = closure.upvalues;

          // Advance to callee frame.
          vBase = vs.sp;
          rBase = rs.sp;
          vs.sp += callee.valueRegCount;
          rs.sp += callee.refRegCount;

          // Switch to callee bytecode.
          code = callee.bytecode;
          pc = 0;

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

          // Save caller's upvalues; static calls have no closure upvalues.
          _upvalueStack.add(currentUpvalues);
          currentUpvalues = null;

          // Advance to callee frame.
          vBase = vs.sp;
          rBase = rs.sp;
          vs.sp += callee.valueRegCount;
          rs.sp += callee.refRegCount;

          // Switch to callee bytecode.
          code = callee.bytecode;
          pc = 0;

        case Op.callVirtual: // CALL_VIRTUAL A, B, C — virtual method dispatch
          final a = (instr >> 8) & 0xFF; // result register
          final b = (instr >> 16) & 0xFF; // receiver register
          final c = (instr >> 24) & 0xFF; // IC table index

          // Read receiver — null receiver throws DarticError.
          final receiver = rs.read(rBase + b);
          if (receiver is! DarticObject) {
            throw DarticError(
              'NoSuchMethodError: method call on null receiver',
            );
          }

          // IC dispatch: look up the current function's IC table.
          final ic = module.functions[callStack.funcId].icTable[c];

          DarticFuncProto callee;
          if (ic.cachedClassId == receiver.classId) {
            // IC hit — fast path.
            callee = module.functions[ic.cachedFuncId];
          } else {
            // IC miss — slow path: look up method in class info.
            final classInfo = module.classes[receiver.classId];
            final method = classInfo.methods[ic.methodNameIndex];
            if (method == null) {
              final name = module.constantPool.getName(ic.methodNameIndex);
              throw DarticError(
                'NoSuchMethodError: method "$name" not found on '
                '${classInfo.name}',
              );
            }
            callee = method;
            // Update IC cache.
            ic.cachedClassId = receiver.classId;
            ic.cachedFuncId = callee.funcId;
          }

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

          // Save caller's upvalues.
          _upvalueStack.add(currentUpvalues);
          currentUpvalues = null;

          // Advance to callee frame.
          vBase = vs.sp;
          rBase = rs.sp;
          vs.sp += callee.valueRegCount;
          rs.sp += callee.refRegCount;

          // Place receiver at callee's rsp+2 (the `this` slot).
          rs.write(rBase + 2, receiver);

          // Auto-load ITA from receiver's runtimeType_ for generic classes.
          final rtType = receiver.runtimeType_;
          if (rtType is DarticInterfaceType && rtType.typeArgs.isNotEmpty) {
            rs.write(rBase + 0, rtType.typeArgs);
          }

          // Switch to callee bytecode.
          code = callee.bytecode;
          pc = 0;

        case Op.callSuper: // CALL_SUPER A, Bx — call super method functions[Bx], result→reg A
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

          // Save caller's upvalues; super calls have no closure upvalues.
          _upvalueStack.add(currentUpvalues);
          currentUpvalues = null;

          // Advance to callee frame.
          final callerRBase = rBase;
          vBase = vs.sp;
          rBase = rs.sp;
          vs.sp += callee.valueRegCount;
          rs.sp += callee.refRegCount;

          // Auto-load ITA from caller's `this` (rsp+2) runtimeType_ for
          // generic classes, so super methods can access class type params.
          final thisObj = rs.read(callerRBase + 2);
          if (thisObj is DarticObject) {
            final rtType = thisObj.runtimeType_;
            if (rtType is DarticInterfaceType && rtType.typeArgs.isNotEmpty) {
              rs.write(rBase + 0, rtType.typeArgs);
            }
          }

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

          // Restore caller's upvalues.
          currentUpvalues = _upvalueStack.removeLast();

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

        // ── Object Operations (0x60-0x64) ──

        case Op.getFieldRef: // GET_FIELD_REF A, B, C — refStack[A] = refStack[B].refFields[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final obj = rs.read(rBase + b) as DarticObject;
          rs.write(rBase + a, obj.refFields[c]);

        case Op.setFieldRef: // SET_FIELD_REF A, B, C — refStack[A].refFields[C] = refStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final obj = rs.read(rBase + a) as DarticObject;
          obj.refFields[c] = rs.read(rBase + b);

        case Op.getFieldVal: // GET_FIELD_VAL A, B, C — valueStack[A] = refStack[B].valueFields[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final obj = rs.read(rBase + b) as DarticObject;
          vs.writeInt(vBase + a, obj.valueFields[c]);

        case Op.setFieldVal: // SET_FIELD_VAL A, B, C — refStack[A].valueFields[C] = valueStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final obj = rs.read(rBase + a) as DarticObject;
          obj.valueFields[c] = vs.readInt(vBase + b);

        case Op.newInstance: // NEW_INSTANCE A, Bx — refStack[A] = new DarticObject(class[Bx])
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          final classInfo = module.classes[bx];
          rs.write(rBase + a, DarticObject(classInfo));

        // ── Type Operations (0x65-0x66) ──

        case Op.instanceOf: // INSTANCEOF A, B, C — valStack[A] = isSubtypeOf(extractType(refStack[B]), refStack[C]) ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final targetType = rs.read(rBase + c) as DarticType;
          final value = rs.read(rBase + b);
          final checker = _subtypeChecker!;
          final reg = _activeTypeRegistry!;
          final objType = extractType(value, reg, module.classes);
          vs.writeInt(vBase + a, checker.isSubtypeOf(objType, targetType) ? 1 : 0);

        case Op.cast: // CAST A, B, C — refStack[A] = refStack[B] if subtype, else throw TypeError
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final targetType = rs.read(rBase + c) as DarticType;
          final value = rs.read(rBase + b);
          final checker = _subtypeChecker!;
          final reg = _activeTypeRegistry!;
          final objType = extractType(value, reg, module.classes);
          if (checker.isSubtypeOf(objType, targetType)) {
            rs.write(rBase + a, value);
          } else {
            throw TypeError();
          }

        // ── Exception Handling (0xA4-0xA5) ──

        case Op.throw_: // THROW A — throw refStack[A]
          final a = (instr >> 8) & 0xFF;
          final exception = rs.read(rBase + a);
          pc = unwindToHandler(pc - 1, exception, StackTrace.current);

        case Op.rethrow_: // RETHROW A, B — rethrow refStack[A] with stackTrace refStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final exception = rs.read(rBase + a);
          // Read stackTrace BEFORE unwinding — the source register may fall
          // within the range that gets nullified during stack unwinding.
          final stackTrace = b > 0 ? rs.read(rBase + b) : null;
          pc = unwindToHandler(pc - 1, exception, stackTrace);

        case Op.assert_: // ASSERT A, Bx — if valueStack[A] == 0 → throw AssertionError
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          if (vs.readInt(vBase + a) == 0) {
            final message =
                bx != 0xFFFF ? module.constantPool.getRef(bx) : null;
            final exception = AssertionError(message?.toString());
            pc = unwindToHandler(pc - 1, exception, StackTrace.current);
          }

        // ── Closure (0x70-0x71) ──

        case Op.closure: // CLOSURE A, Bx — refStack[A] = DarticClosure(funcProto[Bx])
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          final proto = module.functions[bx];
          final upvalues = <Upvalue>[];
          for (final desc in proto.upvalueDescriptors) {
            if (desc.isLocal) {
              final absIndex = rBase + desc.index;
              upvalues.add(
                _openUpvalues.putIfAbsent(
                    absIndex, () => Upvalue.open(absIndex)),
              );
            } else {
              upvalues.add(currentUpvalues![desc.index]);
            }
          }
          rs.write(
            rBase + a,
            DarticClosure(funcProto: proto, upvalues: upvalues),
          );

        case Op.closeUpvalue: // CLOSE_UPVALUE A — close all open upvalues at rBase+A and above
          final minIndex = rBase + ((instr >> 8) & 0xFF);
          _openUpvalues.removeWhere((stackIndex, uv) {
            if (stackIndex >= minIndex) {
              uv.close(rs.read(stackIndex));
              return true;
            }
            return false;
          });

        // ── Generics & Types (0x78-0x7F) ──

        case Op.pushIta: // PUSH_ITA A — refStack[A] = refStack[0] (ITA slot)
          rs.write(
            rBase + ((instr >> 8) & 0xFF),
            rs.read(rBase + 0),
          );

        case Op.pushFta: // PUSH_FTA A — refStack[A] = refStack[1] (FTA slot)
          rs.write(
            rBase + ((instr >> 8) & 0xFF),
            rs.read(rBase + 1),
          );

        case Op.loadTypeArg: // LOAD_TYPE_ARG A, B, C — refStack[A] = (refStack[B] as List<DarticType>)[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final typeArgs = rs.read(rBase + b) as List<DarticType>;
          rs.write(rBase + a, typeArgs[c]);

        case Op.instantiateType: // INSTANTIATE_TYPE A, Bx — refStack[A] = resolveType(constPool.refs[Bx], ITA, FTA)
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          final template = cp.getRef(bx) as TypeTemplate;
          final ita = rs.read(rBase + 0) as List<DarticType>?;
          final fta = rs.read(rBase + 1) as List<DarticType>?;
          rs.write(
              rBase + a, resolveType(template, ita, fta, _activeTypeRegistry!));

        case Op.createTypeArgs: // CREATE_TYPE_ARGS A, B, C — refStack[C] = [refStack[B]..refStack[B+A-1]]
          final count = (instr >> 8) & 0xFF;
          final startReg = (instr >> 16) & 0xFF;
          final destReg = (instr >> 24) & 0xFF;
          final typeArgs = <DarticType>[
            for (var i = 0; i < count; i++)
              rs.read(rBase + startReg + i) as DarticType,
          ];
          rs.write(rBase + destReg, typeArgs);

        case Op.allocGeneric: // ALLOC_GENERIC A, B — refStack[A] = new DarticObject with runtimeType from refStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final type = rs.read(rBase + b) as DarticInterfaceType;
          final classInfo = module.classes[type.classId];
          final obj = DarticObject(classInfo);
          obj.runtimeType_ = type;
          rs.write(rBase + a, obj);

        // ── Null Safety (0xA7) ──

        case Op.nullCheck: // NULL_CHECK A — if refStack[A] == null → throw
          if (rs.read(rBase + ((instr >> 8) & 0xFF)) == null) {
            throw DarticError(
                'Null check operator used on a null value');
          }

        // ── System ──

        case Op.halt: // HALT ABC: A=resultReg, B=kind, C=unused
          // Extract result BEFORE resetting stack pointers.
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          switch (b) {
            case 1: _lastEntryResult = vs.readInt(vBase + a);
            case 2: _lastEntryResult = vs.readDouble(vBase + a);
            case 3: _lastEntryResult = rs.read(rBase + a);
            default: _lastEntryResult = null;
          }
          vs.sp = vBase;
          rs.sp = rBase;
          callStack.popFrame();
          _upvalueStack.removeLast();
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
