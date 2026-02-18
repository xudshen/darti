import 'dart:typed_data';

import 'package:kernel/ast.dart' as ir;
import 'package:kernel/core_types.dart' show CoreTypes;

import '../bytecode/constant_pool.dart';
import '../bytecode/encoding.dart';
import '../bytecode/module.dart';
import '../bytecode/opcodes.dart';
import 'bytecode_emitter.dart';
import 'register_allocator.dart';
import 'scope.dart';

/// Where a compiled expression result lives.
///
/// Mirrors [StackKind] from scope.dart but is the public API type returned
/// by expression compilation methods.
enum ResultLoc { value, ref }

/// Compiles Kernel AST ([ir.Component]) to a [DarticModule].
///
/// Phase 1 minimal compiler:
/// - Two-pass compilation (collect funcIds, then compile bodies)
/// - Expression visitors for literals and int arithmetic
/// - Statement visitors for return/expression/variable/block
/// - Scope-level register allocation via [RegisterAllocator] and [Scope]
///
/// See: docs/design/05-compiler.md
class DarticCompiler {
  DarticCompiler(this._component);

  final ir.Component _component;

  // ── Global compilation state ──

  final List<DarticFuncProto> _functions = [];
  final ConstantPool _constantPool = ConstantPool();

  /// Maps Kernel Procedure references to funcIds in [_functions].
  final Map<ir.Reference, int> _procToFuncId = {};

  /// The funcId of the entry point (main).
  int _entryFuncId = -1;

  /// Maps Kernel Field references (getter + setter) to global slot indices.
  final Map<ir.Reference, int> _fieldToGlobalIndex = {};

  /// For each global: funcId of its initializer function, or -1 if none.
  final List<int> _globalInitializerIds = [];

  /// Total number of global variable slots.
  int _globalCount = 0;

  // ── Per-function compilation state ──
  // Reset in _compileProcedure for each function.

  late BytecodeEmitter _emitter;
  late RegisterAllocator _valueAlloc;
  late RegisterAllocator _refAlloc;
  late Scope _scope;
  bool _isEntryFunction = false;

  /// Pending outgoing arg MOVE instructions to patch after the function is
  /// fully compiled. Each entry records the bytecode offset of a placeholder
  /// instruction, the source register, the arg index, and whether it is a
  /// value-stack or ref-stack argument.
  ///
  /// The calling convention places value args at `valueRegCount + argIndex`
  /// and ref args at `refRegCount + argIndex` (beyond the frame), but these
  /// counts are only known after compilation. We emit placeholders and patch
  /// them in `_compileProcedure`.
  final List<({int pc, int srcReg, int argIdx, ResultLoc loc})>
      _pendingArgMoves = [];

  /// Maps LabeledStatement → list of JUMP placeholder PCs that need to be
  /// backpatched to the label's end when the LabeledStatement finishes.
  final Map<ir.LabeledStatement, List<int>> _labelBreakJumps = {};

  /// Maps loop/switch statements to their continue target PC
  /// (the update-step PC for for-loops, the condition PC for while-loops).
  final Map<ir.Statement, int> _continueTargets = {};

  /// Maps loop/switch statements to their break jump lists.
  /// BreakStatement that targets a loop/switch (not a LabeledStatement)
  /// records its JUMP placeholder here.
  final Map<ir.Statement, List<int>> _breakTargets = {};

  /// Maps SwitchCase → PC of the case body start (for ContinueSwitchStatement).
  final Map<ir.SwitchCase, int> _switchCasePCs = {};

  /// Exception handler table being built for the current function.
  final List<ExceptionHandler> _exceptionHandlers = [];

  /// Maps catch Rethrow → the exception/stackTrace register pair
  /// for the innermost catch clause.
  int _catchExceptionReg = -1;
  int _catchStackTraceReg = -1;

  /// Compiles the component and returns a [DarticModule].
  ///
  /// Two-pass strategy:
  /// 1. Collect all user procedures → assign funcIds
  /// 2. Compile each procedure's body → emit bytecode
  DarticModule compile() {
    // Pass 1a: assign funcIds to all user-defined procedures.
    // TODO: Traverse class members (methods, getters, setters,
    // constructors) once class compilation is supported. Currently only
    // top-level procedures are collected.
    for (final lib in _component.libraries) {
      if (_isPlatformLibrary(lib)) continue;
      for (final proc in lib.procedures) {
        final funcId = _functions.length;
        _procToFuncId[proc.reference] = funcId;
        // Placeholder — will be replaced in pass 2.
        _functions.add(DarticFuncProto(
          funcId: funcId,
          bytecode: _haltBytecode,
          valueRegCount: 0,
          refRegCount: 0,
          paramCount: 0,
        ));
      }
    }

    // Pass 1b: assign global indices to top-level fields.
    for (final lib in _component.libraries) {
      if (_isPlatformLibrary(lib)) continue;
      for (final field in lib.fields) {
        final globalIndex = _globalCount++;
        _fieldToGlobalIndex[field.getterReference] = globalIndex;
        final setterRef = field.setterReference;
        if (setterRef != null) {
          _fieldToGlobalIndex[setterRef] = globalIndex;
        }
        // Placeholder for initializer funcId — will be set in Pass 2b.
        _globalInitializerIds.add(-1);
      }
    }

    // Determine entry point.
    final mainProc = _component.mainMethod;
    if (mainProc != null) {
      final id = _procToFuncId[mainProc.reference];
      if (id != null) _entryFuncId = id;
    }
    if (_entryFuncId < 0 && _functions.isNotEmpty) {
      _entryFuncId = 0; // fallback
    }

    // Pass 2a: compile each procedure.
    for (final lib in _component.libraries) {
      if (_isPlatformLibrary(lib)) continue;
      for (final proc in lib.procedures) {
        _compileProcedure(proc);
      }
    }

    // Pass 2b: compile global initializers.
    for (final lib in _component.libraries) {
      if (_isPlatformLibrary(lib)) continue;
      for (final field in lib.fields) {
        if (field.initializer != null) {
          final globalIndex = _fieldToGlobalIndex[field.getterReference]!;
          final initFuncId = _compileGlobalInitializer(field, globalIndex);
          _globalInitializerIds[globalIndex] = initFuncId;
        }
      }
    }

    return DarticModule(
      functions: _functions,
      constantPool: _constantPool,
      entryFuncId: _entryFuncId,
      globalCount: _globalCount,
      globalInitializerIds: _globalInitializerIds,
    );
  }

  // ── Procedure compilation ──

  void _compileProcedure(ir.Procedure proc) {
    final funcId = _procToFuncId[proc.reference]!;
    final fn = proc.function;

    // Reset per-function state.
    _emitter = BytecodeEmitter();
    _valueAlloc = RegisterAllocator();
    _refAlloc = RegisterAllocator();
    _isEntryFunction = funcId == _entryFuncId;
    _pendingArgMoves.clear();
    _labelBreakJumps.clear();
    _continueTargets.clear();
    _breakTargets.clear();
    _switchCasePCs.clear();
    _exceptionHandlers.clear();
    _catchExceptionReg = -1;
    _catchStackTraceReg = -1;

    // Create the function-level scope.
    _scope = Scope(valueAlloc: _valueAlloc, refAlloc: _refAlloc);

    // Register function parameters as variable bindings.
    // Parameters get dedicated registers via the allocator (not scope-managed
    // for release — they live for the entire function).
    for (final param in fn.positionalParameters) {
      final kind = _classifyStackKind(param.type);
      final reg = kind.isValue
          ? _valueAlloc.alloc()
          : _refAlloc.alloc();
      _scope.declareWithReg(param, kind, reg);
    }

    // Compile function body.
    final body = fn.body;
    if (body != null) {
      _compileStatement(body);
    }

    // Safety net: if no explicit return, emit HALT or RETURN_NULL.
    if (_isEntryFunction) {
      _emitter.emit(encodeAx(Op.halt, 0));
    } else {
      _emitter.emit(encodeABC(Op.returnNull, 0, 0, 0));
    }

    _patchPendingArgMoves();

    final valRegCount = _valueAlloc.maxUsed;
    final refRegCount = _refAlloc.maxUsed;
    _functions[funcId] = DarticFuncProto(
      funcId: funcId,
      name: proc.name.text,
      bytecode: _emitter.toUint32List(),
      valueRegCount: valRegCount,
      refRegCount: refRegCount,
      paramCount: fn.positionalParameters.length,
      exceptionTable: List.of(_exceptionHandlers),
      // TODO(Phase 2+): Handle namedParameters.
    );
  }

