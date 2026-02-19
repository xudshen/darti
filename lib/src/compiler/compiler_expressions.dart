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
    if (expr is ir.LocalFunctionInvocation) {
      return _compileLocalFunctionInvocation(expr);
    }
    if (expr is ir.FunctionExpression) {
      return _compileFunctionExpression(expr);
    }
    if (expr is ir.FunctionInvocation) {
      return _compileFunctionInvocation(expr);
    }
    if (expr is ir.StaticTearOff) {
      return _compileStaticTearOff(expr);
    }
    if (expr is ir.ConstructorInvocation) {
      return _compileConstructorInvocation(expr);
    }
    if (expr is ir.ThisExpression) {
      return _compileThisExpression();
    }
    if (expr is ir.InstanceGet) {
      return _compileInstanceGet(expr);
    }
    if (expr is ir.InstanceSet) {
      return _compileInstanceSet(expr);
    }
    if (expr is ir.SuperMethodInvocation) {
      return _compileSuperMethodInvocation(expr);
    }
    if (expr is ir.SuperPropertyGet) {
      return _compileSuperPropertyGet(expr);
    }
    if (expr is ir.SuperPropertySet) {
      return _compileSuperPropertySet(expr);
    }
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
    if (constant is ir.StaticTearOffConstant) {
      return _compileStaticTearOffConstant(constant);
    }
    throw UnsupportedError(
      'Unsupported constant type: ${constant.runtimeType}',
    );
  }

  // ── Not ──

  (int, ResultLoc) _compileNot(ir.Not expr) {
    var (operandReg, operandLoc) = _compileExpression(expr.operand);
    operandReg = _ensureBoolValue(operandReg, operandLoc);
    final resultReg = _allocValueReg();
    // Load 1 into result, then XOR with operand: result = operand ^ 1
    _emitter.emit(encodeAsBx(Op.loadInt, resultReg, 1));
    _emitter.emit(encodeABC(Op.bitXor, resultReg, operandReg, resultReg));
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
    final (refReg, loc) = _compileExpression(expr.expression);
    assert(loc == ResultLoc.ref,
        'EqualsNull operand must be on ref stack (got value)');
    final resultReg = _allocValueReg();
    // EqualsNull always represents `x == null` (no isNot flag).
    // CFE expresses `x != null` as `Not(EqualsNull(x))`.
    // Pattern: LOAD_FALSE -> JUMP_IF_NNULL +1 -> LOAD_TRUE
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

    // User-defined operator==: dispatch via CALL_VIRTUAL.
    // Check if interfaceTarget is from a user-defined class (not Object/int/double).
    if (!isInt && !isDouble) {
      final eqClass = expr.interfaceTarget.enclosingClass;
      if (eqClass != null && _classToClassId.containsKey(eqClass)) {
        return _compileUserEqualsCall(expr);
      }
    }

    var (lhsReg, lhsLoc) = _compileExpression(expr.left);
    var (rhsReg, rhsLoc) = _compileExpression(expr.right);
    final resultReg = _allocValueReg();

    if (isInt) {
      // Unbox if operands are on the ref-stack (e.g., generic field access).
      if (lhsLoc == ResultLoc.ref) {
        final valReg = _allocValueReg();
        _emitter.emit(encodeABC(Op.unboxInt, valReg, lhsReg, 0));
        lhsReg = valReg;
      }
      if (rhsLoc == ResultLoc.ref) {
        final valReg = _allocValueReg();
        _emitter.emit(encodeABC(Op.unboxInt, valReg, rhsReg, 0));
        rhsReg = valReg;
      }
      _emitter.emit(encodeABC(Op.eqInt, resultReg, lhsReg, rhsReg));
    } else if (isDouble) {
      if (lhsLoc == ResultLoc.ref) {
        final valReg = _allocValueReg();
        _emitter.emit(encodeABC(Op.unboxDouble, valReg, lhsReg, 0));
        lhsReg = valReg;
      }
      if (rhsLoc == ResultLoc.ref) {
        final valReg = _allocValueReg();
        _emitter.emit(encodeABC(Op.unboxDouble, valReg, rhsReg, 0));
        rhsReg = valReg;
      }
      _emitter.emit(encodeABC(Op.eqDbl, resultReg, lhsReg, rhsReg));
    } else {
      // EQ_GENERIC operates on the ref stack — ensure both operands are boxed.
      if (lhsLoc == ResultLoc.value) {
        lhsReg = _emitBoxToRef(lhsReg, _inferExprType(expr.left));
      }
      if (rhsLoc == ResultLoc.value) {
        rhsReg = _emitBoxToRef(rhsReg, _inferExprType(expr.right));
      }
      _emitter.emit(encodeABC(Op.eqGeneric, resultReg, lhsReg, rhsReg));
    }
    return (resultReg, ResultLoc.value);
  }

  /// Compiles a user-defined operator== via CALL_VIRTUAL.
  (int, ResultLoc) _compileUserEqualsCall(ir.EqualsCall expr) {
    // Compile receiver (left operand, ref stack).
    var (receiverReg, receiverLoc) = _compileExpression(expr.left);
    if (receiverLoc == ResultLoc.value) {
      receiverReg = _emitBoxToRef(receiverReg, _inferExprType(expr.left));
    }

    // Compile argument (right operand, ref stack — parameter type is Object).
    var (argReg, argLoc) = _compileExpression(expr.right);
    if (argLoc == ResultLoc.value) {
      argReg = _emitBoxToRef(argReg, _inferExprType(expr.right));
    }

    // Result is bool (value stack).
    final resultReg = _allocValueReg();

    // Emit arg move for right operand via shared helper.
    _emitArgMovesForVirtualCall([(argReg, ResultLoc.ref)]);

    // Emit CALL_VIRTUAL with method name '=='.
    final methodNameIdx = _constantPool.addName('==');
    final icIndex = _icEntries.length;
    _icEntries.add(ICEntry(methodNameIndex: methodNameIdx));
    _emitter.emit(
        encodeABC(Op.callVirtual, resultReg, receiverReg, icIndex));

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
      final unboxOp =
          kind == StackKind.doubleVal ? Op.unboxDouble : Op.unboxInt;
      final valReg = _allocValueReg();
      _emitter.emit(encodeABC(unboxOp, valReg, refReg, 0));
      return (valReg, ResultLoc.value);
    }
    return (refReg, ResultLoc.ref);
  }

  (int, ResultLoc) _compileVariableSet(ir.VariableSet expr) {
    // Check if this is an upvalue access (variable from outer function scope).
    if (_contextStack.isNotEmpty && _isUpvalueAccess(expr.variable)) {
      final uvIdx = _resolveUpvalue(expr.variable);
      var (srcReg, srcLoc) = _compileExpression(expr.value);
      // Ensure the value is on the ref stack (upvalues always use ref stack).
      if (srcLoc == ResultLoc.value) {
        srcReg = _emitBoxToRef(srcReg, _inferExprType(expr.value));
      }
      _emitter.emit(encodeABx(Op.storeUpvalue, srcReg, uvIdx));
      return (srcReg, ResultLoc.ref);
    }

    // Check if this variable has been captured (promoted to ref stack)
    // in the current enclosing function. If so, box and write to the
    // ref register.
    if (_capturedVarRefRegs.containsKey(expr.variable)) {
      final refReg = _capturedVarRefRegs[expr.variable]!;
      var (srcReg, srcLoc) = _compileExpression(expr.value);
      if (srcLoc == ResultLoc.value) {
        srcReg = _emitBoxToRef(srcReg, _inferExprType(expr.value));
      }
      _emitMove(refReg, srcReg, ResultLoc.ref);
      return (refReg, ResultLoc.ref);
    }

    final binding = _lookupVar(expr.variable);
    var (srcReg, srcLoc) = _compileExpression(expr.value);
    final bindingLoc = _locOf(binding);
    // Coerce stack kind if mismatch.
    if (bindingLoc == ResultLoc.value && srcLoc == ResultLoc.ref) {
      // Unbox ref→value (e.g., generic field assigned to int variable).
      final kind = binding.kind;
      final unboxOp = kind == StackKind.doubleVal ? Op.unboxDouble : Op.unboxInt;
      final valReg = _allocValueReg();
      _emitter.emit(encodeABC(unboxOp, valReg, srcReg, 0));
      srcReg = valReg;
    } else if (bindingLoc == ResultLoc.ref && srcLoc == ResultLoc.value) {
      // Box value→ref (e.g., int literal assigned to Object variable).
      srcReg = _emitBoxToRef(srcReg, _inferExprType(expr.value));
    }
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

    // Static getter: compile as CALL_STATIC (no receiver).
    if (target is ir.Procedure && target.isGetter) {
      final funcId = _procToFuncId[target.reference];
      if (funcId == null) {
        throw UnsupportedError(
          'Unknown static getter: ${target.name.text}',
        );
      }

      final retType = target.function.returnType;
      final retLoc = _classifyType(retType);
      final resultReg =
          retLoc == ResultLoc.ref ? _allocRefReg() : _allocValueReg();

      // No arguments — emit CALL_STATIC directly.
      _emitter.emit(encodeABx(Op.callStatic, resultReg, funcId));
      return (resultReg, retLoc);
    }

    throw UnsupportedError(
      'Unsupported StaticGet: ${target.name.text}',
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
    final funcId = _procToFuncId[target.reference];
    if (funcId == null) {
      throw UnsupportedError(
        'Unknown static call target: ${target.name.text}',
      );
    }

    // Allocate result register FIRST -- it lives within the caller's frame.
    final retType = target.function.returnType;
    final retLoc = _classifyType(retType);
    final resultReg =
        retLoc == ResultLoc.ref ? _allocRefReg() : _allocValueReg();

    // Compile each argument expression to a temp register within the frame.
    final positionalArgs = expr.arguments.positional;
    final namedArgs = expr.arguments.named;
    final positionalParams = target.function.positionalParameters;
    final namedParams = target.function.namedParameters;
    final argTemps = <(int, ResultLoc)>[];

    // 1. Compile provided positional arguments.
    for (var i = 0; i < positionalArgs.length; i++) {
      var (argReg, argLoc) = _compileExpression(positionalArgs[i]);

      // Coerce stack kind when callee parameter and argument disagree.
      if (i < positionalParams.length) {
        final paramKind = _classifyStackKind(positionalParams[i].type);
        if (paramKind == StackKind.ref && argLoc == ResultLoc.value) {
          final argType = _inferExprType(positionalArgs[i]);
          argReg = _emitBoxToRef(argReg, argType);
          argLoc = ResultLoc.ref;
        } else if (paramKind.isValue && argLoc == ResultLoc.ref) {
          final unboxOp = paramKind == StackKind.doubleVal
              ? Op.unboxDouble : Op.unboxInt;
          final valReg = _allocValueReg();
          _emitter.emit(encodeABC(unboxOp, valReg, argReg, 0));
          argReg = valReg;
          argLoc = ResultLoc.value;
        }
      }

      argTemps.add((argReg, argLoc));
    }

    // 2. Fill in missing optional positional arguments with default values.
    for (var i = positionalArgs.length; i < positionalParams.length; i++) {
      final param = positionalParams[i];
      final (argReg, argLoc) = _compileDefaultValue(param);
      argTemps.add((argReg, argLoc));
    }

    // 3. Handle named arguments.
    if (namedParams.isNotEmpty) {
      _compileNamedArgsFromParams(namedParams, namedArgs, argTemps);
    }

    // 4. Emit FTA for generic function calls.
    _emitFTAForCall(expr.arguments.types);

    _emitArgMovesAndCall(argTemps, Op.callStatic, resultReg, funcId);
    return (resultReg, retLoc);
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
    // Look up the closure variable.
    final binding = _lookupVar(expr.variable);
    final closureReg = binding.reg;

    // Determine return type for the result register.
    final retType = expr.variable.type;
    final funcType = retType is ir.FunctionType ? retType.returnType : retType;
    final retLoc = _classifyType(funcType);
    final resultReg =
        retLoc == ResultLoc.ref ? _allocRefReg() : _allocValueReg();

    // Compile positional arguments with type coercion.
    final args = expr.arguments.positional;
    final posParamTypes = (expr.variable.type is ir.FunctionType)
        ? (expr.variable.type as ir.FunctionType).positionalParameters
        : const <ir.DartType>[];
    final argTemps = <(int, ResultLoc)>[];
    for (var i = 0; i < args.length; i++) {
      var (argReg, argLoc) = _compileExpression(args[i]);
      if (i < posParamTypes.length) {
        final paramKind = _classifyStackKind(posParamTypes[i]);
        if (paramKind == StackKind.ref && argLoc == ResultLoc.value) {
          argReg = _emitBoxToRef(argReg, _inferExprType(args[i]));
          argLoc = ResultLoc.ref;
        } else if (paramKind.isValue && argLoc == ResultLoc.ref) {
          final unboxOp = paramKind == StackKind.doubleVal
              ? Op.unboxDouble : Op.unboxInt;
          final valReg = _allocValueReg();
          _emitter.emit(encodeABC(unboxOp, valReg, argReg, 0));
          argReg = valReg;
          argLoc = ResultLoc.value;
        }
      }
      argTemps.add((argReg, argLoc));
    }

    // Handle named arguments via the variable's FunctionType.
    final varFuncType = expr.variable.type;
    if (varFuncType is ir.FunctionType &&
        varFuncType.namedParameters.isNotEmpty) {
      _compileNamedArgsFromNamedTypes(
        varFuncType.namedParameters,
        expr.arguments.named,
        argTemps,
      );
    }

    _emitArgMovesAndCall(argTemps, Op.call, resultReg, closureReg);
    return (resultReg, retLoc);
  }

  /// Compiles a [FunctionInvocation] -- calling a closure stored in a variable
  /// or returned from another expression.
  (int, ResultLoc) _compileFunctionInvocation(ir.FunctionInvocation expr) {
    // Compile the receiver expression to get the closure ref register.
    final (closureReg, _) = _compileExpression(expr.receiver);

    // Determine return type from the function type.
    final funcType = expr.functionType;
    final retType = funcType?.returnType ?? const ir.DynamicType();
    final retLoc = _classifyType(retType);
    final resultReg =
        retLoc == ResultLoc.ref ? _allocRefReg() : _allocValueReg();

    // Compile positional arguments with type coercion.
    final args = expr.arguments.positional;
    final posParamTypes = funcType?.positionalParameters ?? const <ir.DartType>[];
    final argTemps = <(int, ResultLoc)>[];
    for (var i = 0; i < args.length; i++) {
      var (argReg, argLoc) = _compileExpression(args[i]);
      if (i < posParamTypes.length) {
        final paramKind = _classifyStackKind(posParamTypes[i]);
        if (paramKind == StackKind.ref && argLoc == ResultLoc.value) {
          argReg = _emitBoxToRef(argReg, _inferExprType(args[i]));
          argLoc = ResultLoc.ref;
        } else if (paramKind.isValue && argLoc == ResultLoc.ref) {
          final unboxOp = paramKind == StackKind.doubleVal
              ? Op.unboxDouble : Op.unboxInt;
          final valReg = _allocValueReg();
          _emitter.emit(encodeABC(unboxOp, valReg, argReg, 0));
          argReg = valReg;
          argLoc = ResultLoc.value;
        }
      }
      argTemps.add((argReg, argLoc));
    }

    // Handle named arguments via the expression's FunctionType.
    if (funcType != null && funcType.namedParameters.isNotEmpty) {
      _compileNamedArgsFromNamedTypes(
        funcType.namedParameters,
        expr.arguments.named,
        argTemps,
      );
    }

    _emitArgMovesAndCall(argTemps, Op.call, resultReg, closureReg);
    return (resultReg, retLoc);
  }

  // ── Shared call helpers ──

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
        if (paramKind == StackKind.ref && argLoc == ResultLoc.value) {
          final argType = _inferExprType(provided.value);
          argReg = _emitBoxToRef(argReg, argType);
          argLoc = ResultLoc.ref;
        } else if (paramKind.isValue && argLoc == ResultLoc.ref) {
          final unboxOp = paramKind == StackKind.doubleVal
              ? Op.unboxDouble : Op.unboxInt;
          final valReg = _allocValueReg();
          _emitter.emit(encodeABC(unboxOp, valReg, argReg, 0));
          argReg = valReg;
          argLoc = ResultLoc.value;
        }
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
        if (paramKind == StackKind.ref && argLoc == ResultLoc.value) {
          final argType = _inferExprType(provided.value);
          argReg = _emitBoxToRef(argReg, argType);
          argLoc = ResultLoc.ref;
        } else if (paramKind.isValue && argLoc == ResultLoc.ref) {
          final unboxOp = paramKind == StackKind.doubleVal
              ? Op.unboxDouble : Op.unboxInt;
          final valReg = _allocValueReg();
          _emitter.emit(encodeABC(unboxOp, valReg, argReg, 0));
          argReg = valReg;
          argLoc = ResultLoc.value;
        }
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
    for (var i = 0; i < argTemps.length; i++) {
      final (srcReg, loc) = argTemps[i];
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
      final receiverType = _inferExprType(expr.receiver);

      // int `/` returns double -- convert both operands and use DIV_DBL.
      if (name == '/' &&
          receiverType != null &&
          _isIntType(receiverType)) {
        var (lhsReg, lhsLoc) = _compileExpression(expr.receiver);
        var (rhsReg, rhsLoc) =
            _compileExpression(expr.arguments.positional[0]);
        // Unbox if operands are on the ref-stack (e.g., generic field access).
        if (lhsLoc == ResultLoc.ref) {
          final valReg = _allocValueReg();
          _emitter.emit(encodeABC(Op.unboxInt, valReg, lhsReg, 0));
          lhsReg = valReg;
        }
        if (rhsLoc == ResultLoc.ref) {
          final valReg = _allocValueReg();
          _emitter.emit(encodeABC(Op.unboxInt, valReg, rhsReg, 0));
          rhsReg = valReg;
        }
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

    // General case: virtual method dispatch via CALL_VIRTUAL + IC.
    return _compileVirtualCall(expr);
  }

  /// Compiles a virtual method call via CALL_VIRTUAL with inline cache.
  ///
  /// Handles: compile receiver → compile args → emit arg MOVEs →
  /// emit CALL_VIRTUAL A,B,C where A=result, B=receiver, C=IC index.
  /// The interpreter places the receiver at callee's rsp+2 automatically.
  (int, ResultLoc) _compileVirtualCall(ir.InstanceInvocation expr) {
    final target = expr.interfaceTarget;
    final methodName = expr.name.text;

    // 1. Compile receiver (always ref stack).
    final (receiverReg, _) = _compileExpression(expr.receiver);

    // 2. Allocate result register based on return type.
    final retType = target.function.returnType;
    final retLoc = _classifyType(retType);
    final resultReg =
        retLoc == ResultLoc.ref ? _allocRefReg() : _allocValueReg();

    // 3. Compile arguments.
    final positionalParams = target.function.positionalParameters;
    final namedParams = target.function.namedParameters;
    final argTemps = <(int, ResultLoc)>[];

    for (var i = 0; i < expr.arguments.positional.length; i++) {
      var (argReg, argLoc) = _compileExpression(expr.arguments.positional[i]);
      if (i < positionalParams.length) {
        final paramKind = _classifyStackKind(positionalParams[i].type);
        if (paramKind == StackKind.ref && argLoc == ResultLoc.value) {
          argReg = _emitBoxToRef(
              argReg, _inferExprType(expr.arguments.positional[i]));
          argLoc = ResultLoc.ref;
        } else if (paramKind.isValue && argLoc == ResultLoc.ref) {
          final unboxOp = paramKind == StackKind.doubleVal
              ? Op.unboxDouble : Op.unboxInt;
          final valReg = _allocValueReg();
          _emitter.emit(encodeABC(unboxOp, valReg, argReg, 0));
          argReg = valReg;
          argLoc = ResultLoc.value;
        }
      }
      argTemps.add((argReg, argLoc));
    }

    // Fill missing optional positional args with defaults.
    for (var i = expr.arguments.positional.length;
        i < positionalParams.length;
        i++) {
      argTemps.add(_compileDefaultValue(positionalParams[i]));
    }

    // Handle named arguments.
    if (namedParams.isNotEmpty) {
      _compileNamedArgsFromParams(namedParams, expr.arguments.named, argTemps);
    }

    // 4. Emit FTA for generic method calls.
    _emitFTAForCall(expr.arguments.types);

    // 5. Emit pending arg MOVEs (skip receiver -- interpreter handles this).
    _emitArgMovesForVirtualCall(argTemps);

    // 6. Allocate IC entry and emit CALL_VIRTUAL.
    final methodNameIdx = _constantPool.addName(methodName);
    final icIndex = _icEntries.length;
    _icEntries.add(ICEntry(methodNameIndex: methodNameIdx));

    _emitter.emit(
        encodeABC(Op.callVirtual, resultReg, receiverReg, icIndex));

    return (resultReg, retLoc);
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

  // ── Exception expressions: throw / rethrow ──

  (int, ResultLoc) _compileThrow(ir.Throw expr) {
    var (reg, loc) = _compileExpression(expr.expression);

    // Ensure it's on the ref stack -- exceptions are always objects.
    if (loc == ResultLoc.value) {
      final exprType = _inferExprType(expr.expression);
      reg = _emitBoxToRef(reg, exprType);
    }

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
    if (operandLoc == ResultLoc.value) {
      final operandType = _inferExprType(expr.operand);
      operandReg = _emitBoxToRef(operandReg, operandType);
    }

    // Emit INSTANTIATE_TYPE for the target type → ref register.
    final typeReg = _emitInstantiateType(expr.type);

    final resultReg = _allocValueReg();
    _emitter.emit(encodeABC(Op.instanceOf, resultReg, operandReg, typeReg));

    return (resultReg, ResultLoc.value);
  }

  (int, ResultLoc) _compileAsExpression(ir.AsExpression expr) {
    var (operandReg, operandLoc) = _compileExpression(expr.operand);

    // Box if on value stack -- CAST needs the operand on the ref stack.
    if (operandLoc == ResultLoc.value) {
      final operandType = _inferExprType(expr.operand);
      operandReg = _emitBoxToRef(operandReg, operandType);
    }

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

  /// Compiles a [ConstructorInvocation]: NEW_INSTANCE (or ALLOC_GENERIC for
  /// generic classes) → args → CALL_STATIC.
  ///
  /// The expression result is the newly allocated object (ref stack), NOT
  /// the constructor's void return value.
  (int, ResultLoc) _compileConstructorInvocation(
    ir.ConstructorInvocation expr,
  ) {
    final target = expr.target;
    final funcId = _constructorToFuncId[target.reference];
    if (funcId == null) {
      throw UnsupportedError(
        'Unknown constructor: ${target.enclosingClass.name}.${target.name.text}',
      );
    }
    final cls = target.enclosingClass;
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
    final positionalParams = target.function.positionalParameters;
    final namedParams = target.function.namedParameters;
    final argTemps = <(int, ResultLoc)>[];

    for (var i = 0; i < expr.arguments.positional.length; i++) {
      var (argReg, argLoc) = _compileExpression(expr.arguments.positional[i]);
      if (i < positionalParams.length) {
        final paramKind = _classifyStackKind(positionalParams[i].type);
        if (paramKind == StackKind.ref && argLoc == ResultLoc.value) {
          argReg =
              _emitBoxToRef(argReg, _inferExprType(expr.arguments.positional[i]));
          argLoc = ResultLoc.ref;
        } else if (paramKind.isValue && argLoc == ResultLoc.ref) {
          final unboxOp = paramKind == StackKind.doubleVal
              ? Op.unboxDouble : Op.unboxInt;
          final valReg = _allocValueReg();
          _emitter.emit(encodeABC(unboxOp, valReg, argReg, 0));
          argReg = valReg;
          argLoc = ResultLoc.value;
        }
      }
      argTemps.add((argReg, argLoc));
    }

    // Fill missing optional positional args with defaults.
    for (var i = expr.arguments.positional.length;
        i < positionalParams.length;
        i++) {
      argTemps.add(_compileDefaultValue(positionalParams[i]));
    }

    // Handle named arguments.
    if (namedParams.isNotEmpty) {
      _compileNamedArgsFromParams(namedParams, expr.arguments.named, argTemps);
    }

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
          final (recvReg, _) = _compileExpression(expr.receiver);
          if (layout.kind.isValue) {
            final resultReg = _allocValueReg();
            _emitter.emit(encodeABC(
              Op.getFieldVal, resultReg, recvReg, layout.offset,
            ));
            return (resultReg, ResultLoc.value);
          } else {
            final resultReg = _allocRefReg();
            _emitter.emit(encodeABC(
              Op.getFieldRef, resultReg, recvReg, layout.offset,
            ));
            return (resultReg, ResultLoc.ref);
          }
        }
      }
    }

    // Check if the target is a getter Procedure → emit CALL_VIRTUAL.
    if (target is ir.Procedure && target.isGetter) {
      return _compileInstanceGetterCall(expr, target);
    }

    throw UnsupportedError(
      'Unsupported InstanceGet: ${expr.name.text} on ${targetClass?.name}',
    );
  }

  /// Compiles an instance getter call via CALL_VIRTUAL.
  ///
  /// A getter has no arguments (only the receiver). The interpreter places
  /// the receiver at callee's rsp+2 automatically.
  (int, ResultLoc) _compileInstanceGetterCall(
    ir.InstanceGet expr,
    ir.Procedure getter,
  ) {
    // 1. Compile receiver (always ref stack).
    final (receiverReg, _) = _compileExpression(expr.receiver);

    // 2. Allocate result register based on the getter's return type.
    final retType = getter.function.returnType;
    final retLoc = _classifyType(retType);
    final resultReg =
        retLoc == ResultLoc.ref ? _allocRefReg() : _allocValueReg();

    // 3. No arguments for a getter — skip arg moves.

    // 4. Allocate IC entry and emit CALL_VIRTUAL.
    final methodName = expr.name.text; // Getter uses the property name.
    final methodNameIdx = _constantPool.addName(methodName);
    final icIndex = _icEntries.length;
    _icEntries.add(ICEntry(methodNameIndex: methodNameIdx));

    _emitter.emit(
        encodeABC(Op.callVirtual, resultReg, receiverReg, icIndex));

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
          final (recvReg, _) = _compileExpression(expr.receiver);
          var (valReg, valLoc) = _compileExpression(expr.value);

          if (layout.kind.isValue) {
            if (valLoc == ResultLoc.ref) {
              final unboxed = _allocValueReg();
              final unboxOp = layout.kind == StackKind.doubleVal
                  ? Op.unboxDouble
                  : Op.unboxInt;
              _emitter.emit(encodeABC(unboxOp, unboxed, valReg, 0));
              valReg = unboxed;
            }
            _emitter.emit(encodeABC(
              Op.setFieldVal, recvReg, valReg, layout.offset,
            ));
          } else {
            if (valLoc == ResultLoc.value) {
              valReg = _emitBoxToRef(valReg, _inferExprType(expr.value));
            }
            _emitter.emit(encodeABC(
              Op.setFieldRef, recvReg, valReg, layout.offset,
            ));
          }
          // InstanceSet result is the written value.
          return (valReg, valLoc);
        }
      }
    }

    // Check if the target is a setter Procedure → emit CALL_VIRTUAL.
    if (target is ir.Procedure && target.isSetter) {
      return _compileInstanceSetterCall(expr, target);
    }

    throw UnsupportedError(
      'Unsupported InstanceSet: ${expr.name.text} on ${targetClass?.name}',
    );
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
    // 1. Compile receiver (always ref stack).
    final (receiverReg, _) = _compileExpression(expr.receiver);

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
    final methodName = '${expr.name.text}=';
    final methodNameIdx = _constantPool.addName(methodName);
    final icIndex = _icEntries.length;
    _icEntries.add(ICEntry(methodNameIndex: methodNameIdx));
    _emitter.emit(
        encodeABC(Op.callVirtual, dummyResult, receiverReg, icIndex));

    // InstanceSet evaluates to the assigned value.
    return (savedValReg, savedValLoc);
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
    final retType = target.function.returnType;
    final retLoc = _classifyType(retType);
    final resultReg =
        retLoc == ResultLoc.ref ? _allocRefReg() : _allocValueReg();

    // Compile arguments.
    final positionalParams = target.function.positionalParameters;
    final namedParams = target.function.namedParameters;
    final argTemps = <(int, ResultLoc)>[];

    for (var i = 0; i < expr.arguments.positional.length; i++) {
      var (argReg, argLoc) = _compileExpression(expr.arguments.positional[i]);
      if (i < positionalParams.length) {
        final paramKind = _classifyStackKind(positionalParams[i].type);
        if (paramKind == StackKind.ref && argLoc == ResultLoc.value) {
          argReg = _emitBoxToRef(
            argReg, _inferExprType(expr.arguments.positional[i]));
          argLoc = ResultLoc.ref;
        } else if (paramKind.isValue && argLoc == ResultLoc.ref) {
          final unboxOp = paramKind == StackKind.doubleVal
              ? Op.unboxDouble : Op.unboxInt;
          final valReg = _allocValueReg();
          _emitter.emit(encodeABC(unboxOp, valReg, argReg, 0));
          argReg = valReg;
          argLoc = ResultLoc.value;
        }
      }
      argTemps.add((argReg, argLoc));
    }

    // Fill missing optional positional args.
    for (var i = expr.arguments.positional.length;
        i < positionalParams.length;
        i++) {
      argTemps.add(_compileDefaultValue(positionalParams[i]));
    }

    // Handle named arguments.
    if (namedParams.isNotEmpty) {
      _compileNamedArgsFromParams(namedParams, expr.arguments.named, argTemps);
    }

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
          if (layout.kind.isValue) {
            final resultReg = _allocValueReg();
            _emitter.emit(encodeABC(
              Op.getFieldVal, resultReg, thisReg, layout.offset,
            ));
            return (resultReg, ResultLoc.value);
          } else {
            final resultReg = _allocRefReg();
            _emitter.emit(encodeABC(
              Op.getFieldRef, resultReg, thisReg, layout.offset,
            ));
            return (resultReg, ResultLoc.ref);
          }
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

      final retType = target.function.returnType;
      final retLoc = _classifyType(retType);
      final resultReg =
          retLoc == ResultLoc.ref ? _allocRefReg() : _allocValueReg();

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

          if (layout.kind.isValue) {
            if (valLoc == ResultLoc.ref) {
              final unboxed = _allocValueReg();
              final unboxOp = layout.kind == StackKind.doubleVal
                  ? Op.unboxDouble
                  : Op.unboxInt;
              _emitter.emit(encodeABC(unboxOp, unboxed, valReg, 0));
              valReg = unboxed;
            }
            _emitter.emit(encodeABC(
              Op.setFieldVal, thisReg, valReg, layout.offset,
            ));
          } else {
            if (valLoc == ResultLoc.value) {
              valReg = _emitBoxToRef(valReg, _inferExprType(expr.value));
            }
            _emitter.emit(encodeABC(
              Op.setFieldRef, thisReg, valReg, layout.offset,
            ));
          }
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
}
