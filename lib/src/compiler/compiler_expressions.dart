part of 'compiler.dart';

/// Expression compilation methods for [DarticCompiler].
///
/// Contains [_compileExpression] dispatch and all individual expression
/// visitor methods (literals, variable access, constants, logical, conditional,
/// null operations, static field access, call expressions, type operations,
/// throw/rethrow, closures).
extension on DarticCompiler {
  // ── Expression compilation ──
  //
  // Returns (register, ResultLoc) indicating where the result lives.

  (int, ResultLoc) _compileExpression(ir.Expression expr) =>
      expr.accept(_exprVisitor);

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

  // ── StringConcatenation (string interpolation) ──

  (int, ResultLoc) _compileStringConcatenation(ir.StringConcatenation expr) {
    final parts = expr.expressions;

    // Empty interpolation → empty string.
    if (parts.isEmpty) {
      return _loadString('');
    }

    // Single StringLiteral → no need to emit STRING_INTERP.
    if (parts.length == 1 && parts[0] is ir.StringLiteral) {
      return _loadString((parts[0] as ir.StringLiteral).value);
    }

    // Phase 1: Compile each part, ensuring all results are on the ref stack.
    final partRegs = <int>[];
    for (final part in parts) {
      var (reg, loc) = _compileExpression(part);
      reg = _boxToRefIfValue(reg, loc, _inferExprType(part));
      partRegs.add(reg);
    }

    // Phase 2: Allocate consecutive ref registers for STRING_INTERP operands.
    // The dest register comes first, then the base + part count.
    final destReg = _allocRefReg();
    final baseReg = _allocRefReg();
    for (var i = 1; i < parts.length; i++) {
      _allocRefReg(); // allocate remaining consecutive slots
    }

    // Phase 3: Move each part result into its consecutive slot.
    for (var i = 0; i < partRegs.length; i++) {
      if (partRegs[i] != baseReg + i) {
        _emitter.emit(encodeABC(Op.moveRef, baseReg + i, partRegs[i], 0));
      }
    }

    // Phase 4: Emit STRING_INTERP A=destReg, B=baseReg, C=partCount.
    _emitter.emit(encodeABC(Op.stringInterp, destReg, baseReg, parts.length));
    return (destReg, ResultLoc.ref);
  }

  // ── ConstantExpression ──

  (int, ResultLoc) _compileConstantExpression(ir.ConstantExpression expr) =>
      expr.constant.accept(_constantVisitor);

  // ── Not ──

  (int, ResultLoc) _compileNot(ir.Not expr) {
    var (operandReg, operandLoc) = _compileExpression(expr.operand);
    operandReg = _ensureBoolValue(operandReg, operandLoc);
    final resultReg = _allocValueReg();
    _emitter.emit(encodeABC(Op.notBool, resultReg, operandReg, 0));
    return (resultReg, ResultLoc.value);
  }

  // ── LogicalExpression (&&, ||) ──

  (int, ResultLoc) _compileLogicalExpression(ir.LogicalExpression expr) {
    var (leftReg, leftLoc) = _compileExpression(expr.left);
    leftReg = _ensureBoolValue(leftReg, leftLoc);

    // &&: short-circuit on false; ||: short-circuit on true.
    final jumpOp = expr.operatorEnum == ir.LogicalExpressionOperator.AND
        ? Op.jumpIfFalse
        : Op.jumpIfTrue;

    final jumpPC = _emitter.emitPlaceholder();
    var (rightReg, rightLoc) = _compileExpression(expr.right);
    rightReg = _ensureBoolValue(rightReg, rightLoc);

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
    var (condReg, condLoc) = _compileExpression(expr.condition);
    condReg = _ensureBoolValue(condReg, condLoc);

    // 2. JUMP_IF_FALSE condReg -> else (placeholder).
    final jumpToElse = _emitter.emitPlaceholder();

    // 3. Compile the then branch -> move result to resultReg.
    _compileBranchInto(expr.then, resultReg, resultLoc);

    // 4. JUMP -> end (placeholder, skip else branch).
    final jumpToEnd = _emitter.emitPlaceholder();

    // 5. Backpatch else label.
    final elsePC = _emitter.currentPC;
    _emitter.patchJump(
      jumpToElse,
      encodeAsBx(Op.jumpIfFalse, condReg, elsePC - jumpToElse - 1),
    );

    // 6. Compile the else branch -> move result to resultReg.
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
    final (reg, loc) = _compileExpression(expr.expression);
    final resultReg = _allocValueReg();
    if (loc == ResultLoc.value) {
      // Value-stack operands (int, bool, double) can never be null.
      // This can happen in CFE-desugared chained `??` where an intermediate
      // Let variable has non-nullable type but is still tested with EqualsNull.
      // Just emit LOAD_FALSE — the result is always "not null".
      _emitter.emit(encodeABC(Op.loadFalse, resultReg, 0, 0));
      return (resultReg, ResultLoc.value);
    }
    // EqualsNull always represents `x == null` (no isNot flag).
    // CFE expresses `x != null` as `Not(EqualsNull(x))`.
    // Pattern: LOAD_FALSE -> JUMP_IF_NNULL +1 -> LOAD_TRUE
    _emitter.emit(encodeABC(Op.loadFalse, resultReg, 0, 0));
    _emitter.emit(encodeAsBx(Op.jumpIfNnull, reg, 1));
    _emitter.emit(encodeABC(Op.loadTrue, resultReg, 0, 0));
    return (resultReg, ResultLoc.value);
  }

  // ── EqualsCall ──

  (int, ResultLoc) _compileEqualsCall(ir.EqualsCall expr) {
    final leftKind = _inferStackKind(expr.left);

    // User-defined operator==: dispatch via CALL_VIRTUAL.
    // Check if interfaceTarget is from a user-defined class (not Object/int/double/bool).
    if (leftKind == StackKind.ref) {
      final eqClass = expr.interfaceTarget.enclosingClass;
      if (eqClass != null && _classToClassId.containsKey(eqClass)) {
        return _compileUserEqualsCall(expr);
      }
    }

    var (lhsReg, lhsLoc) = _compileExpression(expr.left);
    var (rhsReg, rhsLoc) = _compileExpression(expr.right);
    final resultReg = _allocValueReg();

    final rightKind = _inferStackKind(expr.right);

    // Only use optimized EQ_INT/EQ_DBL when both operands are value-kind.
    // Mixed kinds (e.g. `true != SomeClass`) must use EQ_GENERIC on the ref
    // stack to avoid invalid UNBOX casts.
    switch ((leftKind, rightKind)) {
      case (StackKind.intVal || StackKind.boolVal, StackKind.intVal || StackKind.boolVal):
        // bool uses intView (0/1), so EQ_INT works for both int and bool.
        lhsReg = _ensureValue(lhsReg, lhsLoc, StackKind.intVal);
        rhsReg = _ensureValue(rhsReg, rhsLoc, StackKind.intVal);
        _emitter.emit(encodeABC(Op.eqInt, resultReg, lhsReg, rhsReg));
      case (StackKind.doubleVal, StackKind.doubleVal):
        lhsReg = _ensureValue(lhsReg, lhsLoc, StackKind.doubleVal);
        rhsReg = _ensureValue(rhsReg, rhsLoc, StackKind.doubleVal);
        _emitter.emit(encodeABC(Op.eqDbl, resultReg, lhsReg, rhsReg));
      case _:
        // Mixed or ref kinds — EQ_GENERIC on the ref stack.
        lhsReg = _boxToRefIfValue(lhsReg, lhsLoc, _inferExprType(expr.left));
        rhsReg = _boxToRefIfValue(rhsReg, rhsLoc, _inferExprType(expr.right));
        _emitter.emit(encodeABC(Op.eqGeneric, resultReg, lhsReg, rhsReg));
    }
    return (resultReg, ResultLoc.value);
  }

  /// Compiles a user-defined operator== via CALL_VIRTUAL.
  (int, ResultLoc) _compileUserEqualsCall(ir.EqualsCall expr) {
    // Compile receiver (left operand, ref stack).
    var (receiverReg, receiverLoc) = _compileExpression(expr.left);
    receiverReg = _boxToRefIfValue(receiverReg, receiverLoc, _inferExprType(expr.left));

    // Compile argument (right operand, ref stack — parameter type is Object).
    var (argReg, argLoc) = _compileExpression(expr.right);
    argReg = _boxToRefIfValue(argReg, argLoc, _inferExprType(expr.right));

    // Result is bool (value stack).
    final resultReg = _allocValueReg();

    // Emit arg move for right operand via shared helper.
    _emitArgMovesForVirtualCall([(argReg, ResultLoc.ref)]);

    // Emit CALL_VIRTUAL with method name '=='.
    _emitCallVirtual(resultReg, receiverReg, '==', 1);

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
          return (_emitUnbox(reg, kind), ResultLoc.value);
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

    // Release scope -- the result register is NOT scope-tracked (allocated
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
    // Check if this is an upvalue access (variable from outer function scope).
    if (_contextStack.isNotEmpty && _isUpvalueAccess(expr.variable)) {
      final uvIdx = _resolveUpvalue(expr.variable);
      final refReg = _allocRefReg();
      _emitter.emit(encodeABx(Op.loadUpvalue, refReg, uvIdx));

      // Unbox if the variable's declared type is a value type.
      // Upvalues always store boxed values on the ref stack, but downstream
      // code (e.g., ADD_INT) expects value-stack operands for int/double/bool.
      return _unboxCapturedIfNeeded(refReg, expr.variable.type);
    }

    // Check if this variable has been captured (promoted to ref stack)
    // in the current enclosing function. If so, we need to unbox for
    // value-type reads because the variable is now stored as a boxed ref.
    if (_capturedVarRefRegs.containsKey(expr.variable)) {
      final refReg = _capturedVarRefRegs[expr.variable]!;
      return _unboxCapturedIfNeeded(refReg, expr.variable.type);
    }

    final binding = _lookupVar(expr.variable);
    return (binding.reg, _locOf(binding));
  }

  /// For a value that was loaded from an upvalue (or a captured variable's
  /// ref register), unboxes it to the value stack if its declared type is
  /// a value type. Otherwise returns the ref register as-is.
  (int, ResultLoc) _unboxCapturedIfNeeded(int refReg, ir.DartType varType) {
    final kind = _classifyStackKind(varType);
    if (kind.isValue) {
      return (_emitUnbox(refReg, kind), ResultLoc.value);
    }
    return (refReg, ResultLoc.ref);
  }

  (int, ResultLoc) _compileVariableSet(ir.VariableSet expr) {
    // Check if this is an upvalue access (variable from outer function scope).
    if (_contextStack.isNotEmpty && _isUpvalueAccess(expr.variable)) {
      final uvIdx = _resolveUpvalue(expr.variable);
      var (srcReg, srcLoc) = _compileExpression(expr.value);
      // Ensure the value is on the ref stack (upvalues always use ref stack).
      srcReg = _boxToRefIfValue(srcReg, srcLoc, _inferExprType(expr.value));
      _emitter.emit(encodeABx(Op.storeUpvalue, srcReg, uvIdx));
      return (srcReg, ResultLoc.ref);
    }

    // Check if this variable has been captured (promoted to ref stack)
    // in the current enclosing function. If so, box and write to the
    // ref register.
    if (_capturedVarRefRegs.containsKey(expr.variable)) {
      final refReg = _capturedVarRefRegs[expr.variable]!;
      var (srcReg, srcLoc) = _compileExpression(expr.value);
      srcReg = _boxToRefIfValue(srcReg, srcLoc, _inferExprType(expr.value));
      _emitMove(refReg, srcReg, ResultLoc.ref);
      return (refReg, ResultLoc.ref);
    }

    final binding = _lookupVar(expr.variable);
    var (srcReg, srcLoc) = _compileExpression(expr.value);
    // Coerce stack kind if mismatch.
    (srcReg, _) = _coerceArg(srcReg, srcLoc, binding.kind, expr.value);
    final bindingLoc = _locOf(binding);
    _emitMove(binding.reg, srcReg, bindingLoc);
    return (binding.reg, bindingLoc);
  }