  // ── Global initializer compilation ──

  /// Compiles a standalone initializer function for a global [field].
  ///
  /// The generated function computes the initializer expression, boxes the
  /// result if needed, emits STORE_GLOBAL to the given [globalIndex], and
  /// ends with HALT.
  int _compileGlobalInitializer(ir.Field field, int globalIndex) {
    final funcId = _functions.length;

    // Reset per-function state.
    _emitter = BytecodeEmitter();
    _valueAlloc = RegisterAllocator();
    _refAlloc = RegisterAllocator();
    _scope = Scope(valueAlloc: _valueAlloc, refAlloc: _refAlloc);
    _isEntryFunction = true; // Use HALT, not RETURN
    _pendingArgMoves.clear();

    final (reg, loc) = _compileExpression(field.initializer!);
    final refReg = _ensureRef(reg, loc, field.type);
    _emitter.emit(encodeABx(Op.storeGlobal, refReg, globalIndex));

    // HALT (end of initializer).
    _emitter.emit(encodeAx(Op.halt, 0));

    _patchPendingArgMoves();

    final valRegCount = _valueAlloc.maxUsed;
    final refRegCount = _refAlloc.maxUsed;
    _functions.add(DarticFuncProto(
      funcId: funcId,
      name: '__init_${field.name.text}',
      bytecode: _emitter.toUint32List(),
      valueRegCount: valRegCount,
      refRegCount: refRegCount,
      paramCount: 0,
    ));

    return funcId;
  }

  // ── Register allocation helpers ──

  int _allocValueReg() => _valueAlloc.alloc();

  int _allocRefReg() => _refAlloc.alloc();

  /// Emits a MOVE instruction (value or ref) from [srcReg] to [destReg].
  void _emitMove(int destReg, int srcReg, ResultLoc loc) {
    final op = loc == ResultLoc.ref ? Op.moveRef : Op.moveVal;
    _emitter.emit(encodeABC(op, destReg, srcReg, 0));
  }

  /// Compiles a binary value-stack operation: receiver op arg[0].
  (int, ResultLoc) _emitBinaryOp(ir.InstanceInvocation expr, int op) {
    final (lhsReg, _) = _compileExpression(expr.receiver);
    final (rhsReg, _) = _compileExpression(expr.arguments.positional[0]);
    final resultReg = _allocValueReg();
    _emitter.emit(encodeABC(op, resultReg, lhsReg, rhsReg));
    return (resultReg, ResultLoc.value);
  }

  /// Compiles a unary value-stack operation on the receiver.
  (int, ResultLoc) _emitUnaryOp(ir.InstanceInvocation expr, int op) {
    final (srcReg, _) = _compileExpression(expr.receiver);
    final resultReg = _allocValueReg();
    _emitter.emit(encodeABC(op, resultReg, srcReg, 0));
    return (resultReg, ResultLoc.value);
  }

  /// Compiles [branchExpr], boxing and moving the result into [targetReg].
  ///
  /// Used by conditional expressions where both branches must write to the
  /// same pre-allocated register.
  void _compileBranchInto(
    ir.Expression branchExpr,
    int targetReg,
    ResultLoc targetLoc,
  ) {
    var (reg, loc) = _compileExpression(branchExpr);
    if (loc != targetLoc && targetLoc == ResultLoc.ref) {
      reg = _emitBoxToRef(reg, _inferExprType(branchExpr));
    }
    if (reg != targetReg) {
      _emitMove(targetReg, reg, targetLoc);
    }
  }

  /// Ensures a value is on the ref stack, boxing if necessary.
  ///
  /// Used for STORE_GLOBAL which always operates on the ref stack. If the
  /// value is already on the ref stack, returns [reg] unchanged.
  int _ensureRef(int reg, ResultLoc loc, ir.DartType fieldType) {
    if (loc == ResultLoc.ref) return reg;
    final refReg = _allocRefReg();
    final boxOp = _classifyStackKind(fieldType) == StackKind.doubleVal
        ? Op.boxDouble
        : Op.boxInt;
    _emitter.emit(encodeABC(boxOp, refReg, reg, 0));
    return refReg;
  }

  /// Boxes a value-stack register to the ref stack, preserving the Dart
  /// runtime type. Bools (stored as int 0/1) are converted to actual `bool`
  /// objects via a conditional pattern; ints and doubles use BOX_INT/BOX_DOUBLE.
  ///
  /// Returns the ref-stack register containing the boxed value.
  int _emitBoxToRef(int valueReg, ir.DartType? type) {
    final refReg = _allocRefReg();
    if (type != null && _isDoubleType(type)) {
      _emitter.emit(encodeABC(Op.boxDouble, refReg, valueReg, 0));
    } else if (type != null && _isBoolType(type)) {
      // Bools are stored as int 0/1 on the value stack. BOX_INT would create
      // an int object, not a bool. Emit a conditional to produce a real bool:
      //   JUMP_IF_FALSE valueReg, +2
      //   LOAD_CONST refReg, <true>
      //   JUMP +1
      //   LOAD_CONST refReg, <false>
      final trueIdx = _constantPool.addRef(true);
      final falseIdx = _constantPool.addRef(false);
      _emitter.emit(encodeAsBx(Op.jumpIfFalse, valueReg, 2));
      _emitter.emit(encodeABx(Op.loadConst, refReg, trueIdx));
      _emitter.emit(encodeAsBx(Op.jump, 0, 1));
      _emitter.emit(encodeABx(Op.loadConst, refReg, falseIdx));
    } else {
      _emitter.emit(encodeABC(Op.boxInt, refReg, valueReg, 0));
    }
    return refReg;
  }

  /// Patches pending outgoing arg MOVE placeholders.
  ///
  /// Value args go to `valueRegCount + argIdx`, ref args to
  /// `refRegCount + argIdx`. The VM's CALL_STATIC sets
  /// callee.vBase = caller.vBase + valueRegCount (and similarly for refs),
  /// so outgoing[argIdx] becomes callee.v[argIdx] or callee.r[argIdx].
  void _patchPendingArgMoves() {
    final valRegCount = _valueAlloc.maxUsed;
    final refRegCount = _refAlloc.maxUsed;
    for (final move in _pendingArgMoves) {
      final isValue = move.loc == ResultLoc.value;
      final destReg =
          (isValue ? valRegCount : refRegCount) + move.argIdx;
      final op = isValue ? Op.moveVal : Op.moveRef;
      _emitter.patchJump(move.pc, encodeABC(op, destReg, move.srcReg, 0));
    }
    _pendingArgMoves.clear();
  }

  // ── Statement compilation ──

  void _compileStatement(ir.Statement stmt) {
    if (stmt is ir.ReturnStatement) {
      _compileReturnStatement(stmt);
    } else if (stmt is ir.Block) {
      _compileBlock(stmt);
    } else if (stmt is ir.ExpressionStatement) {
      _compileExpression(stmt.expression);
      // Result discarded — temporary register is not reclaimed here because
      // it may alias a variable binding. Scope-level release handles cleanup.
    } else if (stmt is ir.VariableDeclaration) {
      _compileVariableDeclaration(stmt);
    } else if (stmt is ir.IfStatement) {
      _compileIfStatement(stmt);
    } else if (stmt is ir.WhileStatement) {
      _compileWhileStatement(stmt);
    } else if (stmt is ir.ForStatement) {
      _compileForStatement(stmt);
    } else if (stmt is ir.DoStatement) {
      _compileDoStatement(stmt);
    } else if (stmt is ir.SwitchStatement) {
      _compileSwitchStatement(stmt);
    } else if (stmt is ir.LabeledStatement) {
      _compileLabeledStatement(stmt);
    } else if (stmt is ir.BreakStatement) {
      _compileBreakStatement(stmt);
    } else if (stmt is ir.TryCatch) {
      _compileTryCatch(stmt);
    } else if (stmt is ir.TryFinally) {
      _compileTryFinally(stmt);
    } else if (stmt is ir.AssertStatement) {
      _compileAssertStatement(stmt);
    } else if (stmt is ir.EmptyStatement) {
      // No-op.
    } else {
      throw UnsupportedError(
        'Unsupported statement: ${stmt.runtimeType}',
      );
    }
  }

