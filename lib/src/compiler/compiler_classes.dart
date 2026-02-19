part of 'compiler.dart';

/// Class registration and constructor compilation for [DarticCompiler].
extension on DarticCompiler {
  // ── Class registration (Pass 1c) ──

  /// Registers a Kernel [Class] node: assigns classId, computes field layout,
  /// assigns funcIds to constructors and instance methods.
  ///
  /// Inheritance: child class field offsets start after parent's field counts.
  /// superClassId is resolved if the parent is a user-defined class (not a
  /// platform class like Object).
  void _registerClass(ir.Class cls) {
    final classId = _classInfos.length;
    _classToClassId[cls] = classId;

    // Resolve superclass field counts for inherited field offset calculation.
    var inheritedRefFields = 0;
    var inheritedValFields = 0;
    var superClassId = -1;

    final superClass = cls.superclass;
    if (superClass != null && _classToClassId.containsKey(superClass)) {
      superClassId = _classToClassId[superClass]!;
      final superInfo = _classInfos[superClassId];
      inheritedRefFields = superInfo.refFieldCount;
      inheritedValFields = superInfo.valueFieldCount;
    }

    // Compute field layout: offsets start after inherited fields.
    var refOffset = inheritedRefFields;
    var valOffset = inheritedValFields;
    final fieldLayouts = <ir.Reference, FieldLayout>{};

    for (final field in cls.fields) {
      if (field.isStatic) continue;
      final kind = _classifyStackKind(field.type);
      final offset = kind.isValue ? valOffset++ : refOffset++;
      final layout = FieldLayout(offset: offset, kind: kind);
      fieldLayouts[field.getterReference] = layout;
      final setterRef = field.setterReference;
      if (setterRef != null) {
        fieldLayouts[setterRef] = layout;
      }
    }

    // Also include parent class field layouts so that child class code can
    // access inherited fields via their parent-defined offsets.
    if (superClass != null) {
      final parentLayouts = _instanceFieldLayouts[superClass];
      if (parentLayouts != null) {
        for (final entry in parentLayouts.entries) {
          fieldLayouts.putIfAbsent(entry.key, () => entry.value);
        }
      }
    }
    _instanceFieldLayouts[cls] = fieldLayouts;

    final classInfo = DarticClassInfo(
      classId: classId,
      name: cls.name,
      superClassId: superClassId,
      refFieldCount: refOffset, // Total including inherited
      valueFieldCount: valOffset, // Total including inherited
    );

    // Build supertypeIds: self + transitive closure of parent's supertypeIds.
    classInfo.supertypeIds.add(classId);
    if (superClassId >= 0) {
      classInfo.supertypeIds.addAll(_classInfos[superClassId].supertypeIds);
    }

    // Register constructors → assign funcIds.
    for (final ctor in cls.constructors) {
      final funcId = _functions.length;
      _constructorToFuncId[ctor.reference] = funcId;
      _functions.add(DarticFuncProto(
        funcId: funcId,
        bytecode: DarticCompiler._haltBytecode,
        valueRegCount: 0,
        refRegCount: 0,
        paramCount: 0,
      ));
    }

    // Register instance methods → assign funcIds.
    for (final proc in cls.procedures) {
      if (proc.isStatic) continue;
      final funcId = _functions.length;
      _procToFuncId[proc.reference] = funcId;
      _functions.add(DarticFuncProto(
        funcId: funcId,
        bytecode: DarticCompiler._haltBytecode,
        valueRegCount: 0,
        refRegCount: 0,
        paramCount: 0,
      ));

      // Register method in the class info method table.
      // Setters use "name=" convention to distinguish from getters/methods.
      final methodName = proc.isSetter
          ? '${proc.name.text}='
          : proc.name.text;
      final nameIdx = _constantPool.addName(methodName);
      classInfo.methods[nameIdx] = _functions.last;
    }

    // Flatten parent methods into child method table (compile-time flattening).
    // putIfAbsent preserves child overrides registered above.
    if (superClassId >= 0) {
      final superInfo = _classInfos[superClassId];
      for (final entry in superInfo.methods.entries) {
        classInfo.methods.putIfAbsent(entry.key, () => entry.value);
      }
    }

    _classInfos.add(classInfo);
  }

  // ── Constructor compilation (Pass 2c) ──

