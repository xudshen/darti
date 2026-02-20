part of 'compiler.dart';

/// Closure compilation methods for [DarticCompiler].
///
/// Contains context push/pop, inner function compilation,
/// captured variable analysis, upvalue resolution, and related helpers.
/// Also includes [_CompilationContext] and [_CapturedVarVisitor].
extension on DarticCompiler {
  // ── Context management ──

  /// Saves the current per-function compilation state to [_contextStack]
  /// and initializes fresh state for compiling a nested function.
  void _pushContext() {
    _contextStack.add(_CompilationContext(
      emitter: _emitter,
      valueAlloc: _valueAlloc,
      refAlloc: _refAlloc,
      scope: _scope,
      isEntryFunction: _isEntryFunction,
      currentReturnType: _currentReturnType,
      pendingArgMoves: List.of(_pendingArgMoves),
      labelBreakJumps: Map.of(_labelBreakJumps),
      exceptionHandlers: List.of(_exceptionHandlers),
      icEntries: List.of(_icEntries),
      catchExceptionReg: _catchExceptionReg,
      catchStackTraceReg: _catchStackTraceReg,
      upvalueDescriptors: _upvalueDescriptors,
      upvalueIndices: _upvalueIndices,
      capturedVarRefRegs: _capturedVarRefRegs,
    ));

    _emitter = BytecodeEmitter();
    _valueAlloc = RegisterAllocator();
    _refAlloc = RegisterAllocator();
    _isEntryFunction = false;
    _pendingArgMoves.clear();
    _labelBreakJumps.clear();
    _exceptionHandlers.clear();
    _icEntries.clear();
    _catchExceptionReg = -1;
    _catchStackTraceReg = -1;
    _upvalueDescriptors = [];
    _upvalueIndices = {};
    _capturedVarRefRegs = {};
  }

  /// Restores the previous compilation context from [_contextStack].
  void _popContext() {
    final ctx = _contextStack.removeLast();
    _emitter = ctx.emitter;
    _valueAlloc = ctx.valueAlloc;
    _refAlloc = ctx.refAlloc;
    _scope = ctx.scope;
    _isEntryFunction = ctx.isEntryFunction;
    _currentReturnType = ctx.currentReturnType;
    _restoreList(_pendingArgMoves, ctx.pendingArgMoves);
    _restoreMap(_labelBreakJumps, ctx.labelBreakJumps);
    _restoreList(_exceptionHandlers, ctx.exceptionHandlers);
    _restoreList(_icEntries, ctx.icEntries);
    _catchExceptionReg = ctx.catchExceptionReg;
    _catchStackTraceReg = ctx.catchStackTraceReg;
    _upvalueDescriptors = ctx.upvalueDescriptors;
    _upvalueIndices = ctx.upvalueIndices;
    _capturedVarRefRegs = ctx.capturedVarRefRegs;
  }

  /// Restores a mutable list's contents from a saved snapshot.
  void _restoreList<T>(List<T> target, List<T> saved) {
    target
      ..clear()
      ..addAll(saved);
  }

  /// Restores a mutable map's contents from a saved snapshot.
  void _restoreMap<K, V>(Map<K, V> target, Map<K, V> saved) {
    target
      ..clear()
      ..addAll(saved);
  }

  // ── Inner function compilation ──