  void _compileBlock(ir.Block block) {
    // Push a child scope for this block.
    final outerScope = _scope;
    _scope = Scope(
      valueAlloc: _valueAlloc,
      refAlloc: _refAlloc,
      parent: outerScope,
    );

    for (final s in block.statements) {
      _compileStatement(s);
    }

    // Release block-local registers and restore outer scope.
    _scope.release();
    _scope = outerScope;
  }

  // ── Control flow: if/else ──

  void _compileIfStatement(ir.IfStatement stmt) {
    // 1. Compile the condition expression → result on value stack.
    final (condReg, _) = _compileExpression(stmt.condition);

    // 2. JUMP_IF_FALSE condReg → else/end (placeholder).
    final jumpToElse = _emitter.emitPlaceholder();

    // 3. Compile then branch.
    _compileStatement(stmt.then);

    if (stmt.otherwise != null) {
      // 4a. JUMP → end (skip else branch, placeholder).
      final jumpToEnd = _emitter.emitPlaceholder();

      // 5. Backpatch: JUMP_IF_FALSE → else start.
      final elsePC = _emitter.currentPC;
      _emitter.patchJump(
        jumpToElse,
        encodeAsBx(Op.jumpIfFalse, condReg, elsePC - jumpToElse - 1),
      );

      // 6. Compile else branch.
      _compileStatement(stmt.otherwise!);

      // 7. Backpatch: JUMP → end.
      final endPC = _emitter.currentPC;
      _emitter.patchJump(
        jumpToEnd,
        encodeAsBx(Op.jump, 0, endPC - jumpToEnd - 1),
      );
    } else {
      // 4b. No else: backpatch JUMP_IF_FALSE → end.
      final endPC = _emitter.currentPC;
      _emitter.patchJump(
        jumpToElse,
        encodeAsBx(Op.jumpIfFalse, condReg, endPC - jumpToElse - 1),
      );
    }
  }

  // ── Control flow: loops ──

  void _compileWhileStatement(ir.WhileStatement stmt) {
    // Record loop start for backward jump.
    final loopStartPC = _emitter.currentPC;

    // 1. Compile condition.
    final (condReg, _) = _compileExpression(stmt.condition);

    // 2. JUMP_IF_FALSE → exit (placeholder).
    final jumpToExit = _emitter.emitPlaceholder();

    // 3. Compile body.
    _compileStatement(stmt.body);

    // 4. JUMP backward to loop start.
    final jumpPC = _emitter.currentPC;
    _emitter.emit(encodeAsBx(Op.jump, 0, loopStartPC - jumpPC - 1));

    // 5. Backpatch exit.
    final exitPC = _emitter.currentPC;
    _emitter.patchJump(
      jumpToExit,
      encodeAsBx(Op.jumpIfFalse, condReg, exitPC - jumpToExit - 1),
    );
  }

  void _compileForStatement(ir.ForStatement stmt) {
    // Enter scope for loop variables.
    final outerScope = _scope;
    _scope = Scope(
      valueAlloc: _valueAlloc,
      refAlloc: _refAlloc,
      parent: outerScope,
    );

    // 1. Compile variable initializers.
    for (final v in stmt.variables) {
      _compileVariableDeclaration(v);
    }

    // 2. Record loop start (condition check point).
    final loopStartPC = _emitter.currentPC;

    // 3. Compile condition (if present; null = infinite loop).
    int? condReg;
    int? jumpToExit;
    if (stmt.condition != null) {
      final (reg, _) = _compileExpression(stmt.condition!);
      condReg = reg;
      jumpToExit = _emitter.emitPlaceholder();
    }

    // 4. Compile body.
    _compileStatement(stmt.body);

    // 5. Compile update expressions.
    for (final update in stmt.updates) {
      _compileExpression(update);
    }

    // 6. JUMP backward to loop start.
    final jumpPC = _emitter.currentPC;
    _emitter.emit(encodeAsBx(Op.jump, 0, loopStartPC - jumpPC - 1));

    // 7. Backpatch exit (if condition exists).
    if (jumpToExit != null) {
      final exitPC = _emitter.currentPC;
      _emitter.patchJump(
        jumpToExit,
        encodeAsBx(Op.jumpIfFalse, condReg!, exitPC - jumpToExit - 1),
      );
    }

    // Exit scope.
    _scope.release();
    _scope = outerScope;
  }

  void _compileDoStatement(ir.DoStatement stmt) {
    // 1. Record loop start.
    final loopStartPC = _emitter.currentPC;

    // 2. Compile body (executes at least once).
    _compileStatement(stmt.body);

    // 3. Compile condition.
    final (condReg, _) = _compileExpression(stmt.condition);

    // 4. JUMP_IF_TRUE backward to loop start.
    final jumpPC = _emitter.currentPC;
    _emitter.emit(encodeAsBx(Op.jumpIfTrue, condReg, loopStartPC - jumpPC - 1));
  }

  // ── Control flow: switch/case ──

  void _compileSwitchStatement(ir.SwitchStatement stmt) {
    // Phase 2 strategy: compile as sequential comparison chain (if-else chain).
    //
    // For each SwitchCase:
    //   - Compare switch expression with each case expression
    //   - If any matches → jump to body
    //   - If none → fall through to next case
    //   - Default case → always executes
    //   - After body → JUMP to switch end

    // 1. Compile switch expression.
    final (switchReg, switchLoc) = _compileExpression(stmt.expression);
    final isValueSwitch = switchLoc == ResultLoc.value;

    // Collect end-of-body jumps for backpatching.
    final endJumps = <int>[];

    for (var i = 0; i < stmt.cases.length; i++) {
      final switchCase = stmt.cases[i];

      if (switchCase.isDefault) {
        // Default case: always execute body.
        _compileStatement(switchCase.body);
        if (i < stmt.cases.length - 1) {
          endJumps.add(_emitter.emitPlaceholder());
        }
        continue;
      }

      // For each case expression, compare and conditionally jump to body.
      final resultReg = _allocValueReg();
      final matchJumps = <int>[];

      for (final caseExpr in switchCase.expressions) {
        final (caseReg, _) = _compileExpression(caseExpr);
        if (isValueSwitch) {
          _emitter.emit(encodeABC(Op.eqInt, resultReg, switchReg, caseReg));
        } else {
          _emitter.emit(encodeABC(Op.eqRef, resultReg, switchReg, caseReg));
        }
        matchJumps.add(_emitter.emitPlaceholder()); // JUMP_IF_TRUE → body
      }

      // No match → jump to next case.
      final nextCaseJump = _emitter.emitPlaceholder();

      // Backpatch match jumps → body start.
      final bodyPC = _emitter.currentPC;
      for (final jumpPC in matchJumps) {
        _emitter.patchJump(
          jumpPC,
          encodeAsBx(Op.jumpIfTrue, resultReg, bodyPC - jumpPC - 1),
        );
      }

      // Compile case body.
      _compileStatement(switchCase.body);

      // JUMP to switch end (skip remaining cases).
      if (i < stmt.cases.length - 1) {
        endJumps.add(_emitter.emitPlaceholder());
      }

      // Backpatch next case jump.
      final nextCasePC = _emitter.currentPC;
      _emitter.patchJump(
        nextCaseJump,
        encodeAsBx(Op.jump, 0, nextCasePC - nextCaseJump - 1),
      );
    }

    // Backpatch all end-of-body jumps.
    final endPC = _emitter.currentPC;
    for (final jumpPC in endJumps) {
      _emitter.patchJump(
        jumpPC,
        encodeAsBx(Op.jump, 0, endPC - jumpPC - 1),
      );
    }
  }

  // ── Control flow: labeled statement & break ──

  void _compileLabeledStatement(ir.LabeledStatement stmt) {
    // Register the label for break target resolution.
    _labelBreakJumps[stmt] = [];

    // Compile the body.
    _compileStatement(stmt.body);

    // Backpatch all break jumps targeting this label.
    final endPC = _emitter.currentPC;
    for (final jumpPC in _labelBreakJumps[stmt]!) {
      _emitter.patchJump(
        jumpPC,
        encodeAsBx(Op.jump, 0, endPC - jumpPC - 1),
      );
    }
    _labelBreakJumps.remove(stmt);
  }

