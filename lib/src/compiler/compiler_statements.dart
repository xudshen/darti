part of 'compiler.dart';

/// Statement compilation methods for [DarticCompiler].
///
/// Contains [_compileStatement] dispatch and all individual statement
/// compilation methods (if, while, for, do, switch, labeled, break,
/// try/catch, try/finally, assert, return, block, variable declaration).
extension on DarticCompiler {
  // ── Statement compilation ──

  void _compileStatement(ir.Statement stmt) => stmt.accept(_stmtVisitor);

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

    // Emit CLOSE_UPVALUE for captured variables going out of scope.
    _emitCloseUpvaluesForScope(_scope);

    // Release block-local registers and restore outer scope.
    _scope.release();
    _scope = outerScope;
  }

  // ── Control flow: if/else ──

  void _compileIfStatement(ir.IfStatement stmt) {
    // 1. Compile the condition expression -> result on value stack.
    var (condReg, condLoc) = _compileExpression(stmt.condition);
    condReg = _ensureBoolValue(condReg, condLoc);

    // 2. JUMP_IF_FALSE condReg -> else/end (placeholder).
    final jumpToElse = _emitter.emitPlaceholder();

    // 3. Compile then branch.
    _compileStatement(stmt.then);

    if (stmt.otherwise != null) {
      // 4a. JUMP -> end (skip else branch, placeholder).
      final jumpToEnd = _emitter.emitPlaceholder();

      // 5. Backpatch: JUMP_IF_FALSE -> else start.
      final elsePC = _emitter.currentPC;
      _emitter.patchJump(
        jumpToElse,
        encodeAsBx(Op.jumpIfFalse, condReg, elsePC - jumpToElse - 1),
      );

      // 6. Compile else branch.
      _compileStatement(stmt.otherwise!);

      // 7. Backpatch: JUMP -> end.
      final endPC = _emitter.currentPC;
      _emitter.patchJump(
        jumpToEnd,
        encodeAsBx(Op.jump, 0, endPC - jumpToEnd - 1),
      );
    } else {
      // 4b. No else: backpatch JUMP_IF_FALSE -> end.
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
    var (condReg, condLoc) = _compileExpression(stmt.condition);
    condReg = _ensureBoolValue(condReg, condLoc);

    // 2. JUMP_IF_FALSE -> exit (placeholder).
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
      var (reg, regLoc) = _compileExpression(stmt.condition!);
      reg = _ensureBoolValue(reg, regLoc);
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

    // Emit CLOSE_UPVALUE for captured loop variables going out of scope.
    _emitCloseUpvaluesForScope(_scope);

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
    var (condReg, condLoc) = _compileExpression(stmt.condition);
    condReg = _ensureBoolValue(condReg, condLoc);

    // 4. JUMP_IF_TRUE backward to loop start.
    final jumpPC = _emitter.currentPC;
    _emitter.emit(
        encodeAsBx(Op.jumpIfTrue, condReg, loopStartPC - jumpPC - 1));
  }

  // ── Control flow: switch/case ──

  void _compileSwitchStatement(ir.SwitchStatement stmt) {
    // Phase 2 strategy: compile as sequential comparison chain (if-else chain).

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
        matchJumps.add(_emitter.emitPlaceholder()); // JUMP_IF_TRUE -> body
      }

      // No match -> jump to next case.
      final nextCaseJump = _emitter.emitPlaceholder();

      // Backpatch match jumps -> body start.
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
        _scope.declareWithReg(
            catchClause.exception!, StackKind.ref, exceptionReg);
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

      // Determine catch type: -1 for catch-all, constant pool index for typed.
      // In Kernel, untyped `catch(e)` has guard == Object (sound null safety)
      // or DynamicType. Both are catch-all semantics.
      int catchType = -1;
      final guard = catchClause.guard;
      final isCatchAll = guard is ir.DynamicType ||
          (guard is ir.InterfaceType &&
              guard.classNode == _coreTypes.objectClass);
      if (!isCatchAll) {
        final template = dartTypeToTemplate(
          guard,
          _typeClassIdLookup,
          enclosingClassTypeParams: _currentClassTypeParams,
          enclosingFunctionTypeParams: _currentFunctionTypeParams,
        );
        catchType = _constantPool.addRef(template);
      }

      // Add exception handler entry.
      _exceptionHandlers.add(ExceptionHandler(
        startPC: startPC,
        endPC: endPC,
        handlerPC: handlerPC,
        catchType: catchType,
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
    var (condReg, condLoc) = _compileExpression(stmt.condition);
    condReg = _ensureBoolValue(condReg, condLoc);

    // Determine message constant pool index.
    // 0xFFFF = sentinel for "no message".
    int msgIdx = 0xFFFF;
    if (stmt.message != null) {
      final msgExpr = stmt.message!;
      if (msgExpr is ir.StringLiteral) {
        msgIdx = _constantPool.addRef(msgExpr.value);
      }
      // For non-literal messages, treat as "no message" (Phase 3+ can
      // handle lazy evaluation).
    }

    // Emit ASSERT A, Bx -- instruction checks condition and throws if false.
    _emitter.emit(encodeABx(Op.assert_, condReg, msgIdx));
  }

  // ── Return statement ──

  void _compileReturnStatement(ir.ReturnStatement stmt) {
    final expr = stmt.expression;
    if (_isEntryFunction) {
      // Entry function: encode result register and type in HALT ABC fields.
      // B field: 0=void, 1=ref, 2=boolVal, 3=intVal, 4=doubleVal (StackKind.index + 1).
      if (expr != null) {
        final (reg, loc) = _compileExpression(expr);
        final StackKind kind;
        if (loc == ResultLoc.ref) {
          kind = StackKind.ref;
        } else {
          // Value stack — distinguish int vs double via type inference.
          // Default to intVal when type is completely unknown.
          final exprType = _inferExprType(expr);
          kind = exprType != null
              ? _classifyStackKind(exprType)
              : StackKind.intVal;
        }
        _emitter.emit(encodeABC(Op.halt, reg, kind.index + 1, 0));
      } else {
        _emitter.emit(encodeABC(Op.halt, 0, 0, 0));
      }
      return;
    }

    if (expr == null) {
      _emitCloseUpvaluesIfNeeded();
      _emitter.emit(encodeABC(Op.returnNull, 0, 0, 0));
      return;
    }

    final (reg, loc) = _compileExpression(expr);
    _emitCloseUpvaluesIfNeeded();

    // Coerce result between value/ref stacks when they don't match the
    // function's declared return type.
    final retKind = _classifyStackKind(_currentReturnType);
    if (loc == ResultLoc.ref && retKind.isValue) {
      // Unbox: expression is on ref stack but function returns a value type.
      // E.g. `Object x = 42; return x as int;` — `as int` stays on ref stack,
      // but caller expects RETURN_VAL for int return type.
      final valReg = _valueAlloc.alloc();
      final unboxOp = retKind == StackKind.doubleVal
          ? Op.unboxDouble
          : Op.unboxInt;
      _emitter.emit(encodeABC(unboxOp, valReg, reg, 0));
      _emitter.emit(encodeABC(Op.returnVal, valReg, 0, 0));
    } else if (loc == ResultLoc.value && retKind == StackKind.ref) {
      // Box: expression is on value stack but function returns a nullable
      // value type (int?, bool?, double?).  The caller expects RETURN_REF.
      // E.g. `int? f() => 42;` — literal 42 is on the value stack but the
      // return type int? requires the ref stack.
      // Use _emitBoxToRef which correctly handles bool (JUMP_IF_FALSE pattern)
      // in addition to int (BOX_INT) and double (BOX_DOUBLE).
      final exprType = _inferExprType(expr);
      final refReg = _emitBoxToRef(reg, exprType);
      _emitter.emit(encodeABC(Op.returnRef, refReg, 0, 0));
    } else {
      switch (loc) {
        case ResultLoc.value:
          _emitter.emit(encodeABC(Op.returnVal, reg, 0, 0));
        case ResultLoc.ref:
          _emitter.emit(encodeABC(Op.returnRef, reg, 0, 0));
      }
    }
  }

  // ── Upvalue close helper ──

  /// Emits CLOSE_UPVALUE for captured variables going out of [scope].
  ///
  /// Only closes upvalues for variables declared in [scope], not parents.
  /// Finds the minimum ref register among captured variables in this scope
  /// and emits a single CLOSE_UPVALUE instruction (the VM closes all open
  /// upvalues at or above the given register).
  void _emitCloseUpvaluesForScope(Scope scope) {
    int minReg = -1;
    for (final varDecl in scope.localDeclarations) {
      final refReg = _capturedVarRefRegs[varDecl];
      if (refReg != null && (minReg == -1 || refReg < minReg)) {
        minReg = refReg;
      }
    }
    if (minReg != -1) {
      _emitter.emit(encodeABC(Op.closeUpvalue, minReg, 0, 0));
    }
  }

  // ── Variable declaration ──

  void _compileVariableDeclaration(ir.VariableDeclaration decl) {
    final kind = _classifyStackKind(decl.type);
    if (decl.initializer != null) {
      final (initReg, initLoc) = _compileExpression(decl.initializer!);

      // Handle stack kind mismatch: box value->ref when assigning a value-stack
      // result (e.g. int literal) to a ref-stack variable (e.g. int?).
      if (kind == StackKind.ref && initLoc == ResultLoc.value) {
        final refReg = _allocRefReg();
        // Determine the boxing op from the underlying non-nullable type.
        final baseType = decl.type is ir.InterfaceType
            ? (decl.type as ir.InterfaceType)
                .withDeclaredNullability(ir.Nullability.nonNullable)
            : decl.type;
        final boxOp = switch (_classifyStackKind(baseType)) {
          StackKind.doubleVal => Op.boxDouble,
          StackKind.boolVal => Op.boxBool,
          _ => Op.boxInt,
        };
        _emitter.emit(encodeABC(boxOp, refReg, initReg, 0));
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

        // If the initializer is a VariableGet, the returned register belongs to
        // an existing variable. We must allocate a fresh register and copy the
        // value so the new variable does not alias the source. Without this, code
        // like `int a = 1; int b = a; b = 5;` would corrupt `a`.
        if (decl.initializer is ir.VariableGet) {
          final binding = _scope.declare(decl, kind);
          final loc = kind.isValue ? ResultLoc.value : ResultLoc.ref;
          _emitMove(binding.reg, initReg, loc);
        } else {
          _scope.declareWithReg(decl, kind, initReg);
        }
      }
    } else {
      // No initializer -- allocate a register and load a default value.
      final binding = _scope.declare(decl, kind);
      if (kind == StackKind.ref) {
        _emitter.emit(encodeABC(Op.loadNull, binding.reg, 0, 0));
      } else {
        _emitter.emit(encodeAsBx(Op.loadInt, binding.reg, 0));
      }
    }
  }
}

/// Visitor that compiles statements by delegating to `_compileXxx` extension
/// methods.
class _StmtCompileVisitor with ir.StatementVisitorDefaultMixin<void> {
  _StmtCompileVisitor(this._c);
  final DarticCompiler _c;

  @override
  void defaultStatement(ir.Statement node) =>
      throw UnsupportedError(
        'Statement not yet implemented: ${node.runtimeType}. '
        'This may be added in a future compiler phase.',
      );

  @override
  void visitReturnStatement(ir.ReturnStatement node) =>
      _c._compileReturnStatement(node);
  @override
  void visitBlock(ir.Block node) => _c._compileBlock(node);
  @override
  void visitExpressionStatement(ir.ExpressionStatement node) =>
      _c._compileExpression(node.expression);
  @override
  void visitVariableDeclaration(ir.VariableDeclaration node) =>
      _c._compileVariableDeclaration(node);
  @override
  void visitIfStatement(ir.IfStatement node) =>
      _c._compileIfStatement(node);
  @override
  void visitWhileStatement(ir.WhileStatement node) =>
      _c._compileWhileStatement(node);
  @override
  void visitForStatement(ir.ForStatement node) =>
      _c._compileForStatement(node);
  @override
  void visitDoStatement(ir.DoStatement node) =>
      _c._compileDoStatement(node);
  @override
  void visitSwitchStatement(ir.SwitchStatement node) =>
      _c._compileSwitchStatement(node);
  @override
  void visitLabeledStatement(ir.LabeledStatement node) =>
      _c._compileLabeledStatement(node);
  @override
  void visitBreakStatement(ir.BreakStatement node) =>
      _c._compileBreakStatement(node);
  @override
  void visitTryCatch(ir.TryCatch node) => _c._compileTryCatch(node);
  @override
  void visitTryFinally(ir.TryFinally node) => _c._compileTryFinally(node);
  @override
  void visitAssertStatement(ir.AssertStatement node) =>
      _c._compileAssertStatement(node);
  @override
  void visitFunctionDeclaration(ir.FunctionDeclaration node) =>
      _c._compileFunctionDeclaration(node);
  @override
  void visitEmptyStatement(ir.EmptyStatement node) {}
}