  /// Shared logic for compiling an inner function (closure) body.
  ///
  /// Handles the common steps shared by [_compileFunctionDeclaration] and
  /// [_compileFunctionExpression]:
  /// 1. Reserve a placeholder in the function table
  /// 2. Pre-analyze captured variables (upvalues)
  /// 3. Promote/resolve captured variables for the enclosing function
  /// 4. Push a new compilation context
  /// 5. Register both positional AND named parameters
  /// 6. Compile the function body
  /// 7. Emit implicit RETURN_NULL, patch arg moves
  /// 8. Create the DarticFuncProto
  /// 9. Pop context and emit CLOSURE instruction
  ///
  /// Returns `(closureReg, innerFuncId)` so callers can handle their
  /// unique part (binding vs returning).
  (int closureReg, int innerFuncId) _compileInnerFunction(
    ir.FunctionNode fn,
    String? name,
  ) {
    final innerFuncId = _functions.length;

    // Reserve a placeholder in the function table.
    _functions.add(DarticFuncProto(
      funcId: innerFuncId,
      bytecode: DarticCompiler._haltBytecode,
      valueRegCount: 0,
      refRegCount: 0,
      paramCount: 0,
    ));

    // Step 1: Pre-analyze which outer variables the inner function captures.
    final capturedVars = _analyzeCapturedVars(fn, _scope);

    // Step 2: For each captured variable, ensure it's accessible from the
    // current function. Variables local to this function get promoted (boxed)
    // to the ref stack. Variables that are themselves upvalues in this function
    // need to be resolved as upvalues first (so the nested function can
    // capture them transitively).
    for (final varDecl in capturedVars) {
      if (_contextStack.isNotEmpty && _isUpvalueAccess(varDecl)) {
        _resolveUpvalue(varDecl);
      } else {
        _promoteToRefIfNeeded(varDecl);
      }
    }

    // Step 3: Save the enclosing function scope (need it for upvalue resolution).
    final outerScope = _scope;

    // Step 4: Compile the inner function.
    _pushContext();
    _currentReturnType = fn.returnType;

    // Create a new scope for the inner function. Its parent is the
    // outer scope so that upvalue resolution can walk up.
    _scope = Scope(
      valueAlloc: _valueAlloc,
      refAlloc: _refAlloc,
      parent: outerScope,
    );

    // Reserve 3 ref regs: ITA(0), FTA(1), this(2) -- Ch2 convention.
    _refAlloc.alloc(); // rsp+0: ITA
    _refAlloc.alloc(); // rsp+1: FTA
    _refAlloc.alloc(); // rsp+2: this/receiver

    // Register parameters.
    _registerParams(fn.positionalParameters);
    _registerParams(fn.namedParameters);

    // Compile function body.
    final body = fn.body;
    if (body != null) {
      _compileStatement(body);
    }

    // Safety net: emit implicit RETURN_NULL if no explicit return.
    _emitCloseUpvaluesIfNeeded();
    _emitter.emit(encodeABC(Op.returnNull, 0, 0, 0));

    _patchPendingArgMoves();

    final valRegCount = _valueAlloc.maxUsed;
    final refRegCount = _refAlloc.maxUsed;
    final upvalueDescs = List<UpvalueDescriptor>.of(_upvalueDescriptors);

    _functions[innerFuncId] = DarticFuncProto(
      funcId: innerFuncId,
      name: name ?? '<anonymous>',
      bytecode: _emitter.toUint32List(),
      valueRegCount: valRegCount,
      refRegCount: refRegCount,
      paramCount:
          fn.positionalParameters.length + fn.namedParameters.length,
      paramKinds: _buildParamKinds(
          fn.positionalParameters, fn.namedParameters),
      returnKind: _classifyReturnKind(fn.returnType),
      exceptionTable: List.of(_exceptionHandlers),
      icTable: List.of(_icEntries),
      upvalueDescriptors: upvalueDescs,
    );

    // Restore enclosing context.
    _popContext();

    // Emit CLOSURE instruction in the enclosing function.
    final closureReg = _allocRefReg();
    _emitter.emit(encodeABx(Op.closure, closureReg, innerFuncId));

    return (closureReg, innerFuncId);
  }

  /// Compiles a [FunctionDeclaration] as a closure.
  ///
  /// Delegates to [_compileInnerFunction] for the shared compilation logic,
  /// then binds the resulting closure to the declaration's variable.
  void _compileFunctionDeclaration(ir.FunctionDeclaration decl) {
    final (closureReg, _) =
        _compileInnerFunction(decl.function, decl.variable.name);

    // Bind the FunctionDeclaration's variable to the closure register.
    _scope.declareWithReg(decl.variable, StackKind.ref, closureReg);
  }

  /// Compiles a [FunctionExpression] (anonymous function / lambda) as a
  /// closure. Delegates to [_compileInnerFunction] for the shared compilation
  /// logic, then returns the closure as an expression result.
  (int, ResultLoc) _compileFunctionExpression(ir.FunctionExpression expr) {
    final (closureReg, _) = _compileInnerFunction(expr.function, null);
    return (closureReg, ResultLoc.ref);
  }

  // OPTIMIZATION: Reuses target function's existing funcProto directly in the
  // closure instead of creating a thunk wrapper. This works because CALL's
  // frame setup (extract funcProto -> push frame -> set vBase/rBase) is
  // identical to CALL_STATIC's frame setup for the same funcProto.
  //
  // INVARIANT: If CALL and CALL_STATIC frame setup ever diverge (e.g.,
  // generics ITA/FTA handling), a thunk wrapper must be generated instead.