  void _compileBreakStatement(ir.BreakStatement stmt) {
    // Kernel's BreakStatement targets a LabeledStatement.
    final target = stmt.target;
    final breakList = _labelBreakJumps[target];
    if (breakList != null) {
      breakList.add(_emitter.emitPlaceholder());
    } else {
      throw StateError(
        'BreakStatement targets unknown LabeledStatement',
      );
    }
  }

  // ── Control flow: try/catch/finally ──

  void _compileTryCatch(ir.TryCatch stmt) {
    // Record the value/ref stack depths at try entry for stack unwinding.
    final valStackDP = _valueAlloc.maxUsed;
    final refStackDP = _refAlloc.maxUsed;

    // 1. Record try body start PC.
    final startPC = _emitter.currentPC;

    // 2. Compile try body.
    _compileStatement(stmt.body);

    // 3. Record try body end PC and jump over all catch handlers.
    final endPC = _emitter.currentPC;
    final jumpOverCatches = _emitter.emitPlaceholder();

    // 4. Compile each catch clause.
    for (final catchClause in stmt.catches) {
      // Allocate registers for exception and stackTrace variables.
      final exceptionReg = _allocRefReg();
      int stackTraceReg = -1;

      // Declare exception variable in scope.
      if (catchClause.exception != null) {
        _scope.declareWithReg(catchClause.exception!, StackKind.ref, exceptionReg);
      }

      if (catchClause.stackTrace != null) {
        stackTraceReg = _allocRefReg();
        _scope.declareWithReg(
            catchClause.stackTrace!, StackKind.ref, stackTraceReg);
      }

      // Record handler start PC.
      final handlerPC = _emitter.currentPC;

      // Set up rethrow context.
      final savedExReg = _catchExceptionReg;
      final savedStReg = _catchStackTraceReg;
      _catchExceptionReg = exceptionReg;
      _catchStackTraceReg = stackTraceReg;

      // Compile catch body.
      _compileStatement(catchClause.body);

      // Restore rethrow context.
      _catchExceptionReg = savedExReg;
      _catchStackTraceReg = savedStReg;

      // Jump to end of all catch handlers.
      final jumpToEnd = _emitter.emitPlaceholder();

      // Add exception handler entry.
      _exceptionHandlers.add(ExceptionHandler(
        startPC: startPC,
        endPC: endPC,
        handlerPC: handlerPC,
        catchType: -1, // Phase 2: catch-all only
        valStackDP: valStackDP,
        refStackDP: refStackDP,
        exceptionReg: exceptionReg,
        stackTraceReg: stackTraceReg,
      ));

      // Backpatch jump-to-end.
      final endOfHandler = _emitter.currentPC;
      _emitter.patchJump(
        jumpToEnd,
        encodeAsBx(Op.jump, 0, endOfHandler - jumpToEnd - 1),
      );
    }

    // 5. Backpatch jump over catches (from end of try body).
    final afterCatches = _emitter.currentPC;
    _emitter.patchJump(
      jumpOverCatches,
      encodeAsBx(Op.jump, 0, afterCatches - jumpOverCatches - 1),
    );
  }

  void _compileTryFinally(ir.TryFinally stmt) {
    final valStackDP = _valueAlloc.maxUsed;
    final refStackDP = _refAlloc.maxUsed;

    // Allocate registers for exception/stackTrace in the error path.
    final exceptionReg = _allocRefReg();
    final stackTraceReg = _allocRefReg();

    // 1. Record try start PC.
    final startPC = _emitter.currentPC;

    // 2. Compile try body.
    _compileStatement(stmt.body);

    // 3. Record try end and compile finally on normal path.
    final endPC = _emitter.currentPC;

    // Normal path: compile finalizer body.
    _compileStatement(stmt.finalizer);

    // Jump over the exception-path finalizer.
    final jumpOverExPath = _emitter.emitPlaceholder();

    // 4. Exception path: handler entry.
    final handlerPC = _emitter.currentPC;

    // Compile finalizer again for exception path.
    _compileStatement(stmt.finalizer);

    // RETHROW to continue propagating the exception.
    _emitter.emit(encodeABC(Op.rethrow_, exceptionReg, stackTraceReg, 0));

    // 5. Add exception handler.
    _exceptionHandlers.add(ExceptionHandler(
      startPC: startPC,
      endPC: endPC,
      handlerPC: handlerPC,
      catchType: -1, // finally = catch-all
      valStackDP: valStackDP,
      refStackDP: refStackDP,
      exceptionReg: exceptionReg,
      stackTraceReg: stackTraceReg,
    ));

    // 6. Backpatch jump over exception path.
    final afterExPath = _emitter.currentPC;
    _emitter.patchJump(
      jumpOverExPath,
      encodeAsBx(Op.jump, 0, afterExPath - jumpOverExPath - 1),
    );
  }

  // ── Control flow: assert ──

  void _compileAssertStatement(ir.AssertStatement stmt) {
    // Compile the condition expression.
    final (condReg, _) = _compileExpression(stmt.condition);

    // Determine message constant pool index.
    // 0xFFFF = sentinel for "no message".
    int msgIdx = 0xFFFF;
    if (stmt.message != null) {
      // Compile the message expression. For Phase 2, we evaluate it eagerly
      // and store the result in the constant pool if it's a string literal.
      // For non-literal messages, we compile and box the result.
      final msgExpr = stmt.message!;
      if (msgExpr is ir.StringLiteral) {
        msgIdx = _constantPool.addRef(msgExpr.value);
      } else {
        // Evaluate the message and add to constant pool via ref.
        // For now, treat non-literal messages as "no message".
        // Phase 3+ can handle lazy evaluation.
        msgIdx = 0xFFFF;
      }
    }

    // Emit ASSERT A, Bx — instruction checks condition and throws if false.
    _emitter.emit(encodeABx(Op.assert_, condReg, msgIdx));
  }

  // ── Exception expressions: throw / rethrow ──

  (int, ResultLoc) _compileThrow(ir.Throw expr) {
    // 1. Compile the operand (the value being thrown).
    var (reg, loc) = _compileExpression(expr.expression);

    // 2. Ensure it's on the ref stack — exceptions are always objects.
    if (loc == ResultLoc.value) {
      final exprType = _inferExprType(expr.expression);
      reg = _emitBoxToRef(reg, exprType);
    }

    // 3. Emit THROW A.
    _emitter.emit(encodeABC(Op.throw_, reg, 0, 0));

    // Throw has type Never — return a dummy ref register.
    // The result is never used since control transfers to a handler.
    return (reg, ResultLoc.ref);
  }

  (int, ResultLoc) _compileRethrow(ir.Rethrow expr) {
    // Emit RETHROW A, B using the enclosing catch clause's registers.
    assert(_catchExceptionReg >= 0, 'Rethrow outside of catch clause');
    _emitter.emit(
        encodeABC(Op.rethrow_, _catchExceptionReg, _catchStackTraceReg, 0));

    // Rethrow has type Never — return a dummy ref register.
    return (_catchExceptionReg, ResultLoc.ref);
  }

  void _compileReturnStatement(ir.ReturnStatement stmt) {
    final expr = stmt.expression;
    if (_isEntryFunction) {
      // Entry function: compile expression (if any), then HALT terminates.
      if (expr != null) {
        _compileExpression(expr);
      }
      _emitter.emit(encodeAx(Op.halt, 0));
      return;
    }

    if (expr == null) {
      _emitter.emit(encodeABC(Op.returnNull, 0, 0, 0));
      return;
    }

    final (reg, loc) = _compileExpression(expr);
    switch (loc) {
      case ResultLoc.value:
        _emitter.emit(encodeABC(Op.returnVal, reg, 0, 0));
      case ResultLoc.ref:
        _emitter.emit(encodeABC(Op.returnRef, reg, 0, 0));
    }
  }