  /// Returns true if [varDecl] is not declared in the current function's
  /// local scopes but is available via an outer function's scope (i.e.,
  /// it needs upvalue access).
  bool _isUpvalueAccess(ir.VariableDeclaration varDecl) {
    final localBinding = _scope.lookup(varDecl);
    if (localBinding == null) return false;

    if (_contextStack.isNotEmpty) {
      final enclosingScope = _contextStack.last.scope;
      final enclosingBinding = enclosingScope.lookup(varDecl);
      if (enclosingBinding != null) {
        return !_isDeclaredInCurrentFunction(varDecl);
      }
    }
    return false;
  }

  /// Checks if [varDecl] is declared directly within the current function's
  /// scopes (not inherited from an outer function scope).
  bool _isDeclaredInCurrentFunction(ir.VariableDeclaration varDecl) {
    Scope? s = _scope;
    final outerScope =
        _contextStack.isNotEmpty ? _contextStack.last.scope : null;
    while (s != null && s != outerScope) {
      if (s.containsLocal(varDecl)) return true;
      s = s.parent;
    }
    return false;
  }

  // ── Await expression ──

  (int, ResultLoc) _compileAwaitExpression(ir.AwaitExpression expr) {
    // Compile the operand expression (the value being awaited).
    var (operandReg, operandLoc) = _compileExpression(expr.operand);

    // Ensure the operand is on the ref stack (AWAIT operates on ref stack).
    operandReg = _boxToRefIfValue(operandReg, operandLoc,
        _inferExprType(expr.operand));

    // The resume PC is the instruction AFTER the AWAIT instruction.
    // AWAIT A, Bx where Bx = currentPC + 1 (the next instruction).
    final awaitPC = _emitter.currentPC;
    final resumePC = awaitPC + 1;

    // Emit AWAIT A, Bx.
    _emitter.emit(encodeABx(Op.await_, operandReg, resumePC));

    // After resume, the result is in refStack[A] (same register).
    return (operandReg, ResultLoc.ref);
  }

  // ── Static field access ──