  /// Compiles a [StaticTearOff]: wraps a top-level function reference as a
  /// [DarticClosure] so it can be used as a first-class value.
  (int, ResultLoc) _compileStaticTearOff(ir.StaticTearOff expr) {
    final funcId = _procToFuncId[expr.target.reference];
    if (funcId == null) {
      throw UnsupportedError(
        'StaticTearOff: unknown function ${expr.target.name.text}',
      );
    }
    final closureReg = _allocRefReg();
    _emitter.emit(encodeABx(Op.closure, closureReg, funcId));
    return (closureReg, ResultLoc.ref);
  }

  /// Compiles a [StaticTearOffConstant] (encountered inside a
  /// [ConstantExpression]): wraps a top-level function as a closure, same
  /// as [_compileStaticTearOff] but from a constant context.
  (int, ResultLoc) _compileStaticTearOffConstant(
    ir.StaticTearOffConstant constant,
  ) {
    final funcId = _procToFuncId[constant.target.reference];
    if (funcId == null) {
      throw UnsupportedError(
        'StaticTearOffConstant: unknown function '
        '${constant.target.name.text}',
      );
    }
    final closureReg = _allocRefReg();
    _emitter.emit(encodeABx(Op.closure, closureReg, funcId));
    return (closureReg, ResultLoc.ref);
  }

  // ── Captured variable analysis ──

  /// Pre-analyzes the function body to find all outer variables that are
  /// referenced (captured). Returns the set of VariableDeclarations that
  /// need to be captured as upvalues.
  Set<ir.VariableDeclaration> _analyzeCapturedVars(
    ir.FunctionNode fn,
    Scope outerScope,
  ) {
    final captured = <ir.VariableDeclaration>{};
    // Params of the inner function -- these are NOT upvalues.
    final localParams = <ir.VariableDeclaration>{
      ...fn.positionalParameters,
      ...fn.namedParameters,
    };

    fn.body?.accept(_CapturedVarVisitor(captured, localParams, outerScope));
    return captured;
  }

  /// Promotes a value-stack variable to a ref-stack (boxed) register so it
  /// can be shared via an upvalue cell.
  ///
  /// If the variable is already on the ref stack, this is a no-op.
  /// If the variable was already promoted, this is also a no-op.
  void _promoteToRefIfNeeded(ir.VariableDeclaration varDecl) {
    if (_capturedVarRefRegs.containsKey(varDecl)) return;

    final binding = _scope.lookup(varDecl);
    if (binding == null) return;

    if (binding.kind.isValue) {
      // Allocate a ref register and emit BOX instruction.
      final refReg = _allocRefReg();
      final boxOp = switch (binding.kind) {
        StackKind.doubleVal => Op.boxDouble,
        StackKind.boolVal   => Op.boxBool,
        _                   => Op.boxInt,
      };
      _emitter.emit(encodeABC(boxOp, refReg, binding.reg, 0));

      _capturedVarRefRegs[varDecl] = refReg;

      // Re-declare in scope as ref type so subsequent reads use the ref reg.
      _scope.redeclareAsRef(varDecl, refReg);
    } else {
      // Already on ref stack -- just record its register.
      _capturedVarRefRegs[varDecl] = binding.reg;
    }
  }

  // ── Upvalue resolution ──

  /// Resolves an upvalue for the current inner function being compiled.
  ///
  /// If [varDecl] is in the immediately enclosing function's scope, creates
  /// an isLocal=true upvalue descriptor. If it's in a more distant ancestor,
  /// creates an isLocal=false (transitive) descriptor.
  ///
  /// Returns the upvalue index for use with LOAD_UPVALUE/STORE_UPVALUE.
  int _resolveUpvalue(ir.VariableDeclaration varDecl) {
    // Check if we already have an upvalue for this variable.
    final existing = _upvalueIndices[varDecl];
    if (existing != null) return existing;

    // The enclosing context is the top of _contextStack.
    if (_contextStack.isNotEmpty) {
      final enclosingCtx = _contextStack.last;

      // First check if the variable is already an upvalue in the enclosing
      // function (transitive capture). This must be checked BEFORE the scope
      // lookup because scope.lookup() walks the entire parent chain and may
      // find the variable in a grandparent scope, incorrectly treating it as
      // a direct capture.
      final enclosingUpvalueIdx = enclosingCtx.upvalueIndices[varDecl];
      if (enclosingUpvalueIdx != null) {
        final idx = _upvalueDescriptors.length;
        _upvalueDescriptors.add(UpvalueDescriptor(
          isLocal: false,
          index: enclosingUpvalueIdx,
        ));
        _upvalueIndices[varDecl] = idx;
        return idx;
      }

      // Check if the variable is a local or captured variable in the
      // enclosing function's scope. We check capturedVarRefRegs first
      // (for value-type variables that were promoted/boxed), then the scope.
      if (enclosingCtx.capturedVarRefRegs.containsKey(varDecl)) {
        final refReg = enclosingCtx.capturedVarRefRegs[varDecl]!;
        final idx = _upvalueDescriptors.length;
        _upvalueDescriptors.add(UpvalueDescriptor(
          isLocal: true,
          index: refReg,
        ));
        _upvalueIndices[varDecl] = idx;
        return idx;
      }

      // Check if the variable is declared locally in the enclosing function's
      // scope (not inherited from a grandparent scope).
      final enclosingBinding = _findLocalBinding(
        enclosingCtx.scope,
        varDecl,
        _contextStack.length >= 2
            ? _contextStack[_contextStack.length - 2].scope
            : null,
      );
      if (enclosingBinding != null) {
        final idx = _upvalueDescriptors.length;
        _upvalueDescriptors.add(UpvalueDescriptor(
          isLocal: true,
          index: enclosingBinding.reg,
        ));
        _upvalueIndices[varDecl] = idx;
        return idx;
      }
    }

    throw StateError(
      'Cannot resolve upvalue for variable: ${varDecl.name}',
    );
  }