  void _compileVariableDeclaration(ir.VariableDeclaration decl) {
    final kind = _classifyStackKind(decl.type);
    if (decl.initializer != null) {
      final (initReg, initLoc) = _compileExpression(decl.initializer!);

      // Handle stack kind mismatch: box value→ref when assigning a value-stack
      // result (e.g. int literal) to a ref-stack variable (e.g. int?).
      if (kind == StackKind.ref && initLoc == ResultLoc.value) {
        final refReg = _allocRefReg();
        // Determine the boxing op from the underlying non-nullable type.
        final baseType = decl.type is ir.InterfaceType
            ? (decl.type as ir.InterfaceType)
                .withDeclaredNullability(ir.Nullability.nonNullable)
            : decl.type;
        if (_isDoubleType(baseType)) {
          _emitter.emit(encodeABC(Op.boxDouble, refReg, initReg, 0));
        } else {
          _emitter.emit(encodeABC(Op.boxInt, refReg, initReg, 0));
        }
        _scope.declareWithReg(decl, kind, refReg);
      } else if (kind.isValue && initLoc == ResultLoc.ref) {
        // The declared type says value-stack (e.g. `int`), but the initializer
        // lives on the ref stack (e.g. from a nullable variable). This happens
        // in CFE-desugared `??` where `let int #t = x{int}` has type `int`
        // but the initializer comes from an `int?` variable.
        //
        // Keep the variable on the ref stack so downstream null checks (via
        // EqualsNull/JUMP_IF_NNULL) work correctly. The caller will unbox
        // when actually using the value in a non-null context.
        _scope.declareWithReg(decl, StackKind.ref, initReg);
      } else {
        // Bind the variable to the initializer's result register.
        assert(
          kind.isValue == (initLoc == ResultLoc.value),
          'Type mismatch: declared $kind but initializer is $initLoc '
          'for ${decl.name}',
        );
        _scope.declareWithReg(decl, kind, initReg);
      }
    } else {
      // No initializer — allocate a register and load a default value.
      final binding = _scope.declare(decl, kind);
      if (kind == StackKind.ref) {
        _emitter.emit(encodeABC(Op.loadNull, binding.reg, 0, 0));
      } else {
        _emitter.emit(encodeAsBx(Op.loadInt, binding.reg, 0));
      }
    }
  }

  // ── Expression compilation ──
  //
  // Returns (register, ResultLoc) indicating where the result lives.

  (int, ResultLoc) _compileExpression(ir.Expression expr) {
    if (expr is ir.IntLiteral) return _compileIntLiteral(expr);
    if (expr is ir.BoolLiteral) return _compileBoolLiteral(expr);
    if (expr is ir.DoubleLiteral) return _compileDoubleLiteral(expr);
    if (expr is ir.StringLiteral) return _compileStringLiteral(expr);
    if (expr is ir.NullLiteral) return _compileNullLiteral();
    if (expr is ir.VariableGet) return _compileVariableGet(expr);
    if (expr is ir.VariableSet) return _compileVariableSet(expr);
    if (expr is ir.ConstantExpression) return _compileConstantExpression(expr);
    if (expr is ir.Not) return _compileNot(expr);
    if (expr is ir.EqualsNull) return _compileEqualsNull(expr);
    if (expr is ir.EqualsCall) return _compileEqualsCall(expr);
    if (expr is ir.Let) return _compileLet(expr);
    if (expr is ir.BlockExpression) return _compileBlockExpression(expr);
    if (expr is ir.NullCheck) return _compileNullCheck(expr);
    if (expr is ir.StaticGet) return _compileStaticGet(expr);
    if (expr is ir.StaticSet) return _compileStaticSet(expr);
    if (expr is ir.StaticInvocation) return _compileStaticInvocation(expr);
    if (expr is ir.InstanceInvocation) return _compileInstanceInvocation(expr);
    if (expr is ir.LogicalExpression) return _compileLogicalExpression(expr);
    if (expr is ir.ConditionalExpression) {
      return _compileConditionalExpression(expr);
    }
    if (expr is ir.IsExpression) return _compileIsExpression(expr);
    if (expr is ir.AsExpression) return _compileAsExpression(expr);
    if (expr is ir.Throw) return _compileThrow(expr);
    if (expr is ir.Rethrow) return _compileRethrow(expr);
    throw UnsupportedError(
      'Unsupported expression: ${expr.runtimeType}',
    );
  }

  // ── Value loading primitives ──

  (int, ResultLoc) _loadInt(int value) {
    final reg = _allocValueReg();
    // sBx uses excess-K encoding (K=0x7FFF): asymmetric range [-32767, +32768].
    if (value >= -32767 && value <= 32768) {
      _emitter.emit(encodeAsBx(Op.loadInt, reg, value));
    } else {
      final idx = _constantPool.addInt(value);
      _emitter.emit(encodeABx(Op.loadConstInt, reg, idx));
    }
    return (reg, ResultLoc.value);
  }

  (int, ResultLoc) _loadBool(bool value) {
    final reg = _allocValueReg();
    _emitter.emit(encodeABC(
      value ? Op.loadTrue : Op.loadFalse,
      reg, 0, 0,
    ));
    return (reg, ResultLoc.value);
  }

  (int, ResultLoc) _loadDouble(double value) {
    final reg = _allocValueReg();
    final idx = _constantPool.addDouble(value);
    _emitter.emit(encodeABx(Op.loadConstDbl, reg, idx));
    return (reg, ResultLoc.value);
  }

  (int, ResultLoc) _loadString(String value) {
    final reg = _allocRefReg();
    final idx = _constantPool.addRef(value);
    _emitter.emit(encodeABx(Op.loadConst, reg, idx));
    return (reg, ResultLoc.ref);
  }

  (int, ResultLoc) _loadNull() {
    final reg = _allocRefReg();
    _emitter.emit(encodeABC(Op.loadNull, reg, 0, 0));
    return (reg, ResultLoc.ref);
  }

  // ── Literal visitors ──

  (int, ResultLoc) _compileIntLiteral(ir.IntLiteral lit) => _loadInt(lit.value);

  (int, ResultLoc) _compileBoolLiteral(ir.BoolLiteral lit) =>
      _loadBool(lit.value);

  (int, ResultLoc) _compileDoubleLiteral(ir.DoubleLiteral lit) =>
      _loadDouble(lit.value);

  (int, ResultLoc) _compileStringLiteral(ir.StringLiteral lit) =>
      _loadString(lit.value);

  (int, ResultLoc) _compileNullLiteral() => _loadNull();

  // ── ConstantExpression ──

  (int, ResultLoc) _compileConstantExpression(ir.ConstantExpression expr) {
    final constant = expr.constant;
    if (constant is ir.IntConstant) return _loadInt(constant.value);
    if (constant is ir.DoubleConstant) return _loadDouble(constant.value);
    if (constant is ir.BoolConstant) return _loadBool(constant.value);
    if (constant is ir.StringConstant) return _loadString(constant.value);
    if (constant is ir.NullConstant) return _loadNull();
    throw UnsupportedError(
      'Unsupported constant type: ${constant.runtimeType}',
    );
  }

  // ── Not ──

  (int, ResultLoc) _compileNot(ir.Not expr) {
    final (operandReg, _) = _compileExpression(expr.operand);
    final resultReg = _allocValueReg();
    // Load 1 into result, then XOR with operand: result = operand ^ 1
    _emitter.emit(encodeAsBx(Op.loadInt, resultReg, 1));
    _emitter.emit(encodeABC(Op.bitXor, resultReg, operandReg, resultReg));
    return (resultReg, ResultLoc.value);
  }

  // ── LogicalExpression (&&, ||) ──

  (int, ResultLoc) _compileLogicalExpression(ir.LogicalExpression expr) {
    final (leftReg, _) = _compileExpression(expr.left);

    // &&: short-circuit on false; ||: short-circuit on true.
    final jumpOp = expr.operatorEnum == ir.LogicalExpressionOperator.AND
        ? Op.jumpIfFalse
        : Op.jumpIfTrue;

    final jumpPC = _emitter.emitPlaceholder();
    final (rightReg, _) = _compileExpression(expr.right);

    if (rightReg != leftReg) {
      _emitter.emit(encodeABC(Op.moveVal, leftReg, rightReg, 0));
    }

    final targetPC = _emitter.currentPC;
    _emitter.patchJump(
      jumpPC,
      encodeAsBx(jumpOp, leftReg, targetPC - jumpPC - 1),
    );

    return (leftReg, ResultLoc.value);
  }

  // ── ConditionalExpression (? :) ──

