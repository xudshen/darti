import 'dart:typed_data';

import 'package:kernel/ast.dart' as ir;
import 'package:kernel/core_types.dart' show CoreTypes;

import '../bytecode/constant_pool.dart';
import '../bytecode/encoding.dart';
import '../bytecode/module.dart';
import '../bytecode/opcodes.dart';
import '../runtime/class_info.dart';
import '../runtime/object.dart';
import 'bytecode_emitter.dart';
import 'register_allocator.dart';
import 'scope.dart';

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

  // ── Class compilation state ──

  /// Class info table — indexed by classId. Built during Pass 1c.
  final List<DarticClassInfo> _classInfos = [];

  /// Maps Kernel Class nodes to classIds.
  final Map<ir.Class, int> _classToClassId = {};

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
        final funcId = _functions.length;
        _procToFuncId[proc.reference] = funcId;
        // Placeholder -- will be replaced in pass 2.
        _functions.add(DarticFuncProto(
          funcId: funcId,
          bytecode: _haltBytecode,
          valueRegCount: 0,
          refRegCount: 0,
          paramCount: 0,
        ));
      }
      // Also register static procedures from classes.
      for (final cls in lib.classes) {
        for (final proc in cls.procedures) {
          if (!proc.isStatic) continue;
          // Skip if already registered (instance methods are registered in
          // Pass 1c, but static ones need early registration like top-level).
          if (_procToFuncId.containsKey(proc.reference)) continue;
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
        // Placeholder for initializer funcId -- will be set in Pass 2b.
        _globalInitializerIds.add(-1);
      }
      // Also register static fields from classes.
      for (final cls in lib.classes) {
        for (final field in cls.fields) {
          if (!field.isStatic) continue;
          final globalIndex = _globalCount++;
          _fieldToGlobalIndex[field.getterReference] = globalIndex;
          final setterRef = field.setterReference;
          if (setterRef != null) {
            _fieldToGlobalIndex[setterRef] = globalIndex;
          }
          _globalInitializerIds.add(-1);
        }
      }
    }

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
        if (field.initializer != null) {
          final globalIndex = _fieldToGlobalIndex[field.getterReference]!;
          final initFuncId = _compileGlobalInitializer(field, globalIndex);
          _globalInitializerIds[globalIndex] = initFuncId;
        }
      }
      // Also compile static field initializers from classes.
      for (final cls in lib.classes) {
        for (final field in cls.fields) {
          if (!field.isStatic) continue;
          if (field.initializer != null) {
            final globalIndex = _fieldToGlobalIndex[field.getterReference]!;
            final initFuncId = _compileGlobalInitializer(field, globalIndex);
            _globalInitializerIds[globalIndex] = initFuncId;
          }
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

  // ── Procedure compilation ──

  void _compileProcedure(ir.Procedure proc) {
    final funcId = _procToFuncId[proc.reference]!;
    final fn = proc.function;

    _resetFunctionState(
      isEntry: funcId == _entryFuncId,
      returnType: fn.returnType,
      positionalParams: fn.positionalParameters,
      namedParams: fn.namedParameters,
    );

    // Compile function body.
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
      exceptionTable: List.of(_exceptionHandlers),
      icTable: List.of(_icEntries),
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

    _resetFunctionState(isEntry: true);

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
      loc = ResultLoc.ref;
    } else if (loc == ResultLoc.ref && targetLoc == ResultLoc.value) {
      // Unbox ref->value when the branch produces a ref-stack value but the
      // ConditionalExpression targets a value-stack register. This occurs in
      // CFE-desugared `??` where the non-null branch is a VariableGet with
      // promotedType (e.g. int? promoted to int).
      final type = _inferExprType(branchExpr);
      final nonNullType = (type is ir.InterfaceType &&
              type.nullability == ir.Nullability.nullable)
          ? type.withDeclaredNullability(ir.Nullability.nonNullable)
          : type;
      final kind =
          nonNullType != null ? _classifyStackKind(nonNullType) : StackKind.intVal;
      final unboxOp =
          kind == StackKind.doubleVal ? Op.unboxDouble : Op.unboxInt;
      final valReg = _allocValueReg();
      _emitter.emit(encodeABC(unboxOp, valReg, reg, 0));
      reg = valReg;
      loc = ResultLoc.value;
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

  // ── Helpers ──

  bool _isPlatformLibrary(ir.Library lib) => lib.importUri.isScheme('dart');

  static final _haltBytecode =
      Uint32List.fromList([encodeAx(Op.halt, 0)]);
}