  (int, ResultLoc) _compileStaticGet(ir.StaticGet expr) {
    final target = expr.targetReference.asMember;

    // Platform library static field/getter → CALL_HOST.
    if (_isPlatformLibrary(target.enclosingLibrary)) {
      return _compileHostStaticGet(target);
    }

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
        return (_emitUnbox(refReg, kind), ResultLoc.value);
      }
      return (refReg, ResultLoc.ref);
    }

    // Static getter: compile as CALL_STATIC (no receiver).
    if (target is ir.Procedure && target.isGetter) {
      final funcId = _procToFuncId[target.reference];
      if (funcId == null) {
        throw UnsupportedError(
          'Unknown static getter: ${target.name.text}',
        );
      }

      final (resultReg, retLoc) =
          _allocResultReg(target.function.returnType);

      // No arguments — emit CALL_STATIC directly.
      _emitter.emit(encodeABx(Op.callStatic, resultReg, funcId));
      return (resultReg, retLoc);
    }

    throw UnsupportedError(
      'Unsupported StaticGet: ${target.name.text}',
    );
  }

  /// Compiles a platform library static field/getter as CALL_HOST.
  ///
  /// Static getters have no receiver, so argCount=0.
  /// Symbol format: `"dart:core::StackTrace::current#0"`.
  (int, ResultLoc) _compileHostStaticGet(ir.Member target) {
    final symbolName = _hostSymbolName(target);
    final bindingIndex = _allocBinding(symbolName, 0);
    return _emitCallHost(const [], bindingIndex);
  }

  /// Compiles a platform library static field/setter assignment as CALL_HOST.
  ///
  /// No receiver; args = [value]. The expression evaluates to the assigned
  /// value (Dart semantics). Symbol uses `"name=#1"` for setters.
  (int, ResultLoc) _compileHostStaticSet(ir.StaticSet expr, ir.Member target) {
    final (valReg, valLoc) = _compileExpression(expr.value);
    final valType = _inferExprType(expr.value);

    // Save the value before _emitCallHost may invalidate registers.
    final savedReg =
        valLoc == ResultLoc.ref ? _allocRefReg() : _allocValueReg();
    _emitMove(savedReg, valReg, valLoc);

    // Use original valReg (not savedReg) — _emitCallHost copies via MOVE,
    // it does not destroy the source register.
    final compiledArgs = <(int, ResultLoc, ir.DartType?)>[
      (valReg, valLoc, valType),
    ];

    final symbolName = _hostSymbolName(
      target,
      nameOverride: '${target.name.text}=',
      paramCountOverride: 1,
    );
    final bindingIndex = _allocBinding(symbolName, 1);
    _emitCallHost(compiledArgs, bindingIndex);

    return (savedReg, valLoc);
  }

  (int, ResultLoc) _compileStaticSet(ir.StaticSet expr) {
    final target = expr.targetReference.asMember;

    // Platform library static field/setter → CALL_HOST.
    if (_isPlatformLibrary(target.enclosingLibrary)) {
      return _compileHostStaticSet(expr, target);
    }

    if (target is ir.Field) {
      final globalIndex = _fieldToGlobalIndex[expr.targetReference];
      if (globalIndex == null) {
        throw UnsupportedError('Unknown static field: ${target.name.text}');
      }
      final (srcReg, srcLoc) = _compileExpression(expr.value);
      final refReg = _boxToRefIfValue(srcReg, srcLoc, target.type);
      _emitter.emit(encodeABx(Op.storeGlobal, refReg, globalIndex));
      return (srcReg, srcLoc); // Assignment evaluates to the assigned value
    }

    // Static setter: compile as CALL_STATIC with one argument (no receiver).
    if (target is ir.Procedure && target.isSetter) {
      final funcId = _procToFuncId[target.reference];
      if (funcId == null) {
        throw UnsupportedError(
          'Unknown static setter: ${target.name.text}',
        );
      }

      // Compile the value argument.
      var (valReg, valLoc) = _compileExpression(expr.value);

      // Save the original value (StaticSet evaluates to the assigned value).
      final savedValReg = valReg;
      final savedValLoc = valLoc;

      // Box if the setter parameter expects ref stack.
      final setterParam = target.function.positionalParameters.first;
      final paramKind = _classifyStackKind(setterParam.type);
      if (paramKind == StackKind.ref && valLoc == ResultLoc.value) {
        valReg = _emitBoxToRef(valReg, _inferExprType(expr.value));
        valLoc = ResultLoc.ref;
      }

      // Setter returns void → use a dummy result register.
      final dummyResult = _allocRefReg();

      // Emit arg MOVE for the single value parameter.
      final argTemps = <(int, ResultLoc)>[(valReg, valLoc)];
      _emitArgMovesAndCall(argTemps, Op.callStatic, dummyResult, funcId);

      return (savedValReg, savedValLoc);
    }

    throw UnsupportedError(
      'Unsupported StaticSet: ${target.name.text}',
    );
  }

  // ── Call expressions ──

  (int, ResultLoc) _compileStaticInvocation(ir.StaticInvocation expr) {
    final target = expr.target;

    // Platform library target → CALL_HOST (host function dispatch).
    if (_isPlatformLibrary(target.enclosingLibrary)) {
      return _compileHostStaticInvocation(expr);
    }

    final funcId = _procToFuncId[target.reference];
    if (funcId == null) {
      throw UnsupportedError(
        'Unknown static call target: ${target.name.text}',
      );
    }

    // Allocate result register FIRST -- it lives within the caller's frame.
    final (resultReg, retLoc) =
        _allocResultReg(target.function.returnType);

    // Compile arguments with coercion and defaults.
    final argTemps = _compileCallArgs(
      expr.arguments,
      target.function.positionalParameters,
      target.function.namedParameters,
    );

    // Emit FTA for generic function calls.
    _emitFTAForCall(expr.arguments.types);

    _emitArgMovesAndCall(argTemps, Op.callStatic, resultReg, funcId);
    return (resultReg, retLoc);
  }

  /// Compiles a [StaticInvocation] targeting a platform library function
  /// as a CALL_HOST instruction.
  (int, ResultLoc) _compileHostStaticInvocation(ir.StaticInvocation expr) {
    final target = expr.target;

    final compiledArgs = <(int, ResultLoc, ir.DartType?)>[];
    _compileHostPositionalAndNamed(expr.arguments, compiledArgs);

    final symbolName = _hostSymbolName(target);
    final bindingIndex = _allocBinding(symbolName, compiledArgs.length);
    return _emitCallHost(compiledArgs, bindingIndex);
  }

  /// Compiles the default value for a parameter declaration.
  ///
  /// If the parameter has an initializer expression, compiles it.
  /// Otherwise emits LOAD_NULL (the Dart language default for omitted params).
  (int, ResultLoc) _compileDefaultValue(ir.VariableDeclaration param) {
    final init = param.initializer;
    if (init != null) {
      return _compileExpression(init);
    }
    return _loadNull();
  }

  /// Compiles a [LocalFunctionInvocation] as a CALL on the closure.
  (int, ResultLoc) _compileLocalFunctionInvocation(
    ir.LocalFunctionInvocation expr,
  ) {
    final binding = _lookupVar(expr.variable);
    final varType = expr.variable.type;
    final funcType = varType is ir.FunctionType ? varType : null;
    final retType = funcType?.returnType ?? varType;

    return _compileClosureCall(
      closureReg: binding.reg,
      arguments: expr.arguments,
      funcType: funcType,
      returnType: retType,
    );
  }

  /// Compiles a [FunctionInvocation] -- calling a closure stored in a variable
  /// or returned from another expression.
  (int, ResultLoc) _compileFunctionInvocation(ir.FunctionInvocation expr) {
    final (closureReg, _) = _compileExpression(expr.receiver);

    return _compileClosureCall(
      closureReg: closureReg,
      arguments: expr.arguments,
      funcType: expr.functionType,
      returnType: expr.functionType?.returnType ?? const ir.DynamicType(),
    );
  }

  /// Shared helper for compiling closure calls (LocalFunctionInvocation and
  /// FunctionInvocation). Handles positional arg coercion, named arg matching,
  /// and CALL emission.
  (int, ResultLoc) _compileClosureCall({
    required int closureReg,
    required ir.Arguments arguments,
    required ir.FunctionType? funcType,
    required ir.DartType returnType,
  }) {
    final (resultReg, retLoc) = _allocResultReg(returnType);

    // Compile positional arguments with type coercion.
    final posParamTypes =
        funcType?.positionalParameters ?? const <ir.DartType>[];
    final argTemps = _compilePositionalArgsFromTypes(
        arguments.positional, posParamTypes);

    // Handle named arguments via the FunctionType.
    if (funcType != null && funcType.namedParameters.isNotEmpty) {
      _compileNamedArgsFromNamedTypes(
        funcType.namedParameters,
        arguments.named,
        argTemps,
      );
    }

    _emitArgMovesAndCall(argTemps, Op.call, resultReg, closureReg);
    return (resultReg, retLoc);
  }

  /// Compiles positional arguments with type coercion against a list of
  /// parameter types (from a FunctionType). Used by closure calls.
  List<(int, ResultLoc)> _compilePositionalArgsFromTypes(
    List<ir.Expression> args,
    List<ir.DartType> paramTypes,
  ) {
    final argTemps = <(int, ResultLoc)>[];
    for (var i = 0; i < args.length; i++) {
      var (argReg, argLoc) = _compileExpression(args[i]);
      if (i < paramTypes.length) {
        final paramKind = _classifyStackKind(paramTypes[i]);
        (argReg, argLoc) = _coerceArg(argReg, argLoc, paramKind, args[i]);
      }
      argTemps.add((argReg, argLoc));
    }
    return argTemps;
  }

  // ── Shared call helpers ──

  /// Compiles positional and named arguments for a call expression.
  ///
  /// Handles: positional args with coercion, default values for missing
  /// optionals, and named argument matching. Used by static invocation,
  /// virtual calls, super method invocation, and constructor invocation.
  List<(int, ResultLoc)> _compileCallArgs(
    ir.Arguments arguments,
    List<ir.VariableDeclaration> positionalParams,
    List<ir.VariableDeclaration> namedParams,
  ) {
    final argTemps = <(int, ResultLoc)>[];

    // 1. Compile provided positional arguments.
    for (var i = 0; i < arguments.positional.length; i++) {
      var (argReg, argLoc) = _compileExpression(arguments.positional[i]);
      if (i < positionalParams.length) {
        final paramKind = _classifyStackKind(positionalParams[i].type);
        (argReg, argLoc) = _coerceArg(
            argReg, argLoc, paramKind, arguments.positional[i]);
      }
      argTemps.add((argReg, argLoc));
    }

    // 2. Fill in missing optional positional arguments with default values.
    for (var i = arguments.positional.length;
        i < positionalParams.length;
        i++) {
      argTemps.add(_compileDefaultValue(positionalParams[i]));
    }

    // 3. Handle named arguments.
    if (namedParams.isNotEmpty) {
      _compileNamedArgsFromParams(namedParams, arguments.named, argTemps);
    }

    return argTemps;
  }

  /// Compiles named arguments from [ir.VariableDeclaration] parameters
  /// (used by [_compileStaticInvocation] where params come from the target
  /// procedure's FunctionNode).
  ///
  /// For each named param slot, either compiles the provided argument or
  /// the parameter's default value.
  void _compileNamedArgsFromParams(
    List<ir.VariableDeclaration> namedParams,
    List<ir.NamedExpression> namedArgs,
    List<(int, ResultLoc)> argTemps,
  ) {
    final providedNamed = <String, ir.NamedExpression>{};
    for (final namedArg in namedArgs) {
      providedNamed[namedArg.name] = namedArg;
    }

    for (final param in namedParams) {
      final provided = providedNamed[param.name!];
      if (provided != null) {
        var (argReg, argLoc) = _compileExpression(provided.value);
        final paramKind = _classifyStackKind(param.type);
        (argReg, argLoc) = _coerceArg(
            argReg, argLoc, paramKind, provided.value);
        argTemps.add((argReg, argLoc));
      } else {
        final (argReg, argLoc) = _compileDefaultValue(param);
        argTemps.add((argReg, argLoc));
      }
    }
  }

  /// Compiles named arguments from [ir.NamedType] parameters (used by
  /// [_compileLocalFunctionInvocation] and [_compileFunctionInvocation]
  /// where params come from an [ir.FunctionType]).
  ///
  /// For each named param slot, either compiles the provided argument or
  /// loads null (the callee handles actual default initialization).
  void _compileNamedArgsFromNamedTypes(
    List<ir.NamedType> namedParams,
    List<ir.NamedExpression> namedArgs,
    List<(int, ResultLoc)> argTemps,
  ) {
    final providedNamed = <String, ir.NamedExpression>{};
    for (final namedArg in namedArgs) {
      providedNamed[namedArg.name] = namedArg;
    }

    for (final param in namedParams) {
      final provided = providedNamed[param.name];
      if (provided != null) {
        var (argReg, argLoc) = _compileExpression(provided.value);
        final paramKind = _classifyStackKind(param.type);
        (argReg, argLoc) = _coerceArg(
            argReg, argLoc, paramKind, provided.value);
        argTemps.add((argReg, argLoc));
      } else {
        argTemps.add(_loadNull());
      }
    }
  }

  /// Emits placeholder MOVE instructions for arguments destined for a
  /// CALL_VIRTUAL call. The receiver is handled by the interpreter, so
  /// only non-receiver args are emitted here.
  ///
  /// This is the CALL_VIRTUAL counterpart to [_emitArgMovesAndCall] which
  /// handles CALL_STATIC/CALL_SUPER/CALL.
  void _emitArgMovesForVirtualCall(List<(int, ResultLoc)> argTemps) {
    var valArgIdx = 0;
    var refArgIdx = 3; // Skip ITA(0), FTA(1), this(2)
    for (final (srcReg, loc) in argTemps) {
      final movePC = _emitter.emitPlaceholder();
      final argIdx = loc == ResultLoc.value ? valArgIdx++ : refArgIdx++;
      _pendingArgMoves.add(
        (pc: movePC, srcReg: srcReg, argIdx: argIdx, loc: loc),
      );
    }
  }

  /// Allocates an IC entry and emits CALL_VIRTUAL.
  ///
  /// [resultReg] receives the call result. [receiverReg] holds the boxed
  /// receiver. [methodName] is the dispatch method name. [argCount] is the
  /// number of explicit arguments (not counting the receiver).
  void _emitCallVirtual(
      int resultReg, int receiverReg, String methodName, int argCount) {
    final methodNameIdx = _constantPool.addName(methodName);
    final icIndex = _icEntries.length;
    _icEntries.add(ICEntry(methodNameIndex: methodNameIdx, argCount: argCount));
    _emitter.emit(
        encodeABC(Op.callVirtual, resultReg, receiverReg, icIndex));
  }

  /// Compiles a single expression into a host-arg tuple list.
  /// Convenience wrapper for the receiver-only case.
  List<(int, ResultLoc, ir.DartType?)> _compileHostExprArgs(
    ir.Expression expr,
  ) {
    final (reg, loc) = _compileExpression(expr);
    return [(reg, loc, _inferExprType(expr))];
  }

  /// Compiles positional and named arguments from [arguments] into
  /// host-arg tuples and appends them to [out].
  void _compileHostPositionalAndNamed(
    ir.Arguments arguments,
    List<(int, ResultLoc, ir.DartType?)> out,
  ) {
    for (final arg in arguments.positional) {
      final (reg, loc) = _compileExpression(arg);
      out.add((reg, loc, _inferExprType(arg)));
    }
    for (final arg in arguments.named) {
      final (reg, loc) = _compileExpression(arg.value);
      out.add((reg, loc, _inferExprType(arg.value)));
    }
  }

  /// Emits a CALL_HOST instruction for a platform function call.
  ///
  /// Unlike CALL_STATIC (which pushes a CallStack frame), CALL_HOST reads
  /// args from the caller's own ref stack at positions A+1..A+argCount.
  /// All args must be on the ref stack (value-type args are boxed).
  ///
  /// [compiledArgs] contains (register, ResultLoc, DartType?) tuples for
  /// each argument (already compiled). The method handles boxing and
  /// consecutive register layout.
  ///
  /// Returns (resultReg, ResultLoc.ref) — CALL_HOST always returns on ref.
  (int, ResultLoc) _emitCallHost(
    List<(int reg, ResultLoc loc, ir.DartType? type)> compiledArgs,
    int bindingIndex,
  ) {
    // Phase 1: ensure all args are on the ref stack.
    final refArgRegs = <int>[
      for (final (srcReg, srcLoc, srcType) in compiledArgs)
        _boxToRefIfValue(srcReg, srcLoc, srcType),
    ];

    // Phase 2: allocate consecutive ref registers — result + arg slots.
    final resultReg = _allocRefReg();
    final targetArgRegs =
        List.generate(refArgRegs.length, (_) => _allocRefReg());

    // Phase 3: MOVE each arg into its consecutive target slot.
    for (var i = 0; i < refArgRegs.length; i++) {
      if (refArgRegs[i] != targetArgRegs[i]) {
        _emitter.emit(encodeABC(Op.moveRef, targetArgRegs[i], refArgRegs[i], 0));
      }
    }

    // Phase 4: emit CALL_HOST A=resultReg, Bx=bindingIndex.
    _emitter.emit(encodeABx(Op.callHost, resultReg, bindingIndex));
    return (resultReg, ResultLoc.ref);
  }

  /// Emits placeholder MOVE instructions for all compiled arguments and
  /// the final call instruction.
  ///
  /// Value and ref args maintain separate arg indices because they live on
  /// separate stacks. The callee sees value args as v0, v1, ... and ref
  /// args as r3, r4, ... (after ITA/FTA/this).
  ///
  /// For [Op.callStatic], [callOperandB] is the funcId.
  /// For [Op.call], [callOperandB] is the closure register.
  void _emitArgMovesAndCall(
    List<(int, ResultLoc)> argTemps,
    int callOp,
    int resultReg,
    int callOperandB,
  ) {
    var valArgIdx = 0;
    var refArgIdx = 3; // Skip ITA(0), FTA(1), this(2) — Ch2 convention
    for (final (srcReg, loc) in argTemps) {
      final movePC = _emitter.emitPlaceholder();
      final argIdx = loc == ResultLoc.value ? valArgIdx++ : refArgIdx++;
      _pendingArgMoves.add(
        (pc: movePC, srcReg: srcReg, argIdx: argIdx, loc: loc),
      );
    }

    if (callOp == Op.callStatic || callOp == Op.callSuper) {
      _emitter.emit(encodeABx(callOp, resultReg, callOperandB));
    } else {
      _emitter.emit(encodeABC(callOp, resultReg, callOperandB, 0));
    }
  }

  /// Compiles FTA (Function Type Arguments) for a generic invocation and
  /// emits a pending arg MOVE to place the FTA at callee's rsp+1.
  ///
  /// [typeArgs] are the Kernel type arguments from `arguments.types`.
  /// For each type arg, emits INSTANTIATE_TYPE, then CREATE_TYPE_ARGS to
  /// bundle them into a `List<DarticType>`, then a pending MOVE to rsp+1.
  void _emitFTAForCall(List<ir.DartType> typeArgs) {
    if (typeArgs.isEmpty) return;

    // Resolve each type argument to a DarticType ref register.
    final firstTypeReg = _allocRefReg();
    final template0 = dartTypeToTemplate(
      typeArgs[0],
      _typeClassIdLookup,
      enclosingClassTypeParams: _currentClassTypeParams,
      enclosingFunctionTypeParams: _currentFunctionTypeParams,
    );
    final templateIdx0 = _constantPool.addRef(template0);
    _emitter.emit(encodeABx(Op.instantiateType, firstTypeReg, templateIdx0));

    // Allocate consecutive ref registers for remaining type args.
    for (var i = 1; i < typeArgs.length; i++) {
      final typeReg = _allocRefReg();
      assert(typeReg == firstTypeReg + i);
      final template = dartTypeToTemplate(
        typeArgs[i],
        _typeClassIdLookup,
        enclosingClassTypeParams: _currentClassTypeParams,
        enclosingFunctionTypeParams: _currentFunctionTypeParams,
      );
      final templateIdx = _constantPool.addRef(template);
      _emitter.emit(encodeABx(Op.instantiateType, typeReg, templateIdx));
    }

    // CREATE_TYPE_ARGS: bundle resolved types into a List<DarticType>.
    final ftaReg = _allocRefReg();
    _emitter.emit(
        encodeABC(Op.createTypeArgs, typeArgs.length, firstTypeReg, ftaReg));

    // Emit pending MOVE to place FTA at callee's rsp+1 (FTA slot).
    final ftaMovePC = _emitter.emitPlaceholder();
    _pendingArgMoves.add(
      (pc: ftaMovePC, srcReg: ftaReg, argIdx: 1, loc: ResultLoc.ref),
    );
  }

  // ── Instance invocation (arithmetic specialization) ──

  (int, ResultLoc) _compileInstanceInvocation(ir.InstanceInvocation expr) {
    final targetClass = expr.interfaceTarget.enclosingClass;
    final name = expr.name.text;

    if (targetClass == _coreTypes.intClass ||
        targetClass == _coreTypes.numClass) {
      final receiverKind = _inferStackKind(expr.receiver);

      // Check if receiver is statically int.
      if (receiverKind == StackKind.intVal) {
        final intOp = _intBinaryOp(name);
        if (intOp != null) {
          final result = _emitBinaryOp(expr, intOp);
          if (result != null) return result;
        } else {
          // No int opcode — check double (catches `/`: no int version, has double).
          final dblOp = _doubleBinaryOp(name);
          if (dblOp != null) return _emitBinaryOp(expr, dblOp)!;
        }
        final unOp = _intUnaryOp(name);
        if (unOp != null) return _emitUnaryOp(expr, unOp);
      }

      // Check if receiver is statically double.
      if (receiverKind == StackKind.doubleVal) {
        final result = _tryCompileDoubleOp(expr, name);
        if (result != null) return result;
      }
    }

    // double-specific class target (e.g., double.operator/).
    if (targetClass == _coreTypes.doubleClass) {
      final result = _tryCompileDoubleOp(expr, name);
      if (result != null) return result;
    }

    // Platform method call → CALL_HOST (if specialization above didn't fire).
    if (targetClass != null &&
        _isPlatformLibrary(targetClass.enclosingLibrary)) {
      return _compileHostInstanceCall(expr);
    }

    // General case: virtual method dispatch via CALL_VIRTUAL + IC.
    return _compileVirtualCall(expr);
  }

  /// Compiles an [InstanceInvocation] targeting a platform class method
  /// as a CALL_HOST instruction.
  ///
  /// The receiver is the first arg (index 0), followed by explicit args.
  (int, ResultLoc) _compileHostInstanceCall(ir.InstanceInvocation expr) {
    final target = expr.interfaceTarget;

    // Compile receiver + arguments into host-arg tuples.
    final compiledArgs = _compileHostExprArgs(expr.receiver);
    _compileHostPositionalAndNamed(expr.arguments, compiledArgs);

    final symbolName = _hostSymbolName(target);
    final bindingIndex = _allocBinding(symbolName, compiledArgs.length);
    return _emitCallHost(compiledArgs, bindingIndex);
  }

  /// Compiles a virtual method call via CALL_VIRTUAL with inline cache.
  ///
  /// Handles: compile receiver → compile args → emit arg MOVEs →
  /// emit CALL_VIRTUAL A,B,C where A=result, B=receiver, C=IC index.
  /// The interpreter places the receiver at callee's rsp+2 automatically.
  (int, ResultLoc) _compileVirtualCall(ir.InstanceInvocation expr) {
    final target = expr.interfaceTarget;
    final methodName = expr.name.text;

    // 1. Compile receiver — box to ref stack if value-type.
    var (receiverReg, receiverLoc) = _compileExpression(expr.receiver);
    receiverReg = _boxToRefIfValue(
        receiverReg, receiverLoc, _inferExprType(expr.receiver));

    // 2. Allocate result register based on return type.
    final retType = target.function.returnType;
    final (resultReg, retLoc) = _allocResultReg(retType);

    // 3. Compile arguments.
    final argTemps = _compileCallArgs(
      expr.arguments,
      target.function.positionalParameters,
      target.function.namedParameters,
    );

    // 4. Emit FTA for generic method calls.
    _emitFTAForCall(expr.arguments.types);

    // 5. Emit pending arg MOVEs (skip receiver -- interpreter handles this).
    _emitArgMovesForVirtualCall(argTemps);

    // 6. Emit CALL_VIRTUAL.
    _emitCallVirtual(resultReg, receiverReg, methodName, argTemps.length);

    return (resultReg, retLoc);
  }

  /// Tries to compile a double operation (arithmetic, comparison, unary, toInt).
  /// Returns null if [name] is not a recognized double operation.
  (int, ResultLoc)? _tryCompileDoubleOp(
    ir.InstanceInvocation expr,
    String name,
  ) {
    final binOp = _doubleBinaryOp(name);
    if (binOp != null) {
      final result = _emitBinaryOp(expr, binOp);
      if (result != null) return result;
    }
    final unOp = _doubleUnaryOp(name);
    if (unOp != null) return _emitUnaryOp(expr, unOp);
    return null;
  }

  // ── Exception expressions: throw / rethrow ──

  (int, ResultLoc) _compileThrow(ir.Throw expr) {
    var (reg, loc) = _compileExpression(expr.expression);

    // Ensure it's on the ref stack -- exceptions are always objects.
    reg = _boxToRefIfValue(reg, loc, _inferExprType(expr.expression));

    _emitter.emit(encodeABC(Op.throw_, reg, 0, 0));

    // Throw has type Never -- return a dummy ref register.
    return (reg, ResultLoc.ref);
  }

  (int, ResultLoc) _compileRethrow(ir.Rethrow expr) {
    assert(_catchExceptionReg >= 0, 'Rethrow outside of catch clause');
    _emitter.emit(
        encodeABC(Op.rethrow_, _catchExceptionReg, _catchStackTraceReg, 0));

    // Rethrow has type Never -- return a dummy ref register.
    return (_catchExceptionReg, ResultLoc.ref);
  }

  // ── Type operations (is / as) ──

  (int, ResultLoc) _compileIsExpression(ir.IsExpression expr) {
    var (operandReg, operandLoc) = _compileExpression(expr.operand);

    // Box if on value stack -- INSTANCEOF needs the operand on the ref stack.
    operandReg = _boxToRefIfValue(
        operandReg, operandLoc, _inferExprType(expr.operand));

    // Emit INSTANTIATE_TYPE for the target type → ref register.
    final typeReg = _emitInstantiateType(expr.type);

    final resultReg = _allocValueReg();
    _emitter.emit(encodeABC(Op.instanceOf, resultReg, operandReg, typeReg));

    return (resultReg, ResultLoc.value);
  }

  (int, ResultLoc) _compileAsExpression(ir.AsExpression expr) {
    // ── Case 1: isUnchecked — CFE type-promotion / extension-type access ──
    //
    // CFE inserts AsExpression(isUnchecked=true) when it statically knows the
    // cast is safe (e.g., extension type representation access, or a promotion
    // the CFE has already verified). No runtime check is needed — just compile
    // the operand. If the target type is a value type (int, double, bool) and
    // the operand is on the ref stack, emit an UNBOX to move it to the value
    // stack.
    if (expr.isUnchecked) {
      var (operandReg, operandLoc) = _compileExpression(expr.operand);
      final targetKind = _classifyStackKind(expr.type);

      if (targetKind.isValue && operandLoc == ResultLoc.ref) {
        return (_emitUnbox(operandReg, targetKind), ResultLoc.value);
      }

      // Otherwise pass through as-is (no CAST needed).
      return (operandReg, operandLoc);
    }

    // ── Cases 2 & 3: isTypeError or explicit `as` — emit runtime CAST ──
    //
    // Both isTypeError (implicit downcast for assignment compatibility) and
    // explicit `as` expressions need a runtime type check via CAST.
    var (operandReg, operandLoc) = _compileExpression(expr.operand);

    // Box if on value stack -- CAST needs the operand on the ref stack.
    operandReg = _boxToRefIfValue(
        operandReg, operandLoc, _inferExprType(expr.operand));

    // Emit INSTANTIATE_TYPE for the target type → ref register.
    final typeReg = _emitInstantiateType(expr.type);

    final resultReg = _allocRefReg();
    _emitter.emit(encodeABC(Op.cast, resultReg, operandReg, typeReg));

    return (resultReg, ResultLoc.ref);
  }

  /// Emits INSTANTIATE_TYPE for a Kernel DartType, returning the ref register
  /// holding the resolved DarticType at runtime.
  ///
  /// Uses [_currentClassTypeParams] so that TypeParameterType references (like
  /// `T` in `x is T`) correctly resolve to TypeParameterTemplate indices.
  int _emitInstantiateType(ir.DartType type) {
    final template = dartTypeToTemplate(
      type,
      _typeClassIdLookup,
      enclosingClassTypeParams: _currentClassTypeParams,
      enclosingFunctionTypeParams: _currentFunctionTypeParams,
    );
    final templateIdx = _constantPool.addRef(template);
    final typeReg = _allocRefReg();
    _emitter.emit(encodeABx(Op.instantiateType, typeReg, templateIdx));
    return typeReg;
  }

  // ── ConstructorInvocation ──

  /// Compiles a platform class constructor invocation as CALL_HOST.
  ///
  /// The host function wrapper handles object allocation internally.
  /// Returns the result from CALL_HOST (the constructed object on ref stack).
  (int, ResultLoc) _compileHostConstructorInvocation(
    ir.ConstructorInvocation expr,
  ) {
    final compiledArgs = <(int, ResultLoc, ir.DartType?)>[];
    _compileHostPositionalAndNamed(expr.arguments, compiledArgs);

    final symbolName = _hostSymbolName(expr.target);
    final bindingIndex = _allocBinding(symbolName, compiledArgs.length);
    return _emitCallHost(compiledArgs, bindingIndex);
  }

  /// Compiles a [ConstructorInvocation]: NEW_INSTANCE (or ALLOC_GENERIC for
  /// generic classes) → args → CALL_STATIC.
  ///
  /// The expression result is the newly allocated object (ref stack), NOT
  /// the constructor's void return value.
  (int, ResultLoc) _compileConstructorInvocation(
    ir.ConstructorInvocation expr,
  ) {
    final target = expr.target;
    final cls = target.enclosingClass;

    // Platform class constructor → CALL_HOST.
    if (_isPlatformLibrary(cls.enclosingLibrary)) {
      return _compileHostConstructorInvocation(expr);
    }

    final funcId = _constructorToFuncId[target.reference];
    if (funcId == null) {
      throw UnsupportedError(
        'Unknown constructor: ${cls.name}.${target.name.text}',
      );
    }
    final classId = _classToClassId[cls];
    if (classId == null) {
      throw StateError('Class not registered: ${cls.name}');
    }

    // 1. Allocate object register. Use ALLOC_GENERIC for generic classes
    //    (type parameters present), or NEW_INSTANCE for non-generic classes.
    final objReg = _allocRefReg();
    final isGeneric = cls.typeParameters.isNotEmpty;

    if (isGeneric) {
      // Build the full InterfaceType template from classId + type arguments.
      // Arguments.types contains the class type arguments (e.g., [int] for
      // Box<int>). For non-generic invocations of generic classes (e.g.,
      // IntBox's super(v) call to Box<int>), the type args come from the
      // Kernel supertype.
      final typeArgs = expr.arguments.types;
      final typeTemplate = InterfaceTypeTemplate(
        classId: classId,
        typeArgs: [
          for (final arg in typeArgs)
            dartTypeToTemplate(
              arg,
              _typeClassIdLookup,
              enclosingClassTypeParams: _currentClassTypeParams,
              enclosingFunctionTypeParams: _currentFunctionTypeParams,
            ),
        ],
      );
      final templateIdx = _constantPool.addRef(typeTemplate);
      final typeReg = _allocRefReg();
      _emitter.emit(encodeABx(Op.instantiateType, typeReg, templateIdx));
      _emitter.emit(encodeABC(Op.allocGeneric, objReg, typeReg, 0));
    } else {
      _emitter.emit(encodeABx(Op.newInstance, objReg, classId));
    }

    // 2. Compile arguments.
    final argTemps = _compileCallArgs(
      expr.arguments,
      target.function.positionalParameters,
      target.function.namedParameters,
    );

    // 3. Emit pending MOVE for `this` at ref argIdx 2.
    final thisMovePC = _emitter.emitPlaceholder();
    _pendingArgMoves.add(
      (pc: thisMovePC, srcReg: objReg, argIdx: 2, loc: ResultLoc.ref),
    );

    // 4. Emit arg moves + CALL_STATIC. Constructor returns void, so use a
    //    dummy ref register for the unused result.
    final dummyResult = _allocRefReg();
    _emitArgMovesAndCall(argTemps, Op.callStatic, dummyResult, funcId);

    // 5. The expression result is the object, not the call result.
    return (objReg, ResultLoc.ref);
  }

  // ── ThisExpression ──

  /// Compiles [ThisExpression]: returns ref register at rsp+2.
  (int, ResultLoc) _compileThisExpression() {
    // `this` is always at ref register 2 (rsp+2) per Ch2 convention.
    return (2, ResultLoc.ref);
  }

  // ── InstanceGet / InstanceSet (field access) ──

  /// Compiles [InstanceGet]: dispatches to field access or getter call.
  (int, ResultLoc) _compileInstanceGet(ir.InstanceGet expr) {
    final target = expr.interfaceTarget;
    final targetClass = target.enclosingClass;

    // Check if the target is a field.
    if (target is ir.Field) {
      final layouts = _instanceFieldLayouts[targetClass];
      if (layouts != null) {
        final layout = layouts[target.getterReference];
        if (layout != null) {
          // Compile receiver.
          // SAFETY: loc discarded — field access targets object instances
          // which are always on the ref stack.
          final (recvReg, _) = _compileExpression(expr.receiver);
          return _emitGetField(recvReg, layout);
        }
      }
    }

    // Platform class property → CALL_HOST.
    if (targetClass != null &&
        _isPlatformLibrary(targetClass.enclosingLibrary)) {
      return _compileHostGetterCall(expr);
    }

    // Check if the target is a getter Procedure → emit CALL_VIRTUAL.
    if (target is ir.Procedure && target.isGetter) {
      return _compileInstanceGetterCall(expr, target);
    }

    throw UnsupportedError(
      'Unsupported InstanceGet: ${expr.name.text} on ${targetClass?.name}',
    );
  }

  /// Compiles a platform class getter/property access as CALL_HOST.
  ///
  /// The receiver is the only arg. E.g., `"hello".length` becomes
  /// `CALL_HOST` with symbol `"dart:core::String::length#0"`, argCount=1.
  (int, ResultLoc) _compileHostGetterCall(ir.InstanceGet expr) {
    final compiledArgs = _compileHostExprArgs(expr.receiver);

    final symbolName = _hostSymbolName(expr.interfaceTarget);
    final bindingIndex = _allocBinding(symbolName, 1);
    return _emitCallHost(compiledArgs, bindingIndex);
  }

  /// Compiles an instance getter call via CALL_VIRTUAL.
  ///
  /// A getter has no arguments (only the receiver). The interpreter places
  /// the receiver at callee's rsp+2 automatically.
  (int, ResultLoc) _compileInstanceGetterCall(
    ir.InstanceGet expr,
    ir.Procedure getter,
  ) {
    // 1. Compile receiver — box to ref stack if value-type.
    var (receiverReg, receiverLoc) = _compileExpression(expr.receiver);
    receiverReg = _boxToRefIfValue(
        receiverReg, receiverLoc, _inferExprType(expr.receiver));

    // 2. Allocate result register based on the getter's return type.
    final (resultReg, retLoc) = _allocResultReg(getter.function.returnType);

    // 3. No arguments for a getter — skip arg moves.

    // 4. Emit CALL_VIRTUAL.
    _emitCallVirtual(resultReg, receiverReg, expr.name.text, 0);

    return (resultReg, retLoc);
  }

  /// Compiles [InstanceSet]: dispatches to field write or setter call.
  (int, ResultLoc) _compileInstanceSet(ir.InstanceSet expr) {
    final target = expr.interfaceTarget;
    final targetClass = target.enclosingClass;

    if (target is ir.Field) {
      final layouts = _instanceFieldLayouts[targetClass];
      if (layouts != null) {
        final layout = layouts[target.getterReference];
        if (layout != null) {
          // Compile receiver and value.
          // SAFETY: loc discarded — field access targets object instances
          // which are always on the ref stack.
          final (recvReg, _) = _compileExpression(expr.receiver);
          var (valReg, valLoc) = _compileExpression(expr.value);
          valReg = _emitSetField(
              recvReg, valReg, valLoc, layout, _inferExprType(expr.value));
          // InstanceSet result is the written value.
          return (valReg, valLoc);
        }
      }
    }

    // Platform class property set → CALL_HOST.
    if (targetClass != null &&
        _isPlatformLibrary(targetClass.enclosingLibrary)) {
      return _compileHostSetterCall(expr);
    }

    // Check if the target is a setter Procedure → emit CALL_VIRTUAL.
    if (target is ir.Procedure && target.isSetter) {
      return _compileInstanceSetterCall(expr, target);
    }

    throw UnsupportedError(
      'Unsupported InstanceSet: ${expr.name.text} on ${targetClass?.name}',
    );
  }

  /// Compiles a platform class property set as CALL_HOST.
  ///
  /// Args: receiver + value. The expression evaluates to the written value.
  (int, ResultLoc) _compileHostSetterCall(ir.InstanceSet expr) {
    final target = expr.interfaceTarget;

    // Compile receiver.
    final (recvReg, recvLoc) = _compileExpression(expr.receiver);
    final recvType = _inferExprType(expr.receiver);

    // Compile value.
    final (valReg, valLoc) = _compileExpression(expr.value);
    final valType = _inferExprType(expr.value);

    // Save value into a dedicated register *before* _emitCallHost, which may
    // MOVE registers and invalidate the original location.
    final savedReg = valLoc == ResultLoc.ref ? _allocRefReg() : _allocValueReg();
    _emitMove(savedReg, valReg, valLoc);

    final compiledArgs = <(int, ResultLoc, ir.DartType?)>[
      (recvReg, recvLoc, recvType),
      (valReg, valLoc, valType),
    ];

    // Setter symbol: "propertyName=" with 1 explicit param (the value).
    final symbolName = _hostSymbolName(
      target,
      nameOverride: '${expr.name.text}=',
      paramCountOverride: 1,
    );
    final bindingIndex = _allocBinding(symbolName, 2);

    _emitCallHost(compiledArgs, bindingIndex);

    // InstanceSet evaluates to the assigned value.
    return (savedReg, valLoc);
  }

  /// Compiles an instance setter call via CALL_VIRTUAL.
  ///
  /// A setter has one parameter (the value) plus the receiver. The interpreter
  /// places the receiver at callee's rsp+2 automatically.
  /// InstanceSet evaluates to the assigned value (Dart semantics).
  (int, ResultLoc) _compileInstanceSetterCall(
    ir.InstanceSet expr,
    ir.Procedure setter,
  ) {
    // 1. Compile receiver — box to ref stack if value-type.
    var (receiverReg, receiverLoc) = _compileExpression(expr.receiver);
    receiverReg = _boxToRefIfValue(
        receiverReg, receiverLoc, _inferExprType(expr.receiver));

    // 2. Compile the value argument.
    var (valReg, valLoc) = _compileExpression(expr.value);

    // Save the value before arg moves (InstanceSet evaluates to the value).
    final savedValReg = valReg;
    final savedValLoc = valLoc;

    // 3. The setter's parameter determines where the arg goes.
    final setterParam = setter.function.positionalParameters.first;
    final paramKind = _classifyStackKind(setterParam.type);
    if (paramKind == StackKind.ref && valLoc == ResultLoc.value) {
      valReg = _emitBoxToRef(valReg, _inferExprType(expr.value));
      valLoc = ResultLoc.ref;
    }

    // 4. Emit arg MOVE + CALL_VIRTUAL via shared helper.
    final argTemps = <(int, ResultLoc)>[(valReg, valLoc)];
    _emitArgMovesForVirtualCall(argTemps);

    final dummyResult = _allocRefReg();
    _emitCallVirtual(dummyResult, receiverReg, '${expr.name.text}=', 1);

    // InstanceSet evaluates to the assigned value.
    return (savedValReg, savedValLoc);
  }

  // ── Dynamic dispatch (DynamicGet / DynamicSet / DynamicInvocation) ──

  /// Compiles [DynamicGet]: emits GET_FIELD_DYN for dynamic receiver property
  /// access (e.g., `dynamic x = 'hello'; x.length`).
  (int, ResultLoc) _compileDynamicGet(ir.DynamicGet expr) {
    // 1. Compile receiver to ref stack.
    var (recvReg, recvLoc) = _compileExpression(expr.receiver);
    recvReg = _boxToRefIfValue(recvReg, recvLoc, _inferExprType(expr.receiver));

    // 2. Allocate result (always ref for dynamic dispatch).
    final resultReg = _allocRefReg();

    // 3. Add property name to names partition and emit GET_FIELD_DYN.
    final nameIdx = _constantPool.addName(expr.name.text);
    _emitter.emit(encodeABC(Op.getFieldDyn, resultReg, recvReg, nameIdx));

    return (resultReg, ResultLoc.ref);
  }

  /// Compiles [DynamicSet]: emits SET_FIELD_DYN for dynamic receiver property
  /// set (e.g., `dynamic x = obj; x.field = 42`).
  (int, ResultLoc) _compileDynamicSet(ir.DynamicSet expr) {
    // 1. Compile receiver to ref stack.
    var (recvReg, recvLoc) = _compileExpression(expr.receiver);
    recvReg = _boxToRefIfValue(recvReg, recvLoc, _inferExprType(expr.receiver));

    // 2. Compile value to ref stack.
    var (valReg, valLoc) = _compileExpression(expr.value);
    valReg = _boxToRefIfValue(valReg, valLoc, _inferExprType(expr.value));

    // 3. Add property name to names partition and emit SET_FIELD_DYN.
    final nameIdx = _constantPool.addName(expr.name.text);
    _emitter.emit(encodeABC(Op.setFieldDyn, recvReg, valReg, nameIdx));

    // DynamicSet evaluates to the assigned value.
    return (valReg, ResultLoc.ref);
  }

  /// Compiles [DynamicInvocation]: emits INVOKE_DYN for dynamic receiver
  /// method calls (e.g., `dynamic x = [1,2]; x.contains(1)`).
  ///
  /// Layout: result at reg A, receiver at A+1, args at A+2...
  /// INVOKE_DYN A, B, C where B=totalArgCount (receiver+args), C=nameIdx.
  (int, ResultLoc) _compileDynamicInvocation(ir.DynamicInvocation expr) {
    // 1. Compile receiver to ref (box if needed).
    var (recvReg, recvLoc) = _compileExpression(expr.receiver);
    recvReg = _boxToRefIfValue(recvReg, recvLoc, _inferExprType(expr.receiver));

    // 2. Compile all positional args to ref (box if needed).
    final argRegs = <int>[];
    for (final arg in expr.arguments.positional) {
      var (argReg, argLoc) = _compileExpression(arg);
      argReg = _boxToRefIfValue(argReg, argLoc, _inferExprType(arg));
      argRegs.add(argReg);
    }

    // 3. Allocate consecutive ref registers: result, receiver, args.
    final resultReg = _allocRefReg();
    final recvSlot = _allocRefReg();
    final argSlots = List.generate(argRegs.length, (_) => _allocRefReg());

    // 4. MOVE receiver and args into consecutive slots.
    if (recvReg != recvSlot) {
      _emitter.emit(encodeABC(Op.moveRef, recvSlot, recvReg, 0));
    }
    for (var i = 0; i < argRegs.length; i++) {
      if (argRegs[i] != argSlots[i]) {
        _emitter.emit(encodeABC(Op.moveRef, argSlots[i], argRegs[i], 0));
      }
    }

    // 5. Emit INVOKE_DYN A=result, B=totalArgCount, C=nameIdx.
    final nameIdx = _constantPool.addName(expr.name.text);
    final totalArgCount = 1 + argRegs.length; // receiver + explicit args
    _emitter.emit(encodeABC(Op.invokeDyn, resultReg, totalArgCount, nameIdx));

    return (resultReg, ResultLoc.ref);
  }

  // ── Super access expressions ──

  /// Compiles [SuperMethodInvocation] via CALL_SUPER.
  ///
  /// The target method is resolved at compile time via Kernel's
  /// `interfaceTarget`. CALL_SUPER ABx: A=result, Bx=funcId.
  /// The receiver (this) is passed at rsp+2 of the callee frame.
  (int, ResultLoc) _compileSuperMethodInvocation(
    ir.SuperMethodInvocation expr,
  ) {
    final target = expr.interfaceTarget;

    final funcId = _procToFuncId[target.reference];
    if (funcId == null) {
      throw UnsupportedError(
        'Unknown super method target: ${target.name.text}',
      );
    }

    // Allocate result register based on return type.
    final (resultReg, retLoc) = _allocResultReg(target.function.returnType);

    // Compile arguments.
    final argTemps = _compileCallArgs(
      expr.arguments,
      target.function.positionalParameters,
      target.function.namedParameters,
    );

    _emitThisPassthrough();
    _emitArgMovesAndCall(argTemps, Op.callSuper, resultReg, funcId);

    return (resultReg, retLoc);
  }

  /// Compiles [SuperPropertyGet] via CALL_SUPER for getters, or direct
  /// field access for fields.
  (int, ResultLoc) _compileSuperPropertyGet(ir.SuperPropertyGet expr) {
    final target = expr.interfaceTarget;

    // If the target is a field, use GET_FIELD_REF/GET_FIELD_VAL on `this`.
    if (target is ir.Field) {
      final cls = target.enclosingClass!;
      final layouts = _instanceFieldLayouts[cls];
      if (layouts != null) {
        final layout = layouts[target.getterReference];
        if (layout != null) {
          const thisReg = 2; // rsp+2
          return _emitGetField(thisReg, layout);
        }
      }
    }

    // Getter Procedure → CALL_SUPER.
    if (target is ir.Procedure && target.isGetter) {
      final funcId = _procToFuncId[target.reference];
      if (funcId == null) {
        throw UnsupportedError(
          'Unknown super getter target: ${target.name.text}',
        );
      }

      final (resultReg, retLoc) =
          _allocResultReg(target.function.returnType);

      _emitThisPassthrough();
      _emitArgMovesAndCall(
          <(int, ResultLoc)>[], Op.callSuper, resultReg, funcId);

      return (resultReg, retLoc);
    }

    throw UnsupportedError(
      'Unsupported SuperPropertyGet target: ${target.runtimeType}',
    );
  }

  /// Compiles [SuperPropertySet] via CALL_SUPER for setters, or direct
  /// field write for fields.
  (int, ResultLoc) _compileSuperPropertySet(ir.SuperPropertySet expr) {
    final target = expr.interfaceTarget;

    // If the target is a field, use SET_FIELD_REF/SET_FIELD_VAL on `this`.
    if (target is ir.Field) {
      final cls = target.enclosingClass!;
      final layouts = _instanceFieldLayouts[cls];
      if (layouts != null) {
        final layout = layouts[target.getterReference];
        if (layout != null) {
          var (valReg, valLoc) = _compileExpression(expr.value);
          const thisReg = 2;
          valReg = _emitSetField(
              thisReg, valReg, valLoc, layout, _inferExprType(expr.value));
          return (valReg, valLoc);
        }
      }
    }

    // Setter Procedure → CALL_SUPER.
    if (target is ir.Procedure && target.isSetter) {
      final funcId = _procToFuncId[target.reference];
      if (funcId == null) {
        throw UnsupportedError(
          'Unknown super setter target: ${target.name.text}',
        );
      }

      var (valReg, valLoc) = _compileExpression(expr.value);
      final savedValReg = valReg;
      final savedValLoc = valLoc;

      final setterParam = target.function.positionalParameters.first;
      final paramKind = _classifyStackKind(setterParam.type);
      if (paramKind == StackKind.ref && valLoc == ResultLoc.value) {
        valReg = _emitBoxToRef(valReg, _inferExprType(expr.value));
        valLoc = ResultLoc.ref;
      }

      final dummyResult = _allocRefReg();
      final argTemps = <(int, ResultLoc)>[(valReg, valLoc)];

      _emitThisPassthrough();
      _emitArgMovesAndCall(argTemps, Op.callSuper, dummyResult, funcId);

      return (savedValReg, savedValLoc);
    }

    throw UnsupportedError(
      'Unsupported SuperPropertySet target: ${target.runtimeType}',
    );
  }

  // ── InstanceConstant (const MyClass(...)) ──

  /// Compiles an [ir.InstanceConstant] by emitting inline object construction:
  /// allocate → set each field with compiled constant values.
  (int, ResultLoc) _compileInstanceConstant(ir.InstanceConstant constant) {
    final cls = constant.classNode;
    final classId = _classToClassId[cls];
    if (classId == null) {
      if (_isPlatformLibrary(cls.enclosingLibrary)) {
        return _compilePlatformInstanceConstant(constant);
      }
      throw UnsupportedError(
        'InstanceConstant: unknown class ${cls.name}',
      );
    }

    // 1. Allocate the object (generic or non-generic).
    final objReg = _allocRefReg();
    final isGeneric = constant.typeArguments.isNotEmpty;

    if (isGeneric) {
      final typeTemplate = InterfaceTypeTemplate(
        classId: classId,
        typeArgs: [
          for (final arg in constant.typeArguments)
            dartTypeToTemplate(
              arg,
              _typeClassIdLookup,
              enclosingClassTypeParams: _currentClassTypeParams,
              enclosingFunctionTypeParams: _currentFunctionTypeParams,
            ),
        ],
      );
      final templateIdx = _constantPool.addRef(typeTemplate);
      final typeReg = _allocRefReg();
      _emitter.emit(encodeABx(Op.instantiateType, typeReg, templateIdx));
      _emitter.emit(encodeABC(Op.allocGeneric, objReg, typeReg, 0));
    } else {
      _emitter.emit(encodeABx(Op.newInstance, objReg, classId));
    }

    // 2. Set each field from the constant's fieldValues map.
    final layouts = _instanceFieldLayouts[cls];

    for (final entry in constant.fieldValues.entries) {
      final field = entry.key.asField;
      final value = entry.value;

      // Look up field layout (offset + kind).
      final layout = layouts?[field.getterReference];
      if (layout == null) {
        throw UnsupportedError(
          'InstanceConstant: field layout not found for '
          '${cls.name}.${field.name.text}',
        );
      }

      // Compile the constant field value.
      var (valReg, valLoc) = value.accept(_constantVisitor);

      _emitSetField(objReg, valReg, valLoc, layout, field.type);
    }

    return (objReg, ResultLoc.ref);
  }

  /// Compiles an [ir.InstanceConstant] for a **platform class** (e.g.,
  /// `Duration`) by emitting a CALL_HOST to a synthetic `_#fromFields`
  /// binding.
  ///
  /// Platform classes are not registered in [_classToClassId] (only
  /// user-defined classes are), so we cannot allocate + set fields via
  /// bytecode. Instead, we compile the field values and pass them to a
  /// host binding that reconstructs the object from raw field data.
  ///
  /// Symbol format: `{libUri}::{className}::_#fromFields#{fieldCount}`
  (int, ResultLoc) _compilePlatformInstanceConstant(
    ir.InstanceConstant constant,
  ) {
    final cls = constant.classNode;
    final libUri = cls.enclosingLibrary.importUri.toString();
    final className = cls.name;

    // Sort field entries by field name for deterministic ordering.
    final sortedEntries = constant.fieldValues.entries.toList()
      ..sort((a, b) =>
          a.key.asField.name.text.compareTo(b.key.asField.name.text));

    // Compile each field value and collect as CALL_HOST arg tuples.
    final compiledArgs = <(int, ResultLoc, ir.DartType?)>[];
    for (final entry in sortedEntries) {
      final value = entry.value;
      final (reg, loc) = value.accept(_constantVisitor);
      compiledArgs.add((reg, loc, _inferConstantType(value)));
    }

    final symbolName =
        '$libUri::$className::_#fromFields#${compiledArgs.length}';
    final bindingIndex = _allocBinding(symbolName, compiledArgs.length);
    return _emitCallHost(compiledArgs, bindingIndex);
  }

  // ── TypeLiteral (Type as value, e.g., `int` used as expression) ──

  /// Compiles a [ir.TypeLiteral]: reifies a Dart type into a runtime
  /// [DarticType] object via INSTANTIATE_TYPE.
  (int, ResultLoc) _compileTypeLiteral(ir.TypeLiteral expr) {
    return _emitTypeReification(expr.type);
  }

  /// Compiles a [ir.TypeLiteralConstant]: same as TypeLiteral but from
  /// a constant context.
  (int, ResultLoc) _compileTypeLiteralConstant(
      ir.TypeLiteralConstant constant) {
    return _emitTypeReification(constant.type);
  }

  /// Shared helper: convert a DartType to a runtime DarticType via
  /// TypeTemplate → INSTANTIATE_TYPE.
  (int, ResultLoc) _emitTypeReification(ir.DartType type) {
    final template = dartTypeToTemplate(
      type,
      _typeClassIdLookup,
      enclosingClassTypeParams: _currentClassTypeParams,
      enclosingFunctionTypeParams: _currentFunctionTypeParams,
    );
    final templateIdx = _constantPool.addRef(template);
    final typeReg = _allocRefReg();
    _emitter.emit(encodeABx(Op.instantiateType, typeReg, templateIdx));
    return (typeReg, ResultLoc.ref);
  }

  // ── Instantiation (generic function instantiation, e.g., `foo<int>`) ──

  /// Compiles an [ir.Instantiation]: a generic function tear-off with bound
  /// type arguments (e.g., `identity<int>`).
  ///
  /// When the instantiation causes a value/ref stack mismatch between the
  /// generic function's parameter types (`T` → ref) and the instantiated
  /// type (`int` → value), generates a bridge thunk that coerces arguments
  /// and return values between the two calling conventions.
  (int, ResultLoc) _compileInstantiation(ir.Instantiation expr) {
    // For StaticTearOff targets, we know the function at compile time and
    // can generate an optimized CALL_STATIC thunk.
    if (expr.expression is ir.StaticTearOff) {
      return _compileStaticInstantiation(
        expr.expression as ir.StaticTearOff,
        expr.typeArguments,
      );
    }
    // Fallback for non-StaticTearOff targets: pass through.
    return _compileExpression(expr.expression);
  }

  /// Compiles `Instantiation(StaticTearOff(f), typeArgs)`.
  ///
  /// If the instantiation causes a stack-kind mismatch (e.g., generic `T` is
  /// ref but instantiated `int` is value), generates a bridge thunk.
  /// Otherwise returns a plain tear-off closure.
  (int, ResultLoc) _compileStaticInstantiation(
    ir.StaticTearOff tearOff,
    List<ir.DartType> typeArgs,
  ) {
    final target = tearOff.target;
    final funcId = _procToFuncId[target.reference];
    if (funcId == null) {
      throw UnsupportedError(
        'Instantiation: unknown function ${target.name.text}',
      );
    }

    final fn = target.function;
    final typeParams = fn.typeParameters;
    if (typeParams.isEmpty || typeArgs.isEmpty) {
      return _compileStaticTearOff(tearOff);
    }

    // Build a substitution to compute instantiated types.
    final subst = type_algebra.Substitution.fromPairs(typeParams, typeArgs);

    if (!_needsInstantiationThunk(fn, subst)) {
      return _compileStaticTearOff(tearOff);
    }

    return _generateInstantiationThunk(funcId, fn, subst, typeArgs);
  }

  /// Returns true if instantiating [fn] with [subst] causes a value/ref
  /// stack-kind mismatch for any parameter or the return type.
  bool _needsInstantiationThunk(
      ir.FunctionNode fn, type_algebra.Substitution subst) {
    for (final param in fn.positionalParameters) {
      if (_classifyStackKind(param.type) !=
          _classifyStackKind(subst.substituteType(param.type))) {
        return true;
      }
    }
    for (final param in fn.namedParameters) {
      if (_classifyStackKind(param.type) !=
          _classifyStackKind(subst.substituteType(param.type))) {
        return true;
      }
    }
    return _classifyStackKind(fn.returnType) !=
        _classifyStackKind(subst.substituteType(fn.returnType));
  }

  /// Generates a bridge thunk for a generic function instantiation that has
  /// value/ref stack mismatches.
  ///
  /// The thunk accepts parameters per the **instantiated** types (matching
  /// the caller's calling convention), coerces them to the **actual** types
  /// (matching the generic function's convention), calls the inner function
  /// via CALL_STATIC, and coerces the return value back.
  (int, ResultLoc) _generateInstantiationThunk(
    int innerFuncId,
    ir.FunctionNode fn,
    type_algebra.Substitution subst,
    List<ir.DartType> typeArgs,
  ) {
    // Reserve a slot in the function table.
    final thunkFuncId = _functions.length;
    _functions.add(DarticFuncProto(
      funcId: thunkFuncId,
      bytecode: DarticCompiler._haltBytecode,
      valueRegCount: 0,
      refRegCount: 0,
      paramCount: 0,
    ));

    // Save current compilation state.
    _pushContext();
    _currentReturnType = subst.substituteType(fn.returnType);

    // Create a new scope for the thunk.
    _scope = Scope(
      valueAlloc: _valueAlloc,
      refAlloc: _refAlloc,
    );

    // Reserve standard header: ITA(0), FTA(1), this(2).
    _refAlloc.alloc(); // rsp+0: ITA
    _refAlloc.alloc(); // rsp+1: FTA
    _refAlloc.alloc(); // rsp+2: this/receiver

    // Register parameters with INSTANTIATED types. The caller sends args
    // based on the instantiated type, so this ensures the thunk receives
    // them on the correct stack.
    final paramMappings = <({int reg, StackKind instKind, StackKind actualKind,
        ir.DartType instType})>[];
    for (final param in fn.positionalParameters) {
      final instType = subst.substituteType(param.type);
      final instKind = _classifyStackKind(instType);
      final actualKind = _classifyStackKind(param.type);
      final reg = instKind.isValue ? _valueAlloc.alloc() : _refAlloc.alloc();
      paramMappings.add((
        reg: reg,
        instKind: instKind,
        actualKind: actualKind,
        instType: instType,
      ));
    }
    final namedMappings = <({int reg, StackKind instKind, StackKind actualKind,
        ir.DartType instType, String name})>[];
    for (final param in fn.namedParameters) {
      final instType = subst.substituteType(param.type);
      final instKind = _classifyStackKind(instType);
      final actualKind = _classifyStackKind(param.type);
      final reg = instKind.isValue ? _valueAlloc.alloc() : _refAlloc.alloc();
      namedMappings.add((
        reg: reg,
        instKind: instKind,
        actualKind: actualKind,
        instType: instType,
        name: param.name!,
      ));
    }

    // Build argument temps for the CALL_STATIC to the inner function,
    // coercing each arg to match the inner function's actual parameter kind.
    final argTemps = <(int, ResultLoc)>[];
    for (final m in paramMappings) {
      argTemps.add(_coerceThunkArg(m.reg, m.instKind, m.actualKind, m.instType));
    }
    for (final m in namedMappings) {
      argTemps.add(_coerceThunkArg(m.reg, m.instKind, m.actualKind, m.instType));
    }

    // Emit FTA for the call — the inner function needs its type arguments.
    _emitFTAForCall(typeArgs);

    // Emit CALL_STATIC to the inner function.
    final actualRetKind = _classifyStackKind(fn.returnType);
    final innerResultReg =
        actualRetKind.isValue ? _allocValueReg() : _allocRefReg();
    _emitArgMovesAndCall(argTemps, Op.callStatic, innerResultReg, innerFuncId);

    // Coerce return value and emit RETURN.
    final instRetKind =
        _classifyStackKind(subst.substituteType(fn.returnType));
    final actualRetLoc =
        actualRetKind.isValue ? ResultLoc.value : ResultLoc.ref;
    _emitCoercedReturn(
        innerResultReg, actualRetLoc, instRetKind, fn.returnType);

    _patchPendingArgMoves();

    // Create the thunk FuncProto.
    _functions[thunkFuncId] = DarticFuncProto(
      funcId: thunkFuncId,
      name: '<instantiation-thunk>',
      bytecode: _emitter.toUint32List(),
      valueRegCount: _valueAlloc.maxUsed,
      refRegCount: _refAlloc.maxUsed,
      paramCount:
          fn.positionalParameters.length + fn.namedParameters.length,
      paramKinds: _buildParamKinds(
          fn.positionalParameters, fn.namedParameters),
      returnKind: _classifyReturnKind(fn.returnType),
    );

    // Restore enclosing compilation state.
    _popContext();

    // Emit CLOSURE wrapping the thunk in the enclosing function.
    final closureReg = _allocRefReg();
    _emitter.emit(encodeABx(Op.closure, closureReg, thunkFuncId));
    return (closureReg, ResultLoc.ref);
  }

  /// Coerces a thunk parameter from the instantiated kind to the actual kind.
  (int, ResultLoc) _coerceThunkArg(
      int reg, StackKind instKind, StackKind actualKind, ir.DartType instType) {
    if (instKind.isValue && actualKind == StackKind.ref) {
      return (_emitBoxToRef(reg, instType), ResultLoc.ref);
    } else if (instKind == StackKind.ref && actualKind.isValue) {
      return (_emitUnbox(reg, actualKind), ResultLoc.value);
    }
    return (reg, instKind.isValue ? ResultLoc.value : ResultLoc.ref);
  }

  // ── Collection Literals ──

  /// Compiles a [ir.ListLiteral] to CREATE_LIST bytecode.
  (int, ResultLoc) _compileListLiteral(ir.ListLiteral expr) =>
      _compileElementCollection(Op.createList, expr.expressions);

  /// Compiles a [ir.MapLiteral] to CREATE_MAP bytecode.
  ///
  /// Keys and values are interleaved: [k0, v0, k1, v1, ...] in consecutive
  /// ref registers, then CREATE_MAP is emitted with C = number of pairs.
  (int, ResultLoc) _compileMapLiteral(ir.MapLiteral expr) {
    final entries = expr.entries;
    final destReg = _allocRefReg();

    if (entries.isEmpty) {
      _emitter.emit(encodeABC(Op.createMap, destReg, 0, 0));
      return (destReg, ResultLoc.ref);
    }

    // Compile each key/value, box to ref if needed.
    final kvRegs = <int>[];
    for (final entry in entries) {
      var (keyReg, keyLoc) = _compileExpression(entry.key);
      keyReg = _boxToRefIfValue(keyReg, keyLoc, _inferExprType(entry.key));
      kvRegs.add(keyReg);

      var (valReg, valLoc) = _compileExpression(entry.value);
      valReg = _boxToRefIfValue(valReg, valLoc, _inferExprType(entry.value));
      kvRegs.add(valReg);
    }

    // Move k/v pairs into consecutive slots and emit CREATE_MAP.
    _emitCreateCollection(Op.createMap, destReg, kvRegs, entries.length);
    return (destReg, ResultLoc.ref);
  }

  /// Compiles a [ir.SetLiteral] to CREATE_SET bytecode.
  (int, ResultLoc) _compileSetLiteral(ir.SetLiteral expr) =>
      _compileElementCollection(Op.createSet, expr.expressions);

  /// Shared helper for list/set literal compilation: compiles each element
  /// expression, boxes to ref if needed, and emits the collection creation op.
  (int, ResultLoc) _compileElementCollection(
    int op,
    List<ir.Expression> elements,
  ) {
    final destReg = _allocRefReg();

    if (elements.isEmpty) {
      _emitter.emit(encodeABC(op, destReg, 0, 0));
      return (destReg, ResultLoc.ref);
    }

    final elementRegs = <int>[];
    for (final elem in elements) {
      var (reg, loc) = _compileExpression(elem);
      reg = _boxToRefIfValue(reg, loc, _inferExprType(elem));
      elementRegs.add(reg);
    }

    _emitCreateCollection(op, destReg, elementRegs, elements.length);
    return (destReg, ResultLoc.ref);
  }

  // ── Collection Constants ──

  /// Compiles a [ir.ListConstant] to CREATE_LIST bytecode.
  (int, ResultLoc) _compileListConstant(ir.ListConstant constant) =>
      _compileConstantElementCollection(Op.createList, constant.entries);

  /// Compiles a [ir.MapConstant] to CREATE_MAP bytecode.
  (int, ResultLoc) _compileMapConstant(ir.MapConstant constant) {
    final entries = constant.entries;
    final destReg = _allocRefReg();

    if (entries.isEmpty) {
      _emitter.emit(encodeABC(Op.createMap, destReg, 0, 0));
      return (destReg, ResultLoc.ref);
    }

    // Compile each key/value constant, box to ref if needed.
    final kvRegs = <int>[];
    for (final entry in entries) {
      var (keyReg, keyLoc) = entry.key.accept(_constantVisitor);
      keyReg = _boxToRefIfValue(keyReg, keyLoc, _inferConstantType(entry.key));
      kvRegs.add(keyReg);

      var (valReg, valLoc) = entry.value.accept(_constantVisitor);
      valReg = _boxToRefIfValue(
          valReg, valLoc, _inferConstantType(entry.value));
      kvRegs.add(valReg);
    }

    _emitCreateCollection(Op.createMap, destReg, kvRegs, entries.length);
    return (destReg, ResultLoc.ref);
  }

  /// Compiles a [ir.SetConstant] to CREATE_SET bytecode.
  (int, ResultLoc) _compileSetConstant(ir.SetConstant constant) =>
      _compileConstantElementCollection(Op.createSet, constant.entries);

  /// Shared helper for list/set constant compilation: compiles each constant
  /// entry, boxes to ref if needed, and emits the collection creation op.
  (int, ResultLoc) _compileConstantElementCollection(
    int op,
    List<ir.Constant> entries,
  ) {
    final destReg = _allocRefReg();

    if (entries.isEmpty) {
      _emitter.emit(encodeABC(op, destReg, 0, 0));
      return (destReg, ResultLoc.ref);
    }

    final elementRegs = <int>[];
    for (final entry in entries) {
      var (reg, loc) = entry.accept(_constantVisitor);
      reg = _boxToRefIfValue(reg, loc, _inferConstantType(entry));
      elementRegs.add(reg);
    }

    _emitCreateCollection(op, destReg, elementRegs, entries.length);
    return (destReg, ResultLoc.ref);
  }

  /// Compiles an [ir.InstantiationConstant]: a generic function tear-off
  /// with bound type args in constant context.
  ///
  /// For StaticTearOffConstant targets, applies the same thunk generation
  /// as [_compileInstantiation]. For other targets, delegates directly.
  (int, ResultLoc) _compileInstantiationConstant(
      ir.InstantiationConstant constant) {
    if (constant.tearOffConstant is ir.StaticTearOffConstant) {
      final tearOff = constant.tearOffConstant as ir.StaticTearOffConstant;
      final target = tearOff.target;
      final funcId = _procToFuncId[target.reference];
      if (funcId == null) {
        throw UnsupportedError(
          'InstantiationConstant: unknown function ${target.name.text}',
        );
      }

      final fn = target.function;
      final typeParams = fn.typeParameters;
      if (typeParams.isEmpty || constant.types.isEmpty) {
        return _compileStaticTearOffConstant(tearOff);
      }

      final subst =
          type_algebra.Substitution.fromPairs(typeParams, constant.types);

      if (!_needsInstantiationThunk(fn, subst)) {
        return _compileStaticTearOffConstant(tearOff);
      }

      return _generateInstantiationThunk(funcId, fn, subst, constant.types);
    }
    return constant.tearOffConstant.accept(_constantVisitor);
  }
}