  (int, ResultLoc) _compileConditionalExpression(
    ir.ConditionalExpression expr,
  ) {
    // Determine the result location (value or ref) from the static type.
    final resultLoc = _classifyType(expr.staticType);

    // Allocate the result register BEFORE compiling either branch.
    // Both branches write their result to this same register.
    final resultReg = resultLoc == ResultLoc.ref
        ? _allocRefReg()
        : _allocValueReg();

    // 1. Compile the condition.
    final (condReg, _) = _compileExpression(expr.condition);

    // 2. JUMP_IF_FALSE condReg → else (placeholder).
    final jumpToElse = _emitter.emitPlaceholder();

    // 3. Compile the then branch → move result to resultReg.
    _compileBranchInto(expr.then, resultReg, resultLoc);

    // 4. JUMP → end (placeholder, skip else branch).
    final jumpToEnd = _emitter.emitPlaceholder();

    // 5. Backpatch else label.
    final elsePC = _emitter.currentPC;
    _emitter.patchJump(
      jumpToElse,
      encodeAsBx(Op.jumpIfFalse, condReg, elsePC - jumpToElse - 1),
    );

    // 6. Compile the else branch → move result to resultReg.
    _compileBranchInto(expr.otherwise, resultReg, resultLoc);

    // 7. Backpatch end label.
    final endPC = _emitter.currentPC;
    _emitter.patchJump(
      jumpToEnd,
      encodeAsBx(Op.jump, 0, endPC - jumpToEnd - 1),
    );

    return (resultReg, resultLoc);
  }

  // ── EqualsNull ──

  (int, ResultLoc) _compileEqualsNull(ir.EqualsNull expr) {
    final (refReg, loc) = _compileExpression(expr.expression);
    assert(loc == ResultLoc.ref,
        'EqualsNull operand must be on ref stack (got value)');
    final resultReg = _allocValueReg();
    // EqualsNull always represents `x == null` (no isNot flag).
    // CFE expresses `x != null` as `Not(EqualsNull(x))`.
    // Pattern: LOAD_FALSE → JUMP_IF_NNULL +1 → LOAD_TRUE
    _emitter.emit(encodeABC(Op.loadFalse, resultReg, 0, 0));
    _emitter.emit(encodeAsBx(Op.jumpIfNnull, refReg, 1));
    _emitter.emit(encodeABC(Op.loadTrue, resultReg, 0, 0));
    return (resultReg, ResultLoc.value);
  }

  // ── EqualsCall ──

  (int, ResultLoc) _compileEqualsCall(ir.EqualsCall expr) {
    final leftType = _inferExprType(expr.left);
    final isInt = leftType != null && _isIntType(leftType);
    final isDouble = leftType != null && _isDoubleType(leftType);

    final (lhsReg, _) = _compileExpression(expr.left);
    final (rhsReg, _) = _compileExpression(expr.right);
    final resultReg = _allocValueReg();

    if (isInt) {
      _emitter.emit(encodeABC(Op.eqInt, resultReg, lhsReg, rhsReg));
    } else if (isDouble) {
      _emitter.emit(encodeABC(Op.eqDbl, resultReg, lhsReg, rhsReg));
    } else {
      // EQ_GENERIC dispatches to operator== for value equality on ref-stack
      // objects (e.g. String). Phase 3+ will replace this with CALL_VIRTUAL
      // once user-defined classes are supported.
      _emitter.emit(encodeABC(Op.eqGeneric, resultReg, lhsReg, rhsReg));
    }
    return (resultReg, ResultLoc.value);
  }

  // ── NullCheck ──

  (int, ResultLoc) _compileNullCheck(ir.NullCheck expr) {
    final (reg, loc) = _compileExpression(expr.operand);
    // Value-stack values (int, bool, double) can never be null at runtime,
    // so only emit NULL_CHECK for ref-stack operands.
    if (loc == ResultLoc.ref) {
      _emitter.emit(encodeABC(Op.nullCheck, reg, 0, 0));
      // If the underlying type (ignoring nullability) is a value type,
      // unbox after the null check so the result is on the value stack.
      final type = _inferExprType(expr.operand);
      if (type is ir.InterfaceType) {
        final nonNullType =
            type.withDeclaredNullability(ir.Nullability.nonNullable);
        final kind = _classifyStackKind(nonNullType);
        if (kind.isValue) {
          final unboxOp =
              kind == StackKind.doubleVal ? Op.unboxDouble : Op.unboxInt;
          final valReg = _allocValueReg();
          _emitter.emit(encodeABC(unboxOp, valReg, reg, 0));
          return (valReg, ResultLoc.value);
        }
      }
    }
    return (reg, loc);
  }

  // ── Let ──

  (int, ResultLoc) _compileLet(ir.Let expr) {
    _compileVariableDeclaration(expr.variable);
    return _compileExpression(expr.body);
  }

  // ── BlockExpression ──

  (int, ResultLoc) _compileBlockExpression(ir.BlockExpression expr) {
    // Push a child scope for the block.
    final outerScope = _scope;
    _scope = Scope(
      valueAlloc: _valueAlloc,
      refAlloc: _refAlloc,
      parent: outerScope,
    );

    for (final s in expr.body.statements) {
      _compileStatement(s);
    }

    // Compile value expression inside the scope (can reference block vars).
    final result = _compileExpression(expr.value);

    // Release scope — the result register is NOT scope-tracked (allocated
    // by _allocValueReg/_allocRefReg), so it survives.
    _scope.release();
    _scope = outerScope;

    return result;
  }

  // ── Variable access ──

  VarBinding _lookupVar(ir.VariableDeclaration decl) {
    final binding = _scope.lookup(decl);
    if (binding == null) {
      throw StateError('Undefined variable: ${decl.name}');
    }
    return binding;
  }

  ResultLoc _locOf(VarBinding binding) =>
      binding.kind.isValue ? ResultLoc.value : ResultLoc.ref;

  (int, ResultLoc) _compileVariableGet(ir.VariableGet expr) {
    final binding = _lookupVar(expr.variable);
    return (binding.reg, _locOf(binding));
  }

  (int, ResultLoc) _compileVariableSet(ir.VariableSet expr) {
    final binding = _lookupVar(expr.variable);
    final (srcReg, _) = _compileExpression(expr.value);
    _emitMove(binding.reg, srcReg, _locOf(binding));
    return (binding.reg, _locOf(binding));
  }

  // ── Static field access ──

  (int, ResultLoc) _compileStaticGet(ir.StaticGet expr) {
    final target = expr.targetReference.asMember;
    if (target is ir.Field) {
      final globalIndex = _fieldToGlobalIndex[expr.targetReference];
      if (globalIndex == null) {
        throw UnsupportedError('Unknown static field: ${target.name.text}');
      }
      final refReg = _allocRefReg();
      _emitter.emit(encodeABx(Op.loadGlobal, refReg, globalIndex));

      // Unbox if the field type is a value type.
      final kind = _classifyStackKind(target.type);
      if (kind.isValue) {
        final unboxOp =
            kind == StackKind.doubleVal ? Op.unboxDouble : Op.unboxInt;
        final valReg = _allocValueReg();
        _emitter.emit(encodeABC(unboxOp, valReg, refReg, 0));
        return (valReg, ResultLoc.value);
      }
      return (refReg, ResultLoc.ref);
    }
    throw UnsupportedError(
      'Static getter not yet supported: ${target.name.text}',
    );
  }

  (int, ResultLoc) _compileStaticSet(ir.StaticSet expr) {
    final target = expr.targetReference.asMember;
    if (target is ir.Field) {
      final globalIndex = _fieldToGlobalIndex[expr.targetReference];
      if (globalIndex == null) {
        throw UnsupportedError('Unknown static field: ${target.name.text}');
      }
      final (srcReg, srcLoc) = _compileExpression(expr.value);
      final refReg = _ensureRef(srcReg, srcLoc, target.type);
      _emitter.emit(encodeABx(Op.storeGlobal, refReg, globalIndex));
      return (srcReg, srcLoc); // Assignment evaluates to the assigned value
    }
    throw UnsupportedError(
      'Static setter not yet supported: ${target.name.text}',
    );
  }

  // ── Call expressions ──