  /// Compiles a Kernel [Constructor] into a [DarticFuncProto].
  ///
  /// Constructor calling convention:
  /// - `this` (the newly allocated object) is at rsp+2 on the ref stack
  /// - Parameters start at their normal positions (value: v0+, ref: r3+)
  /// - The constructor returns void (RETURN_NULL)
  void _compileConstructor(ir.Constructor ctor) {
    final funcId = _constructorToFuncId[ctor.reference]!;
    final fn = ctor.function;

    // Reset per-function state.
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

    // Create function scope.
    _scope = Scope(valueAlloc: _valueAlloc, refAlloc: _refAlloc);

    // Reserve 3 ref regs: ITA(0), FTA(1), this(2) — Ch2 convention.
    _refAlloc.alloc(); // rsp+0: ITA
    _refAlloc.alloc(); // rsp+1: FTA
    _refAlloc.alloc(); // rsp+2: this/receiver

    // Register parameters.
    for (final param in fn.positionalParameters) {
      final kind = _classifyStackKind(param.type);
      final reg = kind.isValue ? _valueAlloc.alloc() : _refAlloc.alloc();
      _scope.declareWithReg(param, kind, reg);
    }
    for (final param in fn.namedParameters) {
      final kind = _classifyStackKind(param.type);
      final reg = kind.isValue ? _valueAlloc.alloc() : _refAlloc.alloc();
      _scope.declareWithReg(param, kind, reg);
    }

    // Process initializers in declaration order.
    for (final init in ctor.initializers) {
      if (init is ir.FieldInitializer) {
        _compileFieldInitializer(init);
      } else if (init is ir.SuperInitializer) {
        _compileSuperInitializer(init);
      } else if (init is ir.RedirectingInitializer) {
        _compileRedirectingInitializer(init);
      } else if (init is ir.LocalInitializer) {
        _compileVariableDeclaration(init.variable);
      } else if (init is ir.AssertInitializer) {
        // Skip asserts for now.
      }
    }

    // Compile constructor body.
    final body = fn.body;
    if (body != null) {
      _compileStatement(body);
    }

    // Safety net: RETURN_NULL.
    _emitCloseUpvaluesIfNeeded();
    _emitter.emit(encodeABC(Op.returnNull, 0, 0, 0));

    _patchPendingArgMoves();

    final valRegCount = _valueAlloc.maxUsed;
    final refRegCount = _refAlloc.maxUsed;

    // Count parameters (positional + named).
    final paramCount =
        fn.positionalParameters.length + fn.namedParameters.length;

    // Build the function prototype and replace the placeholder.
    final className = ctor.enclosingClass.name;
    final ctorName = ctor.name.text;
    final displayName =
        ctorName.isEmpty ? '$className.<init>' : '$className.$ctorName';

    _functions[funcId] = DarticFuncProto(
      funcId: funcId,
      name: displayName,
      bytecode: _emitter.toUint32List(),
      valueRegCount: valRegCount,
      refRegCount: refRegCount,
      paramCount: paramCount,
      icTable: List.of(_icEntries),
    );
  }

  /// Compiles a [FieldInitializer] within a constructor.
  ///
  /// Emits SET_FIELD_REF or SET_FIELD_VAL to write the initializer value
  /// into the appropriate field of `this` (at rsp+2).
  void _compileFieldInitializer(ir.FieldInitializer init) {
    final field = init.field;
    final cls = field.enclosingClass!;
    final layouts = _instanceFieldLayouts[cls];
    if (layouts == null) {
      throw StateError('Field layouts not found for class ${cls.name}');
    }
    final layout = layouts[field.getterReference];
    if (layout == null) {
      throw StateError('Field layout not found for ${field.name}');
    }

    // Compile the initializer value expression.
    final (valReg, valLoc) = _compileExpression(init.value);

    // `this` is at rsp+2 (ref stack).
    const thisReg = 2;

    if (layout.kind.isValue) {
      // Value field: SET_FIELD_VAL A=receiver(ref), B=value(val), C=offset.
      int srcReg = valReg;
      if (valLoc == ResultLoc.ref) {
        // Unbox ref→value if the initializer is on the ref stack.
        srcReg = _allocValueReg();
        final unboxOp = layout.kind == StackKind.doubleVal
            ? Op.unboxDouble
            : Op.unboxInt;
        _emitter.emit(encodeABC(unboxOp, srcReg, valReg, 0));
      }
      _emitter.emit(encodeABC(Op.setFieldVal, thisReg, srcReg, layout.offset));
    } else {
      // Ref field: SET_FIELD_REF A=receiver(ref), B=value(ref), C=offset.
      int srcReg = valReg;
      if (valLoc == ResultLoc.value) {
        srcReg =
            _emitBoxToRef(valReg, _inferExprType(init.value));
      }
      _emitter.emit(encodeABC(Op.setFieldRef, thisReg, srcReg, layout.offset));
    }
  }