/// Visitor that compiles expressions by delegating to `_compileXxx` extension
/// methods. Lives in the part file alongside the implementations it calls.
class _ExprCompileVisitor
    with ir.ExpressionVisitorDefaultMixin<(int, ResultLoc)> {
  _ExprCompileVisitor(this._c);
  final DarticCompiler _c;

  @override
  (int, ResultLoc) defaultExpression(ir.Expression node) =>
      throw UnsupportedError(
        'Expression not yet implemented: ${node.runtimeType}. '
        'This may be added in a future compiler phase.',
      );

  @override
  (int, ResultLoc) defaultBasicLiteral(ir.BasicLiteral node) =>
      throw UnsupportedError(
        'Literal not yet implemented: ${node.runtimeType}. '
        'This may be added in a future compiler phase.',
      );

  // Literals
  @override
  (int, ResultLoc) visitIntLiteral(ir.IntLiteral node) =>
      _c._compileIntLiteral(node);
  @override
  (int, ResultLoc) visitBoolLiteral(ir.BoolLiteral node) =>
      _c._compileBoolLiteral(node);
  @override
  (int, ResultLoc) visitDoubleLiteral(ir.DoubleLiteral node) =>
      _c._compileDoubleLiteral(node);
  @override
  (int, ResultLoc) visitStringLiteral(ir.StringLiteral node) =>
      _c._compileStringLiteral(node);
  @override
  (int, ResultLoc) visitNullLiteral(ir.NullLiteral node) =>
      _c._compileNullLiteral();

  // Collection literals
  @override
  (int, ResultLoc) visitListLiteral(ir.ListLiteral node) =>
      _c._compileListLiteral(node);
  @override
  (int, ResultLoc) visitMapLiteral(ir.MapLiteral node) =>
      _c._compileMapLiteral(node);
  @override
  (int, ResultLoc) visitSetLiteral(ir.SetLiteral node) =>
      _c._compileSetLiteral(node);

  // String interpolation
  @override
  (int, ResultLoc) visitStringConcatenation(ir.StringConcatenation node) =>
      _c._compileStringConcatenation(node);

  // Variable access
  @override
  (int, ResultLoc) visitVariableGet(ir.VariableGet node) =>
      _c._compileVariableGet(node);
  @override
  (int, ResultLoc) visitVariableSet(ir.VariableSet node) =>
      _c._compileVariableSet(node);

  // Constants
  @override
  (int, ResultLoc) visitConstantExpression(ir.ConstantExpression node) =>
      _c._compileConstantExpression(node);

  // Logical / conditional / null
  @override
  (int, ResultLoc) visitNot(ir.Not node) => _c._compileNot(node);
  @override
  (int, ResultLoc) visitEqualsNull(ir.EqualsNull node) =>
      _c._compileEqualsNull(node);
  @override
  (int, ResultLoc) visitEqualsCall(ir.EqualsCall node) =>
      _c._compileEqualsCall(node);
  @override
  (int, ResultLoc) visitLogicalExpression(ir.LogicalExpression node) =>
      _c._compileLogicalExpression(node);
  @override
  (int, ResultLoc) visitConditionalExpression(
          ir.ConditionalExpression node) =>
      _c._compileConditionalExpression(node);
  @override
  (int, ResultLoc) visitNullCheck(ir.NullCheck node) =>
      _c._compileNullCheck(node);

  // Let / BlockExpression
  @override
  (int, ResultLoc) visitLet(ir.Let node) => _c._compileLet(node);
  @override
  (int, ResultLoc) visitBlockExpression(ir.BlockExpression node) =>
      _c._compileBlockExpression(node);

  // Static access
  @override
  (int, ResultLoc) visitStaticGet(ir.StaticGet node) =>
      _c._compileStaticGet(node);
  @override
  (int, ResultLoc) visitStaticSet(ir.StaticSet node) =>
      _c._compileStaticSet(node);
  @override
  (int, ResultLoc) visitStaticTearOff(ir.StaticTearOff node) =>
      _c._compileStaticTearOff(node);

  // Invocations
  @override
  (int, ResultLoc) visitStaticInvocation(ir.StaticInvocation node) =>
      _c._compileStaticInvocation(node);
  @override
  (int, ResultLoc) visitInstanceInvocation(ir.InstanceInvocation node) =>
      _c._compileInstanceInvocation(node);
  @override
  (int, ResultLoc) visitConstructorInvocation(
          ir.ConstructorInvocation node) =>
      _c._compileConstructorInvocation(node);
  @override
  (int, ResultLoc) visitLocalFunctionInvocation(
          ir.LocalFunctionInvocation node) =>
      _c._compileLocalFunctionInvocation(node);
  @override
  (int, ResultLoc) visitFunctionInvocation(ir.FunctionInvocation node) =>
      _c._compileFunctionInvocation(node);

  // Type operations
  @override
  (int, ResultLoc) visitIsExpression(ir.IsExpression node) =>
      _c._compileIsExpression(node);
  @override
  (int, ResultLoc) visitAsExpression(ir.AsExpression node) =>
      _c._compileAsExpression(node);

  // Exception expressions
  @override
  (int, ResultLoc) visitThrow(ir.Throw node) => _c._compileThrow(node);
  @override
  (int, ResultLoc) visitRethrow(ir.Rethrow node) => _c._compileRethrow(node);

  // Async
  @override
  (int, ResultLoc) visitAwaitExpression(ir.AwaitExpression node) =>
      _c._compileAwaitExpression(node);

  // Closures
  @override
  (int, ResultLoc) visitFunctionExpression(ir.FunctionExpression node) =>
      _c._compileFunctionExpression(node);

  // this
  @override
  (int, ResultLoc) visitThisExpression(ir.ThisExpression node) =>
      _c._compileThisExpression();

  // Instance field access
  @override
  (int, ResultLoc) visitInstanceGet(ir.InstanceGet node) =>
      _c._compileInstanceGet(node);
  @override
  (int, ResultLoc) visitInstanceSet(ir.InstanceSet node) =>
      _c._compileInstanceSet(node);

  // Super access
  @override
  (int, ResultLoc) visitSuperMethodInvocation(
          ir.SuperMethodInvocation node) =>
      _c._compileSuperMethodInvocation(node);
  @override
  (int, ResultLoc) visitSuperPropertyGet(ir.SuperPropertyGet node) =>
      _c._compileSuperPropertyGet(node);
  @override
  (int, ResultLoc) visitSuperPropertySet(ir.SuperPropertySet node) =>
      _c._compileSuperPropertySet(node);

  // Phase 4 additions
  @override
  (int, ResultLoc) visitTypeLiteral(ir.TypeLiteral node) =>
      _c._compileTypeLiteral(node);
  @override
  (int, ResultLoc) visitInstantiation(ir.Instantiation node) =>
      _c._compileInstantiation(node);

  // Dynamic dispatch (Phase 5)
  @override
  (int, ResultLoc) visitDynamicGet(ir.DynamicGet node) =>
      _c._compileDynamicGet(node);
  @override
  (int, ResultLoc) visitDynamicSet(ir.DynamicSet node) =>
      _c._compileDynamicSet(node);
  @override
  (int, ResultLoc) visitDynamicInvocation(ir.DynamicInvocation node) =>
      _c._compileDynamicInvocation(node);
}