  /// Finds a [VarBinding] for [varDecl] in the scope chain starting from
  /// [scope], but stopping before [boundary] (exclusive). Returns null if
  /// not found within the bounded chain.
  VarBinding? _findLocalBinding(
    Scope scope,
    ir.VariableDeclaration varDecl,
    Scope? boundary,
  ) {
    Scope? s = scope;
    while (s != null && s != boundary) {
      if (s.containsLocal(varDecl)) return s.lookup(varDecl);
      s = s.parent;
    }
    return null;
  }
}

/// Saved compilation context for nested function compilation.
class _CompilationContext {
  _CompilationContext({
    required this.emitter,
    required this.valueAlloc,
    required this.refAlloc,
    required this.scope,
    required this.isEntryFunction,
    required this.currentReturnType,
    required this.pendingArgMoves,
    required this.labelBreakJumps,
    required this.exceptionHandlers,
    required this.icEntries,
    required this.catchExceptionReg,
    required this.catchStackTraceReg,
    required this.upvalueDescriptors,
    required this.upvalueIndices,
    required this.capturedVarRefRegs,
  });

  final BytecodeEmitter emitter;
  final RegisterAllocator valueAlloc;
  final RegisterAllocator refAlloc;
  final Scope scope;
  final bool isEntryFunction;
  final ir.DartType currentReturnType;
  final List<({int pc, int srcReg, int argIdx, ResultLoc loc})> pendingArgMoves;
  final Map<ir.LabeledStatement, List<int>> labelBreakJumps;
  final List<ExceptionHandler> exceptionHandlers;
  final List<ICEntry> icEntries;
  final int catchExceptionReg;
  final int catchStackTraceReg;
  final List<UpvalueDescriptor> upvalueDescriptors;
  final Map<ir.VariableDeclaration, int> upvalueIndices;
  final Map<ir.VariableDeclaration, int> capturedVarRefRegs;
}

/// AST visitor that collects references to outer-scope variables.
///
/// Used by [DarticCompiler._analyzeCapturedVars] to find which variables
/// from enclosing scopes are referenced by an inner function.
class _CapturedVarVisitor extends ir.RecursiveVisitor {
  _CapturedVarVisitor(this._captured, this._localParams, this._outerScope);

  final Set<ir.VariableDeclaration> _captured;
  final Set<ir.VariableDeclaration> _localParams;
  final Scope _outerScope;

  /// Variables declared locally within the inner function body.
  final Set<ir.VariableDeclaration> _localDecls = {};

  @override
  void visitVariableDeclaration(ir.VariableDeclaration node) {
    _localDecls.add(node);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitVariableGet(ir.VariableGet node) {
    _checkCaptured(node.variable);
    super.visitVariableGet(node);
  }

  @override
  void visitVariableSet(ir.VariableSet node) {
    _checkCaptured(node.variable);
    super.visitVariableSet(node);
  }

  void _checkCaptured(ir.VariableDeclaration varDecl) {
    // Skip if it's a parameter of the inner function or a local declaration.
    if (_localParams.contains(varDecl)) return;
    if (_localDecls.contains(varDecl)) return;

    // Check if it's defined in an outer scope.
    if (_outerScope.lookup(varDecl) != null) {
      _captured.add(varDecl);
    }
  }
}
