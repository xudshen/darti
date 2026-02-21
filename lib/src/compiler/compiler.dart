import 'dart:typed_data';

import 'package:kernel/ast.dart' as ir;
import 'package:kernel/core_types.dart' show CoreTypes;
import 'package:kernel/type_algebra.dart' as type_algebra;

import '../bytecode/constant_pool.dart';
import '../bytecode/encoding.dart';
import '../bytecode/module.dart';
import '../bytecode/opcodes.dart';
import '../runtime/class_info.dart';
import 'bytecode_emitter.dart';
import 'register_allocator.dart';
import 'scope.dart';
import 'type_converter.dart';
import 'type_template.dart';

part 'compiler_classes.dart';
part 'compiler_closures.dart';
part 'compiler_expressions.dart';
part 'compiler_statements.dart';
part 'compiler_types.dart';

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

  // ── Host binding state ──

  /// Binding name table for CALL_HOST instructions.
  /// Each entry maps a local binding index (Bx) to a symbol name + argCount.
  final List<BindingEntry> _bindingNames = [];

  /// Maps symbol names to their binding index in [_bindingNames].
  final Map<String, int> _bindingNameToIndex = {};

  // ── Class compilation state ──

  /// Class info table — indexed by classId. Built during Pass 1c.
  final List<DarticClassInfo> _classInfos = [];

  /// Maps Kernel Class nodes to classIds.
  final Map<ir.Class, int> _classToClassId = {};

  /// Classes currently being registered (cycle detection for malformed input).
  final Set<ir.Class> _registeringInProgress = {};

  /// Maps Kernel Constructor references to funcIds.
  final Map<ir.Reference, int> _constructorToFuncId = {};

  /// Per-class field layouts: maps field getter reference to FieldLayout.
  /// Used by SET_FIELD/GET_FIELD compilation to determine offset and kind.
  final Map<ir.Class, Map<ir.Reference, FieldLayout>> _instanceFieldLayouts =
      {};

  // ── Per-function compilation state ──
  // Reset in _compileProcedure for each function.

  late BytecodeEmitter _emitter;
  late RegisterAllocator _valueAlloc;
  late RegisterAllocator _refAlloc;
  late Scope _scope;
  bool _isEntryFunction = false;
  ir.DartType _currentReturnType = const ir.VoidType();

  /// The async marker of the current function being compiled.
  /// Used by [_compileReturnStatement] to emit ASYNC_RETURN instead of RETURN.
  ir.AsyncMarker _currentAsyncMarker = ir.AsyncMarker.Sync;

  /// The class currently being compiled. Null for top-level functions.
  ir.Class? _currentEnclosingClass;

  /// Type parameters of the enclosing class (for resolving TypeParameterType
  /// references like `T` in `is T` checks within generic class methods).
  /// Null when compiling top-level or static functions.
  List<ir.TypeParameter>? _currentClassTypeParams;

  /// Type parameters of the current function/method being compiled (for
  /// resolving function-level TypeParameterType references like `T` in
  /// `bool check<T>(Object o) => o is T`). Null when the function is
  /// not generic.
  List<ir.TypeParameter>? _currentFunctionTypeParams;

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

  /// Maps LabeledStatement -> list of JUMP placeholder PCs that need to be
  /// backpatched to the label's end when the LabeledStatement finishes.
  final Map<ir.LabeledStatement, List<int>> _labelBreakJumps = {};

  // Note: CFE represents all break/continue as LabeledStatement+BreakStatement
  // pairs, so separate continueTargets/breakTargets maps are not needed.
  // ContinueSwitchStatement (fall-through) is not yet supported (Phase 3+).

  /// Exception handler table being built for the current function.
  final List<ExceptionHandler> _exceptionHandlers = [];

  /// Inline cache entries being built for the current function.
  /// Each CALL_VIRTUAL site adds one ICEntry.
  final List<ICEntry> _icEntries = [];

  /// Maps catch Rethrow -> the exception/stackTrace register pair
  /// for the innermost catch clause.
  int _catchExceptionReg = -1;
  int _catchStackTraceReg = -1;

  // ── Closure compilation state ──

  /// Upvalue descriptors being built for the current inner function.
  /// Populated during inner function compilation when a variable lookup
  /// crosses a function boundary.
  List<UpvalueDescriptor> _upvalueDescriptors = [];

  /// Maps a captured VariableDeclaration to its upvalue index within the
  /// current inner function's upvalue table.
  Map<ir.VariableDeclaration, int> _upvalueIndices = {};

  /// Stack of saved compilation contexts. Each entry saves the state of
  /// the enclosing function being compiled when we enter a nested function.
  final List<_CompilationContext> _contextStack = [];

  /// Maps variables that are captured by inner closures to their ref-stack
  /// register in the enclosing function. When a value-type variable is
  /// captured, it is "promoted" (boxed) to the ref stack, and all subsequent
  /// reads/writes in the enclosing function use this ref register.
  Map<ir.VariableDeclaration, int> _capturedVarRefRegs = {};

  // ── Core types (lazily initialized) ──

  late final CoreTypes _coreTypes = CoreTypes(_component);

  // ── Visitor delegates ──

  late final _ExprCompileVisitor _exprVisitor = _ExprCompileVisitor(this);
  late final _StmtCompileVisitor _stmtVisitor = _StmtCompileVisitor(this);
  late final _ConstantCompileVisitor _constantVisitor =
      _ConstantCompileVisitor(this);
  late final _InitializerCompileVisitor _initializerVisitor =
      _InitializerCompileVisitor(this);
  late final _ExprTypeInferVisitor _typeInferVisitor =
      _ExprTypeInferVisitor(this);

  /// Core type classIds — populated by [_registerCoreTypes].
  CoreTypeIds? _coreTypeIds;

  /// Combined classId lookup for type operations (core + user classes).
  /// Used by `dartTypeToTemplate` to produce correct TypeTemplates.
  /// Separate from `_classToClassId` to avoid polluting compiler decisions
  /// (e.g., EqualsCall dispatch, constructor resolution).
  final Map<ir.Class, int> _typeClassIdLookup = {};

  /// Compiles the component and returns a [DarticModule].
  ///
  /// Two-pass strategy:
  /// 1. Collect all user procedures -> assign funcIds
  /// 2. Compile each procedure's body -> emit bytecode
  DarticModule compile() {
    // Pass 1a: assign funcIds to all user-defined procedures.
    for (final lib in _component.libraries) {
      if (_isPlatformLibrary(lib)) continue;
      for (final proc in lib.procedures) {
        _reserveProcFuncId(proc);
      }
      for (final cls in lib.classes) {
        for (final proc in cls.procedures) {
          if (!proc.isStatic) continue;
          // Skip if already registered (instance methods are registered in
          // Pass 1c, but static ones need early registration like top-level).
          if (_procToFuncId.containsKey(proc.reference)) continue;
          _reserveProcFuncId(proc);
        }
      }
    }

    // Pass 1b: assign global indices to top-level and static class fields.
    for (final lib in _component.libraries) {
      if (_isPlatformLibrary(lib)) continue;
      for (final field in lib.fields) {
        _registerGlobalField(field);
      }
      for (final cls in lib.classes) {
        for (final field in cls.fields) {
          if (!field.isStatic) continue;
          _registerGlobalField(field);
        }
      }
    }

    // Pass 1c-pre: register core types as virtual classes.
    // These get classIds 0-5 before any user-defined classes.
    _registerCoreTypes();

    // Pass 1c: register classes — assign classIds, compute field layouts,
    // assign funcIds to constructors and instance methods.
    // NOTE: Relies on Kernel CFE emitting classes in dependency order within
    // each library (superclasses and interfaces before their subtypes).
    for (final lib in _component.libraries) {
      if (_isPlatformLibrary(lib)) continue;
      for (final cls in lib.classes) {
        _registerClass(cls);
      }
    }

    // Merge user class IDs into the type lookup for dartTypeToTemplate.
    _typeClassIdLookup.addAll(_classToClassId);

    // Pass 1d: populate SuperTypeMap entries for generic subtype checking.
    // buildSuperTypeEntries uses _typeClassIdLookup (core + user classes) to
    // resolve supertype classIds for both platform and user-defined types.
    for (final lib in _component.libraries) {
      if (_isPlatformLibrary(lib)) continue;
      for (final cls in lib.classes) {
        final classId = _classToClassId[cls]!;
        final entries = buildSuperTypeEntries(cls, _typeClassIdLookup);
        for (final entry in entries) {
          _classInfos[classId].superTypeArgs[entry.superClassId] =
              entry.typeArgMapping;
        }
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

    // Pass 2a: compile each top-level procedure and static class procedures.
    for (final lib in _component.libraries) {
      if (_isPlatformLibrary(lib)) continue;
      for (final proc in lib.procedures) {
        _compileProcedure(proc);
      }
      for (final cls in lib.classes) {
        for (final proc in cls.procedures) {
          if (!proc.isStatic) continue;
          _compileProcedure(proc);
        }
      }
    }

    // Pass 2b: compile global initializers.
    for (final lib in _component.libraries) {
      if (_isPlatformLibrary(lib)) continue;
      for (final field in lib.fields) {
        _compileFieldInitializerIfPresent(field);
      }
      for (final cls in lib.classes) {
        for (final field in cls.fields) {
          if (!field.isStatic) continue;
          _compileFieldInitializerIfPresent(field);
        }
      }
    }

    // Pass 2c: compile class members (constructors and instance methods).
    for (final lib in _component.libraries) {
      if (_isPlatformLibrary(lib)) continue;
      for (final cls in lib.classes) {
        for (final ctor in cls.constructors) {
          _compileConstructor(ctor);
        }
        for (final proc in cls.procedures) {
          if (proc.isStatic) continue;
          // Skip abstract methods — they have no body and serve only as
          // interface contracts. Their funcIds are registered in Pass 1c
          // for method table resolution, but no bytecode is generated.
          if (proc.isAbstract) continue;
          _compileProcedure(proc);
        }
      }
    }

    // Post-compilation: refresh class method tables with compiled FuncProtos.
    // Pass 1c stored placeholder FuncProtos; now that Pass 2c has compiled them,
    // update the method table references to point to the real FuncProtos.
    for (final classInfo in _classInfos) {
      for (final nameIdx in classInfo.methods.keys.toList()) {
        final placeholder = classInfo.methods[nameIdx]!;
        classInfo.methods[nameIdx] = _functions[placeholder.funcId];
      }
    }

    return DarticModule(
      functions: _functions,
      constantPool: _constantPool,
      entryFuncId: _entryFuncId,
      globalCount: _globalCount,
      globalInitializerIds: _globalInitializerIds,
      classes: _classInfos,
      coreTypeIds: _coreTypeIds,
      bindingNames: _bindingNames,
    );
  }

  // ── Core type registration ──

  /// Registers core platform types (int, double, String, bool, Object, num)
  /// as virtual class entries in the class table.
  ///
  /// These get the first classIds (before any user-defined classes) so that
  /// `dartTypeToTemplate` can produce correct `InterfaceTypeTemplate` classIds
  /// for type checks and casts.
  ///
  /// Core types are added to [_typeClassIdLookup] (for type conversion) but
  /// NOT to [_classToClassId] (which controls compiler decisions like equality
  /// dispatch and constructor resolution).
  void _registerCoreTypes() {
    int register(ir.Class cls, String name, {int superClassId = -1}) {
      final classId = _classInfos.length;
      // Only add to the type-operation lookup, NOT _classToClassId.
      _typeClassIdLookup[cls] = classId;
      _classInfos.add(DarticClassInfo(
        classId: classId,
        name: name,
        superClassId: superClassId,
        refFieldCount: 0,
        valueFieldCount: 0,
      ));
      return classId;
    }

    final ct = _coreTypes;

    final objectCid = register(ct.objectClass, 'Object');
    final numCid = register(ct.numClass, 'num', superClassId: objectCid);
    final intCid = register(ct.intClass, 'int', superClassId: numCid);
    final doubleCid = register(ct.doubleClass, 'double', superClassId: numCid);
    final stringCid = register(ct.stringClass, 'String', superClassId: objectCid);
    final boolCid = register(ct.boolClass, 'bool', superClassId: objectCid);

    // Set up supertype closures (transitive supertypeIds).
    _classInfos[objectCid].supertypeIds.add(objectCid);
    _classInfos[numCid].supertypeIds.addAll({numCid, objectCid});
    _classInfos[intCid].supertypeIds.addAll({intCid, numCid, objectCid});
    _classInfos[doubleCid].supertypeIds.addAll({doubleCid, numCid, objectCid});
    _classInfos[stringCid].supertypeIds.addAll({stringCid, objectCid});
    _classInfos[boolCid].supertypeIds.addAll({boolCid, objectCid});

    _coreTypeIds = CoreTypeIds(
      intId: intCid,
      doubleId: doubleCid,
      stringId: stringCid,
      boolId: boolCid,
      objectId: objectCid,
      numId: numCid,
    );
  }

  // ── Per-function state management ──

  /// Resets all per-function compilation state and creates a fresh scope.
  ///
  /// Called at the start of compiling each procedure, constructor, or
  /// global initializer. Reserves the 3 Ch2-convention ref registers
  /// (ITA, FTA, this) and registers all function parameters.
  void _resetFunctionState({
    bool isEntry = false,
    ir.DartType returnType = const ir.VoidType(),
    List<ir.VariableDeclaration> positionalParams = const [],
    List<ir.VariableDeclaration> namedParams = const [],
  }) {
    _emitter = BytecodeEmitter();
    _valueAlloc = RegisterAllocator();
    _refAlloc = RegisterAllocator();
    _isEntryFunction = isEntry;
    _currentReturnType = returnType;
    _currentAsyncMarker = ir.AsyncMarker.Sync;
    _pendingArgMoves.clear();
    _labelBreakJumps.clear();
    _exceptionHandlers.clear();
    _icEntries.clear();
    _catchExceptionReg = -1;
    _catchStackTraceReg = -1;

    _scope = Scope(valueAlloc: _valueAlloc, refAlloc: _refAlloc);

    // Reserve 3 ref regs: ITA(0), FTA(1), this(2) — Ch2 convention.
    // All frames follow this layout even if slots are unused (null).
    _refAlloc.alloc(); // rsp+0: ITA
    _refAlloc.alloc(); // rsp+1: FTA
    _refAlloc.alloc(); // rsp+2: this/receiver

    // Register function parameters as variable bindings.
    // Parameters get dedicated registers via the allocator (not scope-managed
    // for release -- they live for the entire function).
    _registerParams(positionalParams);
    _registerParams(namedParams);
  }

  /// Registers a list of parameter declarations in the current scope.
  void _registerParams(List<ir.VariableDeclaration> params) {
    for (final param in params) {
      final kind = _classifyStackKind(param.type);
      final reg = kind.isValue ? _valueAlloc.alloc() : _refAlloc.alloc();
      _scope.declareWithReg(param, kind, reg);
    }
  }

  /// Builds a [Uint8List] encoding each parameter's [StackKind] for
  /// [DarticFuncProto.paramKinds]. Used by invokeClosure to route
  /// host-side arguments to the correct stack.
  Uint8List _buildParamKinds(
    List<ir.VariableDeclaration> positional,
    List<ir.VariableDeclaration> named,
  ) {
    final all = [...positional, ...named];
    final kinds = Uint8List(all.length);
    for (var i = 0; i < all.length; i++) {
      kinds[i] = _classifyStackKind(all[i].type).index;
    }
    return kinds;
  }

  /// Computes [DarticFuncProto.returnKind] for invokeClosure result boxing.
  ///
  /// Returns: StackKind.xxx.index (ref=0, boolVal=1, intVal=2, doubleVal=3).
  /// Bool is distinguished from int because the value stack stores both
  /// as int64, but the host VM expects a Dart [bool].
  int _classifyReturnKind(ir.DartType returnType) {
    if (returnType is ir.InterfaceType &&
        returnType.nullability != ir.Nullability.nullable) {
      final cls = returnType.classNode;
      if (cls == _coreTypes.boolClass) return StackKind.boolVal.index;
      if (cls == _coreTypes.intClass) return StackKind.intVal.index;
      if (cls == _coreTypes.doubleClass) return StackKind.doubleVal.index;
    }
    return StackKind.ref.index;
  }

  // ── Async stub ──

  /// Emits a stub body for async/generator functions that throws at runtime.
  /// This allows the compiler to proceed past async code (e.g., in
  /// expect.dart's async_utils.dart) without failing at compile time.
  /// Tests that never call these functions will work; tests that do call them
  /// will get a clear runtime error.
  void _emitAsyncStub(ir.AsyncMarker marker, String funcName) {
    final label = switch (marker) {
      ir.AsyncMarker.Async => 'async',
      ir.AsyncMarker.AsyncStar => 'async*',
      ir.AsyncMarker.SyncStar => 'sync*',
      _ => marker.toString(),
    };
    final msg = 'Unsupported: $label function "$funcName" '
        'is not yet implemented. This will be added in Phase 6.';
    final reg = _allocRefReg();
    final idx = _constantPool.addRef(msg);
    _emitter.emit(encodeABx(Op.loadConst, reg, idx));
    _emitter.emit(encodeABC(Op.throw_, reg, 0, 0));
  }

  // ── Procedure compilation ──

  void _compileProcedure(ir.Procedure proc) {
    final funcId = _procToFuncId[proc.reference]!;
    final fn = proc.function;

    // Track enclosing class type params for generic type resolution.
    final enclosingClass = proc.enclosingClass;
    _currentEnclosingClass = (!proc.isStatic && enclosingClass != null)
        ? enclosingClass
        : null;
    _currentClassTypeParams = (!proc.isStatic && enclosingClass != null)
        ? enclosingClass.typeParameters
        : null;

    // Track function-level type params for generic method type resolution.
    _currentFunctionTypeParams = fn.typeParameters.isNotEmpty
        ? fn.typeParameters
        : null;

    _resetFunctionState(
      isEntry: funcId == _entryFuncId,
      returnType: fn.returnType,
      positionalParams: fn.positionalParameters,
      namedParams: fn.namedParameters,
    );

    // Check async marker using dartAsyncMarker (design doc decision).
    final asyncMarker = fn.dartAsyncMarker;

    if (asyncMarker == ir.AsyncMarker.Async) {
      _currentAsyncMarker = ir.AsyncMarker.Async;

      // Compile emittedValueType to TypeTemplate, store in constant pool.
      final emittedType = fn.emittedValueType ?? const ir.DynamicType();
      final template = dartTypeToTemplate(
        emittedType,
        _typeClassIdLookup,
        enclosingClassTypeParams: _currentClassTypeParams,
        enclosingFunctionTypeParams: _currentFunctionTypeParams,
      );
      final typeBx = _constantPool.addRef(template);

      // Allocate a ref register for the future result.
      final futureReg = _allocRefReg();

      // Emit INIT_ASYNC A, Bx.
      _emitter.emit(encodeABx(Op.initAsync, futureReg, typeBx));

      // Compile function body normally.
      final body = fn.body;
      if (body != null) {
        _compileStatement(body);
      }

      // Safety net: if no explicit return, emit ASYNC_RETURN null.
      // For async entry functions, INIT_ASYNC stores the future in
      // _lastEntryResult (handled in the interpreter), so no HALT needed.
      {
        // Non-entry async function: safety net is ASYNC_RETURN null.
        final nullReg = _allocRefReg();
        _emitter.emit(encodeABC(Op.loadNull, nullReg, 0, 0));
        _emitCloseUpvaluesIfNeeded();
        _emitter.emit(encodeABC(Op.asyncReturn, nullReg, 0, 0));
      }
    } else if (asyncMarker == ir.AsyncMarker.SyncStar) {
      _currentAsyncMarker = ir.AsyncMarker.SyncStar;

      // Compile emittedValueType to TypeTemplate, store in constant pool.
      final emittedType = fn.emittedValueType ?? const ir.DynamicType();
      final template = dartTypeToTemplate(
        emittedType,
        _typeClassIdLookup,
        enclosingClassTypeParams: _currentClassTypeParams,
        enclosingFunctionTypeParams: _currentFunctionTypeParams,
      );
      final typeBx = _constantPool.addRef(template);

      // Allocate a ref register for the iterable.
      final iterableReg = _allocRefReg();

      // Emit INIT_SYNC_STAR A, Bx — creates the lazy iterable.
      _emitter.emit(encodeABx(Op.initSyncStar, iterableReg, typeBx));

      // Emit RETURN_REF A — return the iterable synchronously to the caller.
      // For entry functions, use HALT instead so the dispatch loop exits.
      if (_isEntryFunction) {
        _emitter.emit(
          encodeABC(Op.halt, iterableReg, StackKind.refDefault + 1, 0),
        );
      } else {
        _emitter.emit(encodeABC(Op.returnRef, iterableReg, 0, 0));
      }

      // The body bytecode follows (executed by SyncStarIterator.moveNext
      // via drive()). Compile the function body.
      final body = fn.body;
      if (body != null) {
        _compileStatement(body);
      }

      // Safety net: RETURN_NULL signals generator done.
      _emitCloseUpvaluesIfNeeded();
      _emitter.emit(encodeABC(Op.returnNull, 0, 0, 0));
    } else if (asyncMarker == ir.AsyncMarker.AsyncStar) {
      _currentAsyncMarker = ir.AsyncMarker.AsyncStar;

      // Compile emittedValueType to TypeTemplate, store in constant pool.
      final emittedType = fn.emittedValueType ?? const ir.DynamicType();
      final template = dartTypeToTemplate(
        emittedType,
        _typeClassIdLookup,
        enclosingClassTypeParams: _currentClassTypeParams,
        enclosingFunctionTypeParams: _currentFunctionTypeParams,
      );
      final typeBx = _constantPool.addRef(template);

      // Allocate a ref register for the stream.
      final streamReg = _allocRefReg();

      // Emit INIT_ASYNC_STAR A, Bx — creates StreamController, stores stream.
      _emitter.emit(encodeABx(Op.initAsyncStar, streamReg, typeBx));

      // Emit RETURN_REF A — return the stream synchronously to the caller.
      // For entry functions, use HALT instead so the dispatch loop exits.
      if (_isEntryFunction) {
        _emitter.emit(
          encodeABC(Op.halt, streamReg, StackKind.refDefault + 1, 0),
        );
      } else {
        _emitter.emit(encodeABC(Op.returnRef, streamReg, 0, 0));
      }

      // The body bytecode follows (executed when the stream gets a listener
      // via onListen callback). Compile the function body.
      final body = fn.body;
      if (body != null) {
        _compileStatement(body);
      }

      // Safety net: RETURN_NULL signals generator done -> controller.close().
      _emitCloseUpvaluesIfNeeded();
      _emitter.emit(encodeABC(Op.returnNull, 0, 0, 0));
    } else if (asyncMarker != ir.AsyncMarker.Sync) {
      // Unknown async marker — use stub.
      _emitAsyncStub(asyncMarker, proc.name.text);

      // Safety net: if no explicit return, emit HALT or RETURN_NULL.
      if (_isEntryFunction) {
        _emitter.emit(encodeABC(Op.halt, 0, 0, 0));
      } else {
        _emitCloseUpvaluesIfNeeded();
        _emitter.emit(encodeABC(Op.returnNull, 0, 0, 0));
      }
    } else {
      // Synchronous function — compile body normally.
      final body = fn.body;
      if (body != null) {
        _compileStatement(body);
      }

      // Safety net: if no explicit return, emit HALT or RETURN_NULL.
      if (_isEntryFunction) {
        _emitter.emit(encodeABC(Op.halt, 0, 0, 0));
      } else {
        _emitCloseUpvaluesIfNeeded();
        _emitter.emit(encodeABC(Op.returnNull, 0, 0, 0));
      }
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
      paramCount: fn.positionalParameters.length + fn.namedParameters.length,
      paramKinds: _buildParamKinds(
          fn.positionalParameters, fn.namedParameters),
      returnKind: _classifyReturnKind(fn.returnType),
      exceptionTable: List.of(_exceptionHandlers),
      icTable: List.of(_icEntries),
    );
    _currentEnclosingClass = null;
    _currentClassTypeParams = null;
    _currentFunctionTypeParams = null;
  }

  // ── Global initializer compilation ──

  /// Compiles a standalone initializer function for a global [field].
  ///
  /// The generated function computes the initializer expression, boxes the
  /// result if needed, emits STORE_GLOBAL to the given [globalIndex], and
  /// ends with HALT.
  int _compileGlobalInitializer(ir.Field field, int globalIndex) {
    _resetFunctionState(isEntry: true);

    final (reg, loc) = _compileExpression(field.initializer!);
    final refReg = _boxToRefIfValue(reg, loc, field.type);
    _emitter.emit(encodeABx(Op.storeGlobal, refReg, globalIndex));

    // HALT (end of initializer).
    _emitter.emit(encodeAx(Op.halt, 0));

    _patchPendingArgMoves();

    // Capture funcId AFTER compiling the expression, because compilation
    // may add inner functions (closures) to _functions, shifting indices.
    final funcId = _functions.length;
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

  /// Compiles a binary value-stack operation with mixed-type auto-promotion.
  ///
  /// Pre-checks operand types BEFORE compiling them. If one operand is int
  /// and the other is double, auto-promotes the int opcode to its double
  /// equivalent and converts the int operand via INT_TO_DBL.
  ///
  /// Returns null if auto-promotion is impossible (e.g., divInt has no double
  /// equivalent). When null is returned, NO operands have been compiled —
  /// the caller can safely fall through to an alternative path.
  (int, ResultLoc)? _emitBinaryOp(ir.InstanceInvocation expr, int op) {
    var targetKind =
        _isDoubleBinaryOp(op) ? StackKind.doubleVal : StackKind.intVal;

    // Pre-check: infer actual operand kinds (cheap, no side effects).
    final lhsKind = _inferStackKind(expr.receiver);
    final rhsKind = expr.arguments.positional.isNotEmpty
        ? _inferStackKind(expr.arguments.positional[0])
        : targetKind;

    // Auto-promote int opcode to double when one operand is double.
    if (targetKind == StackKind.intVal &&
        (lhsKind == StackKind.doubleVal || rhsKind == StackKind.doubleVal)) {
      final promoted = _intToDoubleOp(op);
      if (promoted == null) return null; // No double equivalent → bail out
      op = promoted;
      targetKind = StackKind.doubleVal;
    }

    // Compile operands (only after pre-check passes).
    var (lhsReg, lhsLoc) = _compileExpression(expr.receiver);
    var (rhsReg, rhsLoc) =
        _compileExpression(expr.arguments.positional[0]);

    // Coerce both operands to target kind (handles ref→value AND int↔double).
    lhsReg = _coerceToValueKind(lhsReg, lhsLoc, lhsKind, targetKind);
    rhsReg = _coerceToValueKind(rhsReg, rhsLoc, rhsKind, targetKind);

    final resultReg = _allocValueReg();
    _emitter.emit(encodeABC(op, resultReg, lhsReg, rhsReg));
    return (resultReg, ResultLoc.value);
  }

  /// Compiles a unary value-stack operation on the receiver.
  ///
  /// If the operand is on the ref-stack, it is unboxed first. The unbox type
  /// is determined by what the opcode expects: negDbl/dblToInt need double
  /// input; everything else (negInt, bitNot, intToDbl) needs int input.
  (int, ResultLoc) _emitUnaryOp(ir.InstanceInvocation expr, int op) {
    var (srcReg, srcLoc) = _compileExpression(expr.receiver);
    final kind = (op == Op.negDbl || op == Op.dblToInt)
        ? StackKind.doubleVal : StackKind.intVal;
    srcReg = _ensureValue(srcReg, srcLoc, kind);
    final resultReg = _allocValueReg();
    _emitter.emit(encodeABC(op, resultReg, srcReg, 0));
    return (resultReg, ResultLoc.value);
  }

  /// Emits UNBOX_INT, UNBOX_DOUBLE, or UNBOX_BOOL to move a ref-stack value
  /// to the value stack. Returns the new value-stack register.
  int _emitUnbox(int refReg, StackKind kind) {
    final unboxOp = switch (kind) {
      StackKind.doubleVal => Op.unboxDouble,
      StackKind.boolVal   => Op.unboxBool,
      _                   => Op.unboxInt,
    };
    final valReg = _allocValueReg();
    _emitter.emit(encodeABC(unboxOp, valReg, refReg, 0));
    return valReg;
  }

  /// Ensures a value is on the value stack. If [loc] is ref, emits
  /// UNBOX via [_emitUnbox]. No-op if already on value stack.
  int _ensureValue(int reg, ResultLoc loc, StackKind kind) {
    if (loc == ResultLoc.ref) return _emitUnbox(reg, kind);
    return reg;
  }

  /// Ensures a register is on the value stack with the target [StackKind].
  ///
  /// Unlike [_ensureValue] which only handles ref→value (unbox), this method
  /// also handles value-stack int↔double conversion via INT_TO_DBL / DBL_TO_INT.
  int _coerceToValueKind(
    int reg, ResultLoc loc, StackKind actualKind, StackKind targetKind,
  ) {
    if (loc == ResultLoc.ref) {
      return _emitUnbox(reg, targetKind);
    }
    if (actualKind == StackKind.intVal && targetKind == StackKind.doubleVal) {
      final converted = _allocValueReg();
      _emitter.emit(encodeABC(Op.intToDbl, converted, reg, 0));
      return converted;
    }
    if (actualKind == StackKind.doubleVal && targetKind == StackKind.intVal) {
      final converted = _allocValueReg();
      _emitter.emit(encodeABC(Op.dblToInt, converted, reg, 0));
      return converted;
    }
    return reg;
  }

  /// Ensures a boolean expression result is on the value stack.
  int _ensureBoolValue(int reg, ResultLoc loc) =>
      _ensureValue(reg, loc, StackKind.boolVal);

  /// Ensures a value is on the ref stack, boxing if it is on the value stack.
  /// Uses [type] to determine the boxing opcode (int/double/bool).
  /// No-op if already on the ref stack.
  int _boxToRefIfValue(int reg, ResultLoc loc, ir.DartType? type) {
    if (loc == ResultLoc.value) return _emitBoxToRef(reg, type);
    return reg;
  }

  /// Coerces an argument register to match the expected parameter [paramKind].
  /// Returns the (possibly new) register and its location.
  ///
  /// - ref arg → value param: emits UNBOX_INT/UNBOX_DOUBLE
  /// - value arg → ref param: emits BOX via _emitBoxToRef (uses [argExpr]
  ///   to infer the boxing type — only evaluated on the boxing path)
  /// - matching: returns unchanged
  (int, ResultLoc) _coerceArg(
    int argReg, ResultLoc argLoc,
    StackKind paramKind, ir.Expression? argExpr,
  ) {
    if (paramKind == StackKind.ref && argLoc == ResultLoc.value) {
      final argType = argExpr != null ? _inferExprType(argExpr) : null;
      return (_emitBoxToRef(argReg, argType), ResultLoc.ref);
    } else if (paramKind.isValue && argLoc == ResultLoc.ref) {
      return (_ensureValue(argReg, argLoc, paramKind), ResultLoc.value);
    }
    return (argReg, argLoc);
  }

  /// Returns true if [op] is a double binary opcode (arithmetic or comparison).
  bool _isDoubleBinaryOp(int op) =>
      (op >= Op.addDbl && op <= Op.divDbl) ||
      (op >= Op.ltDbl && op <= Op.geDbl) ||
      op == Op.eqDbl ||
      op == Op.modDbl;

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
    if (loc == ResultLoc.value && targetLoc == ResultLoc.ref) {
      reg = _emitBoxToRef(reg, _inferExprType(branchExpr));
      loc = ResultLoc.ref;
    } else if (loc == ResultLoc.ref && targetLoc == ResultLoc.value) {
      // Unbox ref->value when the branch produces a ref-stack value but the
      // ConditionalExpression targets a value-stack register. This occurs in
      // CFE-desugared `??` where the non-null branch is a VariableGet with
      // promotedType (e.g. int? promoted to int).
      final kind = _inferNonNullStackKind(branchExpr);
      reg = _ensureValue(reg, loc, kind);
      loc = ResultLoc.value;
    }
    if (reg != targetReg) {
      _emitMove(targetReg, reg, targetLoc);
    }
  }

  /// Infers the value-stack kind for an expression, stripping nullability.
  ///
  /// Used when unboxing a ref-stack value to the value stack. If the inferred
  /// type is nullable (e.g. `int?`), strips the nullability to determine the
  /// correct unbox opcode. Falls back to [StackKind.intVal] when the type
  /// cannot be determined.
  StackKind _inferNonNullStackKind(ir.Expression expr) {
    final type = _inferExprType(expr);
    if (type is ir.InterfaceType &&
        type.nullability == ir.Nullability.nullable) {
      return _classifyStackKind(
          type.withDeclaredNullability(ir.Nullability.nonNullable));
    }
    return type != null ? _classifyStackKind(type) : StackKind.intVal;
  }

  /// Boxes a value-stack register to the ref stack, preserving the Dart
  /// runtime type. Uses BOX_BOOL for bools, BOX_DOUBLE for doubles,
  /// and BOX_INT for ints.
  ///
  /// Returns the ref-stack register containing the boxed value.
  int _emitBoxToRef(int valueReg, ir.DartType? type) {
    final refReg = _allocRefReg();
    final kind = type != null ? _classifyStackKind(type) : StackKind.intVal;
    switch (kind) {
      case StackKind.doubleVal:
        _emitter.emit(encodeABC(Op.boxDouble, refReg, valueReg, 0));
      case StackKind.boolVal:
        _emitter.emit(encodeABC(Op.boxBool, refReg, valueReg, 0));
      default:
        _emitter.emit(encodeABC(Op.boxInt, refReg, valueReg, 0));
    }
    return refReg;
  }

  /// Emits SET_FIELD_VAL or SET_FIELD_REF with appropriate value/ref coercion.
  ///
  /// If the field is a value-kind (int/double) but the source is on the ref
  /// stack, emits UNBOX first. Conversely, if the field is ref-kind but the
  /// source is on the value stack, emits BOX via [_emitBoxToRef].
  ///
  /// Returns the (possibly coerced) value register.
  int _emitSetField(int receiverReg, int valReg, ResultLoc valLoc,
      FieldLayout layout, ir.DartType? boxingType) {
    if (layout.kind.isValue) {
      valReg = _ensureValue(valReg, valLoc, layout.kind);
      _emitter.emit(
          encodeABC(Op.setFieldVal, receiverReg, valReg, layout.offset));
    } else {
      valReg = _boxToRefIfValue(valReg, valLoc, boxingType);
      _emitter.emit(
          encodeABC(Op.setFieldRef, receiverReg, valReg, layout.offset));
    }
    return valReg;
  }

  /// Emits GET_FIELD_VAL or GET_FIELD_REF based on the field layout kind.
  (int, ResultLoc) _emitGetField(int receiverReg, FieldLayout layout) {
    if (layout.kind.isValue) {
      final resultReg = _allocValueReg();
      _emitter.emit(
          encodeABC(Op.getFieldVal, resultReg, receiverReg, layout.offset));
      return (resultReg, ResultLoc.value);
    } else {
      final resultReg = _allocRefReg();
      _emitter.emit(
          encodeABC(Op.getFieldRef, resultReg, receiverReg, layout.offset));
      return (resultReg, ResultLoc.ref);
    }
  }

  /// Patches pending outgoing arg MOVE placeholders.
  ///
  /// Value args go to `valueRegCount + argIdx`, ref args to
  /// `refRegCount + argIdx`.
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

  /// Emits CLOSE_UPVALUE 0 if there are any captured variables in the current
  /// function. This must be called before RETURN to ensure open upvalues are
  /// closed before the frame is deallocated.
  void _emitCloseUpvaluesIfNeeded() {
    if (_capturedVarRefRegs.isNotEmpty) {
      _emitter.emit(encodeABC(Op.closeUpvalue, 0, 0, 0));
    }
  }

  /// Coerces [reg] between value/ref stacks if needed, then emits the
  /// appropriate RETURN instruction (RETURN_VAL or RETURN_REF).
  ///
  /// [loc] is where the result currently lives.
  /// [targetKind] is the declared return kind the caller expects.
  /// [boxingType] is used to determine the boxing opcode when coercing
  /// value->ref.
  void _emitCoercedReturn(
      int reg, ResultLoc loc, StackKind targetKind, ir.DartType? boxingType) {
    if (loc == ResultLoc.ref && targetKind.isValue) {
      final valReg = _emitUnbox(reg, targetKind);
      _emitter.emit(encodeABC(Op.returnVal, valReg, 0, 0));
    } else if (loc == ResultLoc.value && targetKind == StackKind.ref) {
      final refReg = _emitBoxToRef(reg, boxingType);
      _emitter.emit(encodeABC(Op.returnRef, refReg, 0, 0));
    } else if (loc == ResultLoc.value) {
      _emitter.emit(encodeABC(Op.returnVal, reg, 0, 0));
    } else {
      _emitter.emit(encodeABC(Op.returnRef, reg, 0, 0));
    }
  }

  /// Allocates a result register based on the return [type].
  ///
  /// Returns (register, ResultLoc) — ref types get a ref register,
  /// value types get a value register.
  (int, ResultLoc) _allocResultReg(ir.DartType type) {
    final loc = _classifyType(type);
    final reg = loc == ResultLoc.ref ? _allocRefReg() : _allocValueReg();
    return (reg, loc);
  }

  /// Moves [srcRegs] into consecutive ref register slots and emits a
  /// collection creation instruction.
  ///
  /// [op] is the opcode (createList/createMap/createSet).
  /// [destReg] is the pre-allocated destination register.
  /// [srcRegs] are the already-compiled element registers (all on ref stack).
  /// [count] is the element/entry count for the C operand.
  void _emitCreateCollection(
      int op, int destReg, List<int> srcRegs, int count) {
    final targetRegs = List.generate(srcRegs.length, (_) => _allocRefReg());
    for (var i = 0; i < srcRegs.length; i++) {
      if (srcRegs[i] != targetRegs[i]) {
        _emitter.emit(encodeABC(Op.moveRef, targetRegs[i], srcRegs[i], 0));
      }
    }
    _emitter.emit(encodeABC(op, destReg, targetRegs.first, count));
  }

  // ── Host binding helpers ──

  /// Allocates (or reuses) a binding index for a host function symbol.
  ///
  /// [symbolName] follows the convention: `"libUri::className::methodName#N"`
  /// where N is the number of explicit parameters (not counting receiver).
  /// [argCount] is the total number of args the CALL_HOST instruction will
  /// pass (includes receiver for instance methods).  Must fit in a uint8
  /// (max 255) since the .darb binding table serialises it as a single byte.
  int _allocBinding(String symbolName, int argCount) {
    assert(argCount >= 0 && argCount <= 255,
        'argCount $argCount out of uint8 range for binding "$symbolName"');
    return _bindingNameToIndex.putIfAbsent(symbolName, () {
      final index = _bindingNames.length;
      _bindingNames.add(BindingEntry(name: symbolName, argCount: argCount));
      return index;
    });
  }

  /// Builds a host binding symbol name for a [Member].
  ///
  /// Format: `"libUri::className::memberName#paramCount"`
  /// Top-level functions have an empty className: `"dart:core::::print#1"`.
  ///
  /// [nameOverride] replaces the member name (e.g. `"propName="` for setters).
  /// [paramCountOverride] replaces the computed param count.
  String _hostSymbolName(
    ir.Member target, {
    String? nameOverride,
    int? paramCountOverride,
  }) {
    final lib = target.enclosingLibrary.importUri.toString();
    final className = target.enclosingClass?.name ?? '';
    final memberName = nameOverride ?? target.name.text;

    final int paramCount;
    if (paramCountOverride != null) {
      paramCount = paramCountOverride;
    } else {
      final fn = switch (target) {
        ir.Procedure p => p.function,
        ir.Constructor c => c.function,
        _ => null,
      };
      paramCount = fn != null
          ? fn.positionalParameters.length + fn.namedParameters.length
          : 0; // field getter/setter
    }

    return '$lib::$className::$memberName#$paramCount';
  }

  // ── Helpers ──

  /// Reserves a funcId for a [Procedure] by appending a placeholder to
  /// [_functions] and recording the mapping in [_procToFuncId].
  void _reserveProcFuncId(ir.Procedure proc) {
    final funcId = _functions.length;
    _procToFuncId[proc.reference] = funcId;
    _functions.add(DarticFuncProto(
      funcId: funcId,
      bytecode: _haltBytecode,
      valueRegCount: 0,
      refRegCount: 0,
      paramCount: 0,
    ));
  }

  /// Registers a top-level or static field as a global variable slot.
  void _registerGlobalField(ir.Field field) {
    final globalIndex = _globalCount++;
    _fieldToGlobalIndex[field.getterReference] = globalIndex;
    final setterRef = field.setterReference;
    if (setterRef != null) {
      _fieldToGlobalIndex[setterRef] = globalIndex;
    }
    _globalInitializerIds.add(-1);
  }

  /// Compiles the initializer for a global field if it has one.
  void _compileFieldInitializerIfPresent(ir.Field field) {
    if (field.initializer == null) return;
    final globalIndex = _fieldToGlobalIndex[field.getterReference]!;
    _globalInitializerIds[globalIndex] =
        _compileGlobalInitializer(field, globalIndex);
  }

  bool _isPlatformLibrary(ir.Library lib) => lib.importUri.isScheme('dart');

  static final _haltBytecode =
      Uint32List.fromList([encodeAx(Op.halt, 0)]);
}