/// Visitor that compiles [ir.Constant] nodes to bytecode.
///
/// Delegates each constant type to the corresponding extension method on
/// [DarticCompiler]. Unhandled constants fall through to [defaultConstant]
/// which throws [UnsupportedError].
class _ConstantCompileVisitor
    with ir.ConstantVisitorDefaultMixin<(int, ResultLoc)> {
  _ConstantCompileVisitor(this._c);
  final DarticCompiler _c;

  @override
  (int, ResultLoc) defaultConstant(ir.Constant node) => throw UnsupportedError(
        'Constant not yet implemented: ${node.runtimeType}. '
        'This may be added in a future compiler phase.',
      );

  @override
  (int, ResultLoc) visitIntConstant(ir.IntConstant node) =>
      _c._loadInt(node.value);
  @override
  (int, ResultLoc) visitDoubleConstant(ir.DoubleConstant node) =>
      _c._loadDouble(node.value);
  @override
  (int, ResultLoc) visitBoolConstant(ir.BoolConstant node) =>
      _c._loadBool(node.value);
  @override
  (int, ResultLoc) visitStringConstant(ir.StringConstant node) =>
      _c._loadString(node.value);
  @override
  (int, ResultLoc) visitNullConstant(ir.NullConstant node) => _c._loadNull();
  @override
  (int, ResultLoc) visitStaticTearOffConstant(
          ir.StaticTearOffConstant node) =>
      _c._compileStaticTearOffConstant(node);

  // Phase 4 additions
  @override
  (int, ResultLoc) visitInstanceConstant(ir.InstanceConstant node) =>
      _c._compileInstanceConstant(node);
  @override
  (int, ResultLoc) visitTypeLiteralConstant(ir.TypeLiteralConstant node) =>
      _c._compileTypeLiteralConstant(node);
  @override
  (int, ResultLoc) visitInstantiationConstant(
          ir.InstantiationConstant node) =>
      _c._compileInstantiationConstant(node);

  // Collection constants
  @override
  (int, ResultLoc) visitListConstant(ir.ListConstant node) =>
      _c._compileListConstant(node);
  @override
  (int, ResultLoc) visitMapConstant(ir.MapConstant node) =>
      _c._compileMapConstant(node);
  @override
  (int, ResultLoc) visitSetConstant(ir.SetConstant node) =>
      _c._compileSetConstant(node);
}