  /// Compiles a [SuperInitializer] within a constructor.
  ///
  /// Emits CALL_SUPER to the parent constructor, passing `this` (rsp+2)
  /// and the super arguments. Uses CALL_SUPER (ABx) since the target
  /// constructor funcId is known at compile time.
  void _compileSuperInitializer(ir.SuperInitializer init) {
    final targetRef = init.targetReference;
    final funcId = _constructorToFuncId[targetRef];
    if (funcId == null) {
      // Super constructor is in a platform class (e.g., Object()).
      // Platform constructors are no-ops for our purposes — skip.
      return;
    }

    final targetParams = init.target.function.positionalParameters;
    final targetNamedParams = init.target.function.namedParameters;
    final argTemps = <(int, ResultLoc)>[];

    // Compile positional arguments.
    for (var i = 0; i < init.arguments.positional.length; i++) {
      var (argReg, argLoc) = _compileExpression(init.arguments.positional[i]);
      if (i < targetParams.length) {
        final paramKind = _classifyStackKind(targetParams[i].type);
        if (paramKind == StackKind.ref && argLoc == ResultLoc.value) {
          argReg = _emitBoxToRef(
            argReg,
            _inferExprType(init.arguments.positional[i]),
          );
          argLoc = ResultLoc.ref;
        }
      }
      argTemps.add((argReg, argLoc));
    }

    // Fill missing optional positional args with defaults.
    for (var i = init.arguments.positional.length;
        i < targetParams.length;
        i++) {
      argTemps.add(_compileDefaultValue(targetParams[i]));
    }

    // Handle named arguments.
    if (targetNamedParams.isNotEmpty) {
      _compileNamedArgsFromParams(
        targetNamedParams,
        init.arguments.named,
        argTemps,
      );
    }

    // Pass `this` (rsp+2) to the super constructor's `this` slot (argIdx 2).
    const thisReg = 2;
    final thisMovePC = _emitter.emitPlaceholder();
    _pendingArgMoves.add(
      (pc: thisMovePC, srcReg: thisReg, argIdx: 2, loc: ResultLoc.ref),
    );

    // Emit arg moves + CALL_SUPER. Super constructor is compile-time resolved.
    final dummyResult = _allocRefReg();
    _emitArgMovesAndCall(argTemps, Op.callSuper, dummyResult, funcId);
  }

  /// Compiles a [RedirectingInitializer] within a constructor.
  ///
  /// Emits CALL_STATIC to the target constructor, passing `this` (rsp+2)
  /// and the redirecting arguments.
  void _compileRedirectingInitializer(ir.RedirectingInitializer init) {
    final targetRef = init.targetReference;
    final funcId = _constructorToFuncId[targetRef];
    if (funcId == null) {
      throw UnsupportedError(
        'Unknown redirecting constructor target: '
        '${init.target.enclosingClass.name}.${init.target.name.text}',
      );
    }

    final targetParams = init.target.function.positionalParameters;
    final targetNamedParams = init.target.function.namedParameters;
    final argTemps = <(int, ResultLoc)>[];

    // Compile positional arguments.
    for (var i = 0; i < init.arguments.positional.length; i++) {
      var (argReg, argLoc) = _compileExpression(init.arguments.positional[i]);
      if (i < targetParams.length) {
        final paramKind = _classifyStackKind(targetParams[i].type);
        if (paramKind == StackKind.ref && argLoc == ResultLoc.value) {
          argReg = _emitBoxToRef(
            argReg,
            _inferExprType(init.arguments.positional[i]),
          );
          argLoc = ResultLoc.ref;
        }
      }
      argTemps.add((argReg, argLoc));
    }

    // Fill missing optional positional args with defaults.
    for (var i = init.arguments.positional.length;
        i < targetParams.length;
        i++) {
      argTemps.add(_compileDefaultValue(targetParams[i]));
    }

    // Handle named arguments.
    if (targetNamedParams.isNotEmpty) {
      _compileNamedArgsFromParams(
        targetNamedParams,
        init.arguments.named,
        argTemps,
      );
    }

    // Pass `this` (rsp+2) to the target constructor's `this` slot (argIdx 2).
    const thisReg = 2;
    final thisMovePC = _emitter.emitPlaceholder();
    _pendingArgMoves.add(
      (pc: thisMovePC, srcReg: thisReg, argIdx: 2, loc: ResultLoc.ref),
    );

    // Emit arg moves + CALL_STATIC. Constructor returns void.
    final dummyResult = _allocRefReg();
    _emitArgMovesAndCall(argTemps, Op.callStatic, dummyResult, funcId);
  }
}