  (int, ResultLoc) _compileStaticInvocation(ir.StaticInvocation expr) {
    final target = expr.target;
    final funcId = _procToFuncId[target.reference];
    if (funcId == null) {
      throw UnsupportedError(
        'Unknown static call target: ${target.name.text}',
      );
    }

    // Allocate result register FIRST — it lives within the caller's frame.
    // The VM's RETURN_VAL writes to caller.vBase + resultReg, so it must
    // be within [0, valueRegCount).
    final retType = target.function.returnType;
    final retLoc = _classifyType(retType);
    final resultReg =
        retLoc == ResultLoc.ref ? _allocRefReg() : _allocValueReg();

    // Compile each argument expression to a temp register within the frame.
    // These are "source" registers — the actual outgoing placement happens
    // via MOVE instructions patched after compilation (see _compileProcedure).
    final args = expr.arguments.positional;
    final params = target.function.positionalParameters;
    final argTemps = <(int, ResultLoc)>[];
    for (var i = 0; i < args.length; i++) {
      var (argReg, argLoc) = _compileExpression(args[i]);

      // Box value-stack args when the callee parameter expects ref stack.
      // This handles cases like passing `42` (int, value stack) to an
      // `Object` parameter (ref stack).
      if (i < params.length) {
        final paramKind = _classifyStackKind(params[i].type);
        if (paramKind == StackKind.ref && argLoc == ResultLoc.value) {
          final argType = _inferExprType(args[i]);
          argReg = _emitBoxToRef(argReg, argType);
          argLoc = ResultLoc.ref;
        }
      }

      argTemps.add((argReg, argLoc));
    }

    // Emit placeholder MOVE instructions for each arg. The destination
    // register depends on stack kind: value args go to valueRegCount + idx,
    // ref args go to refRegCount + idx. Since these counts aren't known yet
    // (the function is still being compiled), we record positions and patch
    // them in _compileProcedure after compilation finishes.
    //
    // Value and ref args maintain separate arg indices because they live on
    // separate stacks. The callee sees value args as v0, v1, ... and ref
    // args as r3, r4, ... (after ITA/FTA/this).
    var valArgIdx = 0;
    var refArgIdx = 0;
    for (var i = 0; i < argTemps.length; i++) {
      final (srcReg, loc) = argTemps[i];
      final movePC = _emitter.emitPlaceholder();
      final argIdx = loc == ResultLoc.value ? valArgIdx++ : refArgIdx++;
      _pendingArgMoves.add(
        (pc: movePC, srcReg: srcReg, argIdx: argIdx, loc: loc),
      );
    }

    _emitter.emit(encodeABx(Op.callStatic, resultReg, funcId));

    return (resultReg, retLoc);
  }

  (int, ResultLoc) _compileInstanceInvocation(ir.InstanceInvocation expr) {
    // Specialize arithmetic operators for int and double.
    //
    // In Dart, `int` extends `num`, so arithmetic operators (+, -, *, etc.)
    // are defined on `num`. The interfaceTarget.enclosingClass is `num`,
    // not `int`. We check both, then use the receiver's type to decide
    // between int and double instructions.
    final targetClass = expr.interfaceTarget.enclosingClass;
    final name = expr.name.text;

    if (targetClass == _coreTypes.intClass ||
        targetClass == _coreTypes.numClass) {
      final receiverType = _inferExprType(expr.receiver);

      // int `/` returns double — convert both operands and use DIV_DBL.
      if (name == '/' &&
          receiverType != null &&
          _isIntType(receiverType)) {
        final (lhsReg, _) = _compileExpression(expr.receiver);
        final (rhsReg, _) =
            _compileExpression(expr.arguments.positional[0]);
        // Convert both int operands to double.
        final lhsDbl = _allocValueReg();
        _emitter.emit(encodeABC(Op.intToDbl, lhsDbl, lhsReg, 0));
        final rhsDbl = _allocValueReg();
        _emitter.emit(encodeABC(Op.intToDbl, rhsDbl, rhsReg, 0));
        final resultReg = _allocValueReg();
        _emitter.emit(encodeABC(Op.divDbl, resultReg, lhsDbl, rhsDbl));
        return (resultReg, ResultLoc.value);
      }

      // Check if receiver is statically int.
      if (receiverType != null && _isIntType(receiverType)) {
        final op = _intBinaryOp(name);
        if (op != null) return _emitBinaryOp(expr, op);
        if (name == 'unary-') return _emitUnaryOp(expr, Op.negInt);
        if (name == '~') return _emitUnaryOp(expr, Op.bitNot);
        if (name == 'toDouble') return _emitUnaryOp(expr, Op.intToDbl);
      }

      // Check if receiver is statically double.
      if (receiverType != null && _isDoubleType(receiverType)) {
        final result = _tryCompileDoubleOp(expr, name);
        if (result != null) return result;
      }
    }

    // double-specific class target (e.g., double.operator/).
    if (targetClass == _coreTypes.doubleClass) {
      final result = _tryCompileDoubleOp(expr, name);
      if (result != null) return result;
    }

    throw UnsupportedError(
      'Unsupported instance invocation: $name on $targetClass',
    );
  }

  /// Tries to compile a double operation (arithmetic, comparison, unary, toInt).
  /// Returns null if [name] is not a recognized double operation.
  (int, ResultLoc)? _tryCompileDoubleOp(
    ir.InstanceInvocation expr,
    String name,
  ) {
    final op = _doubleBinaryOp(name);
    if (op != null) return _emitBinaryOp(expr, op);
    if (name == 'unary-') return _emitUnaryOp(expr, Op.negDbl);
    if (name == 'toInt') return _emitUnaryOp(expr, Op.dblToInt);
    return null;
  }

  // ── Type operations (is / as) ──

  (int, ResultLoc) _compileIsExpression(ir.IsExpression expr) {
    // 1. Compile operand.
    var (operandReg, operandLoc) = _compileExpression(expr.operand);

    // 2. Box if on value stack — INSTANCEOF needs the operand on the ref stack.
    if (operandLoc == ResultLoc.value) {
      final operandType = _inferExprType(expr.operand);
      operandReg = _emitBoxToRef(operandReg, operandType);
    }

    // 3. Create type checker function and add to constant pool.
    final checker = _createTypeChecker(expr.type);
    final checkerIdx = _constantPool.addRef(checker);
    assert(checkerIdx <= 0xFF,
        'INSTANCEOF C operand overflow: checkerIdx=$checkerIdx > 255');

    // 4. Emit INSTANCEOF A, B, C.
    final resultReg = _allocValueReg();
    _emitter.emit(encodeABC(Op.instanceOf, resultReg, operandReg, checkerIdx));

    return (resultReg, ResultLoc.value);
  }

  (int, ResultLoc) _compileAsExpression(ir.AsExpression expr) {
    // 1. Compile operand.
    var (operandReg, operandLoc) = _compileExpression(expr.operand);

    // 2. Box if on value stack — CAST needs the operand on the ref stack.
    if (operandLoc == ResultLoc.value) {
      final operandType = _inferExprType(expr.operand);
      operandReg = _emitBoxToRef(operandReg, operandType);
    }

    // 3. Create cast function and add to constant pool.
    final caster = _createCaster(expr.type);
    final casterIdx = _constantPool.addRef(caster);
    assert(casterIdx <= 0xFF,
        'CAST C operand overflow: casterIdx=$casterIdx > 255');

    // 4. Emit CAST A, B, C.
    final resultReg = _allocRefReg();
    _emitter.emit(encodeABC(Op.cast, resultReg, operandReg, casterIdx));

    return (resultReg, ResultLoc.ref);
  }

  /// Creates a type-checking function for the Phase 2 simplified is-check.
  ///
  /// Delegates to Dart host VM's `is` operator via a closure stored in the
  /// constant pool. Phase 4 will replace this with DarticType/TypeTemplate.
  bool Function(Object?) _createTypeChecker(ir.DartType type) {
    if (type is ir.InterfaceType) {
      final cls = type.classNode;
      if (cls == _coreTypes.intClass) return (v) => v is int;
      if (cls == _coreTypes.doubleClass) return (v) => v is double;
      if (cls == _coreTypes.boolClass) return (v) => v is bool;
      if (cls == _coreTypes.stringClass) return (v) => v is String;
      if (cls == _coreTypes.numClass) return (v) => v is num;
      if (cls == _coreTypes.objectClass) {
        // Object? (nullable) matches everything; Object (non-nullable) excludes null.
        if (type.nullability == ir.Nullability.nullable) return (v) => true;
        return (v) => v != null;
      }
    }
    if (type is ir.NullType) return (v) => v == null;
    throw UnsupportedError('Unsupported type for is check: $type');
  }

