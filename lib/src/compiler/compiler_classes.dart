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
  ///
  /// Handles dependency ordering: if the superclass or implemented types have
  /// not been registered yet (e.g., anonymous mixin classes that appear later
  /// in the Kernel class list), they are registered recursively first.
  void _registerClass(ir.Class cls) {
    // Skip if already registered (avoids double registration from recursive
    // dependency resolution).
    if (_classToClassId.containsKey(cls)) return;

    // Guard against circular class dependencies in malformed Kernel input.
    if (!_registeringInProgress.add(cls)) {
      throw StateError('Circular class dependency detected: ${cls.name}');
    }

    // Ensure superclass is registered first (critical for anonymous mixin
    // classes that may appear after the classes that use them in the Kernel
    // class list).
    final superClass = cls.superclass;
    if (superClass != null &&
        !_classToClassId.containsKey(superClass) &&
        !_isPlatformLibrary(superClass.enclosingLibrary)) {
      _registerClass(superClass);
    }

    // Ensure implemented types (interfaces / mixin types) are registered.
    for (final implemented in cls.implementedTypes) {
      final implClass = implemented.classNode;
      if (!_classToClassId.containsKey(implClass) &&
          !_isPlatformLibrary(implClass.enclosingLibrary)) {
        _registerClass(implClass);
      }
    }

    _registeringInProgress.remove(cls);

    final classId = _classInfos.length;
    _classToClassId[cls] = classId;

    // Resolve superclass field counts for inherited field offset calculation.
    var inheritedRefFields = 0;
    var inheritedValFields = 0;
    var superClassId = -1;

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

    // Compute Dart 3 class modifier flags from Kernel Class node.
    var modifiers = ClassModifiers.none;
    if (cls.isSealed) modifiers |= ClassModifiers.sealed;
    if (cls.isBase) modifiers |= ClassModifiers.base;
    if (cls.isInterface) modifiers |= ClassModifiers.interface;
    if (cls.isFinal) modifiers |= ClassModifiers.final_;
    if (cls.isMixinClass) modifiers |= ClassModifiers.mixin_;
    if (cls.isAbstract) modifiers |= ClassModifiers.abstract_;

    final classInfo = DarticClassInfo(
      classId: classId,
      name: cls.name,
      superClassId: superClassId,
      refFieldCount: refOffset, // Total including inherited
      valueFieldCount: valOffset, // Total including inherited
      typeParamCount: cls.typeParameters.length,
      modifiers: modifiers,
    );

    // Build supertypeIds: self + transitive closure of all supertypes.
    // Includes superclass chain AND implementedTypes (interfaces).
    // Uses _typeClassIdLookup as fallback for platform types (core types).
    classInfo.supertypeIds.add(classId);
    if (superClassId >= 0) {
      classInfo.supertypeIds.addAll(_classInfos[superClassId].supertypeIds);
    } else if (superClass != null) {
      // Superclass is a platform class (e.g., Object). Check _typeClassIdLookup
      // to include core type classIds in supertypeIds for runtime subtype checks.
      final coreSuperCid = _typeClassIdLookup[superClass];
      if (coreSuperCid != null) {
        classInfo.supertypeIds.addAll(_classInfos[coreSuperCid].supertypeIds);
      }
    }
    for (final implemented in cls.implementedTypes) {
      final implClassId = _classToClassId[implemented.classNode]
          ?? _typeClassIdLookup[implemented.classNode];
      if (implClassId != null) {
        // Add the interface itself and its transitive supertypeIds.
        classInfo.supertypeIds.addAll(_classInfos[implClassId].supertypeIds);
      }
    }

    // Register constructors -> assign funcIds.
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

    // Register instance methods -> assign funcIds.
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

    // Track enclosing class type params for generic type resolution.
    _currentEnclosingClass = ctor.enclosingClass;
    _currentClassTypeParams = ctor.enclosingClass.typeParameters;

    _resetFunctionState(
      positionalParams: fn.positionalParameters,
      namedParams: fn.namedParameters,
    );

    // Compile implicit field initializers: fields with initializer expressions
    // that are NOT explicitly listed as FieldInitializer in the constructor.
    // In Kernel, `int x = 10;` on a field declaration may not generate an
    // explicit FieldInitializer in the constructor's initializer list. These
    // must be compiled before the explicit initializers.
    final explicitFields = <ir.Field>{};
    for (final init in ctor.initializers) {
      if (init is ir.FieldInitializer) explicitFields.add(init.field);
    }
    final enclosingClass = ctor.enclosingClass;
    for (final field in enclosingClass.fields) {
      if (field.isStatic) continue;
      if (explicitFields.contains(field)) continue;
      if (field.initializer == null) continue;
      // Compile the field-level initializer directly.
      _compileFieldInit(field, field.initializer!);
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

    final className = ctor.enclosingClass.name;
    final ctorName = ctor.name.text;
    final displayName =
        ctorName.isEmpty ? '$className.<init>' : '$className.$ctorName';

    _functions[funcId] = DarticFuncProto(
      funcId: funcId,
      name: displayName,
      bytecode: _emitter.toUint32List(),
      valueRegCount: _valueAlloc.maxUsed,
      refRegCount: _refAlloc.maxUsed,
      paramCount: fn.positionalParameters.length + fn.namedParameters.length,
      icTable: List.of(_icEntries),
    );
    _currentEnclosingClass = null;
    _currentClassTypeParams = null;
  }

  /// Compiles a [FieldInitializer] within a constructor.
  ///
  /// Emits SET_FIELD_REF or SET_FIELD_VAL to write the initializer value
  /// into the appropriate field of `this` (at rsp+2).
  void _compileFieldInitializer(ir.FieldInitializer init) {
    _compileFieldInit(init.field, init.value);
  }

  /// Compiles a field initialization for [field] with the given [value]
  /// expression.
  ///
  /// Shared by explicit [FieldInitializer] and implicit field-level
  /// initializers (e.g., `int x = 10;` on field declarations).
  void _compileFieldInit(ir.Field field, ir.Expression value) {
    final cls = field.enclosingClass!;
    final layouts = _instanceFieldLayouts[cls];
    if (layouts == null) {
      throw StateError('Field layouts not found for class ${cls.name}');
    }
    final layout = layouts[field.getterReference];
    if (layout == null) {
      throw StateError('Field layout not found for ${field.name}');
    }

    final (valReg, valLoc) = _compileExpression(value);
    const thisReg = 2; // rsp+2 on the ref stack

    if (layout.kind.isValue) {
      int srcReg = valReg;
      if (valLoc == ResultLoc.ref) {
        srcReg = _allocValueReg();
        final unboxOp = layout.kind == StackKind.doubleVal
            ? Op.unboxDouble
            : Op.unboxInt;
        _emitter.emit(encodeABC(unboxOp, srcReg, valReg, 0));
      }
      _emitter.emit(encodeABC(Op.setFieldVal, thisReg, srcReg, layout.offset));
    } else {
      int srcReg = valReg;
      if (valLoc == ResultLoc.value) {
        srcReg = _emitBoxToRef(valReg, _inferExprType(value));
      }
      _emitter.emit(encodeABC(Op.setFieldRef, thisReg, srcReg, layout.offset));
    }
  }

  /// Compiles a [SuperInitializer] within a constructor.
  ///
  /// Emits CALL_SUPER to the parent constructor, passing `this` (rsp+2)
  /// and the super arguments.
  void _compileSuperInitializer(ir.SuperInitializer init) {
    final funcId = _constructorToFuncId[init.targetReference];
    if (funcId == null) {
      // Super constructor is in a platform class (e.g., Object()).
      // Platform constructors are no-ops for our purposes -- skip.
      return;
    }

    final argTemps = _compileInitializerArgs(
      init.arguments,
      init.target.function,
    );

    _emitThisPassthrough();

    final dummyResult = _allocRefReg();
    _emitArgMovesAndCall(argTemps, Op.callSuper, dummyResult, funcId);
  }

  /// Compiles a [RedirectingInitializer] within a constructor.
  ///
  /// Emits CALL_STATIC to the target constructor, passing `this` (rsp+2)
  /// and the redirecting arguments.
  void _compileRedirectingInitializer(ir.RedirectingInitializer init) {
    final funcId = _constructorToFuncId[init.targetReference];
    if (funcId == null) {
      throw UnsupportedError(
        'Unknown redirecting constructor target: '
        '${init.target.enclosingClass.name}.${init.target.name.text}',
      );
    }

    final argTemps = _compileInitializerArgs(
      init.arguments,
      init.target.function,
    );

    _emitThisPassthrough();

    final dummyResult = _allocRefReg();
    _emitArgMovesAndCall(argTemps, Op.callStatic, dummyResult, funcId);
  }

  /// Compiles arguments for a constructor initializer call (super or
  /// redirecting). Handles positional args with boxing, default values
  /// for missing optionals, and named arguments.
  List<(int, ResultLoc)> _compileInitializerArgs(
    ir.Arguments arguments,
    ir.FunctionNode targetFn,
  ) {
    final targetParams = targetFn.positionalParameters;
    final targetNamedParams = targetFn.namedParameters;
    final argTemps = <(int, ResultLoc)>[];

    // Compile positional arguments.
    for (var i = 0; i < arguments.positional.length; i++) {
      var (argReg, argLoc) = _compileExpression(arguments.positional[i]);
      if (i < targetParams.length) {
        final paramKind = _classifyStackKind(targetParams[i].type);
        if (paramKind == StackKind.ref && argLoc == ResultLoc.value) {
          argReg = _emitBoxToRef(
            argReg,
            _inferExprType(arguments.positional[i]),
          );
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
    for (var i = arguments.positional.length; i < targetParams.length; i++) {
      argTemps.add(_compileDefaultValue(targetParams[i]));
    }

    // Handle named arguments.
    if (targetNamedParams.isNotEmpty) {
      _compileNamedArgsFromParams(
        targetNamedParams,
        arguments.named,
        argTemps,
      );
    }

    return argTemps;
  }

  /// Emits a pending MOVE to pass `this` (rsp+2) to the callee's `this`
  /// slot (argIdx 2). Used by super and redirecting initializer calls.
  void _emitThisPassthrough() {
    const thisReg = 2;
    final thisMovePC = _emitter.emitPlaceholder();
    _pendingArgMoves.add(
      (pc: thisMovePC, srcReg: thisReg, argIdx: 2, loc: ResultLoc.ref),
    );
  }
}