  /// Creates a cast function for the Phase 2 simplified as-cast.
  ///
  /// Delegates to Dart host VM's `as` operator. Throws [TypeError] on failure.
  /// Phase 4 will replace this with DarticType/TypeTemplate.
  Object? Function(Object?) _createCaster(ir.DartType type) {
    if (type is ir.InterfaceType) {
      final cls = type.classNode;
      if (cls == _coreTypes.intClass) return (v) => v as int;
      if (cls == _coreTypes.doubleClass) return (v) => v as double;
      if (cls == _coreTypes.boolClass) return (v) => v as bool;
      if (cls == _coreTypes.stringClass) return (v) => v as String;
      if (cls == _coreTypes.numClass) return (v) => v as num;
      if (cls == _coreTypes.objectClass) {
        if (type.nullability == ir.Nullability.nullable) return (v) => v;
        return (v) => v as Object;
      }
    }
    if (type is ir.NullType) return (v) => v as Null;
    throw UnsupportedError('Unsupported type for cast: $type');
  }

  // ── Type classification ──

  late final CoreTypes _coreTypes = CoreTypes(_component);

  /// Infers the static DartType of an expression without StaticTypeContext.
  ///
  /// Handles common cases needed for Phase 1 int arithmetic specialization.
  ir.DartType? _inferExprType(ir.Expression expr) {
    if (expr is ir.VariableGet) return expr.variable.type;
    if (expr is ir.IntLiteral) return _coreTypes.intNonNullableRawType;
    if (expr is ir.DoubleLiteral) return _coreTypes.doubleNonNullableRawType;
    if (expr is ir.BoolLiteral) return _coreTypes.boolNonNullableRawType;
    if (expr is ir.StringLiteral) return _coreTypes.stringNonNullableRawType;
    if (expr is ir.NullLiteral) return const ir.NullType();
    if (expr is ir.ConstantExpression) return _inferConstantType(expr.constant);
    if (expr is ir.Not) return _coreTypes.boolNonNullableRawType;
    if (expr is ir.LogicalExpression) return _coreTypes.boolNonNullableRawType;
    if (expr is ir.EqualsNull) return _coreTypes.boolNonNullableRawType;
    if (expr is ir.EqualsCall) return _coreTypes.boolNonNullableRawType;
    if (expr is ir.ConditionalExpression) return expr.staticType;
    if (expr is ir.Let) return _inferExprType(expr.body);
    if (expr is ir.BlockExpression) return _inferExprType(expr.value);
    if (expr is ir.NullCheck) {
      final operandType = _inferExprType(expr.operand);
      // NullCheck produces the non-nullable version of the operand type.
      if (operandType is ir.InterfaceType &&
          operandType.nullability == ir.Nullability.nullable) {
        return operandType.withDeclaredNullability(ir.Nullability.nonNullable);
      }
      return operandType;
    }
    if (expr is ir.StaticGet) {
      final target = expr.targetReference.asMember;
      if (target is ir.Field) return target.type;
      if (target is ir.Procedure) return target.function.returnType;
    }
    if (expr is ir.IsExpression) return _coreTypes.boolNonNullableRawType;
    if (expr is ir.AsExpression) return expr.type;
    if (expr is ir.StaticInvocation) return expr.target.function.returnType;
    if (expr is ir.InstanceInvocation) {
      // For chained operations like (a + b) - c:
      // num.operator+ returns `num`, but if the receiver is `int`,
      // the result is `int` at runtime. Propagate the more specific type.
      //
      // Exception: `/` on int returns `double` (Dart spec). Also, if the
      // receiver is `double`, the result is `double`.
      final targetClass = expr.interfaceTarget.enclosingClass;
      final invName = expr.name.text;
      // Comparison operators always return bool, regardless of receiver type.
      if (_isCompareOp(invName)) {
        return _coreTypes.boolNonNullableRawType;
      }
      if (targetClass == _coreTypes.numClass ||
          targetClass == _coreTypes.intClass) {
        final receiverType = _inferExprType(expr.receiver);
        if (receiverType != null && _isIntType(receiverType)) {
          // int `/` returns double; toDouble() returns double.
          if (invName == '/' || invName == 'toDouble') {
            return _coreTypes.doubleNonNullableRawType;
          }
          return _coreTypes.intNonNullableRawType;
        }
        if (receiverType != null && _isDoubleType(receiverType)) {
          // toInt() on double returns int.
          if (invName == 'toInt') {
            return _coreTypes.intNonNullableRawType;
          }
          return _coreTypes.doubleNonNullableRawType;
        }
      }
      if (targetClass == _coreTypes.doubleClass) {
        // Comparison operators already handled above.
        if (invName == 'toInt') {
          return _coreTypes.intNonNullableRawType;
        }
        return _coreTypes.doubleNonNullableRawType;
      }
      return expr.interfaceTarget.function.returnType;
    }
    return null;
  }

  bool _isIntType(ir.DartType type) =>
      type is ir.InterfaceType && type.classNode == _coreTypes.intClass;

  bool _isDoubleType(ir.DartType type) =>
      type is ir.InterfaceType && type.classNode == _coreTypes.doubleClass;

  bool _isBoolType(ir.DartType type) =>
      type is ir.InterfaceType && type.classNode == _coreTypes.boolClass;

  ir.DartType? _inferConstantType(ir.Constant constant) => switch (constant) {
        ir.IntConstant() => _coreTypes.intNonNullableRawType,
        ir.DoubleConstant() => _coreTypes.doubleNonNullableRawType,
        ir.BoolConstant() => _coreTypes.boolNonNullableRawType,
        ir.StringConstant() => _coreTypes.stringNonNullableRawType,
        ir.NullConstant() => const ir.NullType(),
        _ => null,
      };

  /// Classifies a DartType for expression result location (value or ref).
  ///
  /// Derived from [_classifyStackKind] to avoid duplicating the type→stack
  /// classification logic.
  ResultLoc _classifyType(ir.DartType type) =>
      _classifyStackKind(type).isValue ? ResultLoc.value : ResultLoc.ref;

  /// Classifies a DartType for scope-level register allocation.
  ///
  /// Canonical type classification: int/bool → intVal (value stack intView),
  /// double → doubleVal (value stack doubleView),
  /// everything else → ref (ref stack).
  StackKind _classifyStackKind(ir.DartType type) {
    if (type is ir.InterfaceType) {
      // Nullable value types (int?, bool?, double?) must go on the ref stack
      // because only ref registers can represent null.
      if (type.nullability == ir.Nullability.nullable) return StackKind.ref;
      final cls = type.classNode;
      if (cls == _coreTypes.intClass) return StackKind.intVal;
      if (cls == _coreTypes.boolClass) return StackKind.intVal;
      if (cls == _coreTypes.doubleClass) return StackKind.doubleVal;
    }
    return StackKind.ref;
  }

  /// Maps int binary operator names to opcodes (arithmetic + comparison).
  static int? _intBinaryOp(String name) => switch (name) {
        '+' => Op.addInt,
        '-' => Op.subInt,
        '*' => Op.mulInt,
        '~/' => Op.divInt,
        '%' => Op.modInt,
        '&' => Op.bitAnd,
        '|' => Op.bitOr,
        '^' => Op.bitXor,
        '<<' => Op.shl,
        '>>' => Op.shr,
        '>>>' => Op.ushr,
        '<' => Op.ltInt,
        '<=' => Op.leInt,
        '>' => Op.gtInt,
        '>=' => Op.geInt,
        _ => null,
      };

  /// Maps double binary operator names to opcodes (arithmetic + comparison).
  static int? _doubleBinaryOp(String name) => switch (name) {
        '+' => Op.addDbl,
        '-' => Op.subDbl,
        '*' => Op.mulDbl,
        '/' => Op.divDbl,
        '<' => Op.ltDbl,
        '<=' => Op.leDbl,
        '>' => Op.gtDbl,
        '>=' => Op.geDbl,
        _ => null,
      };

  /// Returns true if the operator name is a comparison operator.
  static bool _isCompareOp(String name) =>
      name == '<' || name == '<=' || name == '>' || name == '>=';

  // ── Helpers ──

  bool _isPlatformLibrary(ir.Library lib) => lib.importUri.isScheme('dart');

  static final _haltBytecode =
      Uint32List.fromList([encodeAx(Op.halt, 0)]);
}
