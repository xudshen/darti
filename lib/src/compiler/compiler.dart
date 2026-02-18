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

    // Compile initializer expression.
    final (reg, loc) = _compileExpression(field.initializer!);

    // Box value types to ref stack for STORE_GLOBAL.
    int refReg;
    if (loc == ResultLoc.value) {
      refReg = _allocRefReg();
      final kind = _classifyStackKind(field.type);
      if (kind == StackKind.doubleVal) {
        _emitter.emit(encodeABC(Op.boxDouble, refReg, reg, 0));
      } else {
        _emitter.emit(encodeABC(Op.boxInt, refReg, reg, 0));
      }
    } else {
      refReg = reg;
    }

    // Store to global slot.
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
      if (move.loc == ResultLoc.value) {
        final destReg = valRegCount + move.argIdx;
        _emitter.patchJump(
          move.pc,
          encodeABC(Op.moveVal, destReg, move.srcReg, 0),
        );
      } else {
        final destReg = refRegCount + move.argIdx;
        _emitter.patchJump(
          move.pc,
          encodeABC(Op.moveRef, destReg, move.srcReg, 0),
        );
      }
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
      // Bind the variable to the initializer's result register.
      // In Phase 1, the declared type and initializer type must agree.
      assert(
        kind.isValue == (initLoc == ResultLoc.value),
        'Type mismatch: declared $kind but initializer is $initLoc '
        'for ${decl.name}',
      );
      _scope.declareWithReg(decl, kind, initReg);
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
    throw UnsupportedError(
      'Unsupported expression: ${expr.runtimeType}',
    );
  }

  // ── Literal visitors ──

  (int, ResultLoc) _compileIntLiteral(ir.IntLiteral lit) {
    final reg = _allocValueReg();
    // sBx uses excess-K encoding (K=0x7FFF): asymmetric range [-32767, +32768].
    if (lit.value >= -32767 && lit.value <= 32768) {
      _emitter.emit(encodeAsBx(Op.loadInt, reg, lit.value));
    } else {
      final idx = _constantPool.addInt(lit.value);
      _emitter.emit(encodeABx(Op.loadConstInt, reg, idx));
    }
    return (reg, ResultLoc.value);
  }

  (int, ResultLoc) _compileBoolLiteral(ir.BoolLiteral lit) {
    final reg = _allocValueReg();
    _emitter.emit(encodeABC(
      lit.value ? Op.loadTrue : Op.loadFalse,
      reg, 0, 0,
    ));
    return (reg, ResultLoc.value);
  }

  (int, ResultLoc) _compileDoubleLiteral(ir.DoubleLiteral lit) {
    final reg = _allocValueReg();
    final idx = _constantPool.addDouble(lit.value);
    _emitter.emit(encodeABx(Op.loadConstDbl, reg, idx));
    return (reg, ResultLoc.value);
  }

  (int, ResultLoc) _compileStringLiteral(ir.StringLiteral lit) {
    final reg = _allocRefReg();
    final idx = _constantPool.addRef(lit.value);
    _emitter.emit(encodeABx(Op.loadConst, reg, idx));
    return (reg, ResultLoc.ref);
  }

  (int, ResultLoc) _compileNullLiteral() {
    final reg = _allocRefReg();
    _emitter.emit(encodeABC(Op.loadNull, reg, 0, 0));
    return (reg, ResultLoc.ref);
  }

  // ── ConstantExpression ──

  (int, ResultLoc) _compileConstantExpression(ir.ConstantExpression expr) {
    final constant = expr.constant;
    if (constant is ir.IntConstant) {
      final reg = _allocValueReg();
      if (constant.value >= -32767 && constant.value <= 32768) {
        _emitter.emit(encodeAsBx(Op.loadInt, reg, constant.value));
      } else {
        final idx = _constantPool.addInt(constant.value);
        _emitter.emit(encodeABx(Op.loadConstInt, reg, idx));
      }
      return (reg, ResultLoc.value);
    }
    if (constant is ir.DoubleConstant) {
      final reg = _allocValueReg();
      final idx = _constantPool.addDouble(constant.value);
      _emitter.emit(encodeABx(Op.loadConstDbl, reg, idx));
      return (reg, ResultLoc.value);
    }
    if (constant is ir.BoolConstant) {
      final reg = _allocValueReg();
      _emitter.emit(encodeABC(
        constant.value ? Op.loadTrue : Op.loadFalse,
        reg, 0, 0,
      ));
      return (reg, ResultLoc.value);
    }
    if (constant is ir.StringConstant) {
      final reg = _allocRefReg();
      final idx = _constantPool.addRef(constant.value);
      _emitter.emit(encodeABx(Op.loadConst, reg, idx));
      return (reg, ResultLoc.ref);
    }
    if (constant is ir.NullConstant) {
      final reg = _allocRefReg();
      _emitter.emit(encodeABC(Op.loadNull, reg, 0, 0));
      return (reg, ResultLoc.ref);
    }
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

  // ── EqualsNull ──

  (int, ResultLoc) _compileEqualsNull(ir.EqualsNull expr) {
    final (refReg, _) = _compileExpression(expr.expression);
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

    final (lhsReg, _) = _compileExpression(expr.left);
    final (rhsReg, _) = _compileExpression(expr.right);
    final resultReg = _allocValueReg();

    if (isInt) {
      _emitter.emit(encodeABC(Op.eqInt, resultReg, lhsReg, rhsReg));
    } else {
      // TODO(Phase 3): Replace EQ_REF (identical) with EQ_GENERIC or
      // CALL_VIRTUAL on operator== once user-defined classes are supported.
      _emitter.emit(encodeABC(Op.eqRef, resultReg, lhsReg, rhsReg));
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
        final cls = type.classNode;
        if (cls == _coreTypes.intClass || cls == _coreTypes.boolClass) {
          final valReg = _allocValueReg();
          _emitter.emit(encodeABC(Op.unboxInt, valReg, reg, 0));
          return (valReg, ResultLoc.value);
        }
        if (cls == _coreTypes.doubleClass) {
          final valReg = _allocValueReg();
          _emitter.emit(encodeABC(Op.unboxDouble, valReg, reg, 0));
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

  (int, ResultLoc) _compileVariableGet(ir.VariableGet expr) {
    final binding = _scope.lookup(expr.variable);
    if (binding == null) {
      throw StateError(
        'Undefined variable: ${expr.variable.name}',
      );
    }
    return (
      binding.reg,
      binding.kind.isValue ? ResultLoc.value : ResultLoc.ref,
    );
  }

  (int, ResultLoc) _compileVariableSet(ir.VariableSet expr) {
    final binding = _scope.lookup(expr.variable);
    if (binding == null) {
      throw StateError(
        'Undefined variable: ${expr.variable.name}',
      );
    }
    final (srcReg, _) = _compileExpression(expr.value);
    if (binding.kind.isValue) {
      _emitter.emit(encodeABC(Op.moveVal, binding.reg, srcReg, 0));
    } else {
      _emitter.emit(encodeABC(Op.moveRef, binding.reg, srcReg, 0));
    }
    return (
      binding.reg,
      binding.kind.isValue ? ResultLoc.value : ResultLoc.ref,
    );
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
      if (kind == StackKind.intVal) {
        final valReg = _allocValueReg();
        _emitter.emit(encodeABC(Op.unboxInt, valReg, refReg, 0));
        return (valReg, ResultLoc.value);
      }
      if (kind == StackKind.doubleVal) {
        final valReg = _allocValueReg();
        _emitter.emit(encodeABC(Op.unboxDouble, valReg, refReg, 0));
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

      // Box value types to ref stack for STORE_GLOBAL.
      int refReg;
      if (srcLoc == ResultLoc.value) {
        refReg = _allocRefReg();
        final kind = _classifyStackKind(target.type);
        if (kind == StackKind.doubleVal) {
          _emitter.emit(encodeABC(Op.boxDouble, refReg, srcReg, 0));
        } else {
          _emitter.emit(encodeABC(Op.boxInt, refReg, srcReg, 0));
        }
      } else {
        refReg = srcReg;
      }

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
    final argTemps = <(int, ResultLoc)>[];
    for (final arg in args) {
      argTemps.add(_compileExpression(arg));
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
    // Phase 1: specialize int arithmetic operators.
    //
    // In Dart, `int` extends `num`, so arithmetic operators (+, -, *, etc.)
    // are defined on `num`. The interfaceTarget.enclosingClass is `num`,
    // not `int`. We check both, then use the receiver's type to decide
    // between int and double instructions.
    final targetClass = expr.interfaceTarget.enclosingClass;
    final name = expr.name.text;

    if (targetClass == _coreTypes.intClass ||
        targetClass == _coreTypes.numClass) {
      // Check if receiver is statically int.
      final receiverType = _inferExprType(expr.receiver);
      if (receiverType != null && _isIntType(receiverType)) {
        final intOp = _intArithOp(name);
        if (intOp != null) {
          final (lhsReg, _) = _compileExpression(expr.receiver);
          final (rhsReg, _) =
              _compileExpression(expr.arguments.positional[0]);
          final resultReg = _allocValueReg();
          _emitter.emit(encodeABC(intOp, resultReg, lhsReg, rhsReg));
          return (resultReg, ResultLoc.value);
        }

        // Unary minus: in Kernel, -a is InstanceInvocation(a, 'unary-', [])
        if (name == 'unary-') {
          final (srcReg, _) = _compileExpression(expr.receiver);
          final resultReg = _allocValueReg();
          _emitter.emit(encodeABC(Op.negInt, resultReg, srcReg, 0));
          return (resultReg, ResultLoc.value);
        }
      }
    }

    throw UnsupportedError(
      'Unsupported instance invocation: $name on $targetClass',
    );
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
    if (expr is ir.EqualsNull) return _coreTypes.boolNonNullableRawType;
    if (expr is ir.EqualsCall) return _coreTypes.boolNonNullableRawType;
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
    if (expr is ir.StaticInvocation) return expr.target.function.returnType;
    if (expr is ir.InstanceInvocation) {
      // For chained int operations like (a + b) - c:
      // num.operator+ returns `num`, but if the receiver is `int`,
      // the result is `int` at runtime. Propagate the more specific type.
      final targetClass = expr.interfaceTarget.enclosingClass;
      if (targetClass == _coreTypes.numClass) {
        final receiverType = _inferExprType(expr.receiver);
        if (receiverType != null && _isIntType(receiverType)) {
          return _coreTypes.intNonNullableRawType;
        }
      }
      return expr.interfaceTarget.function.returnType;
    }
    return null;
  }

  bool _isIntType(ir.DartType type) =>
      type is ir.InterfaceType && type.classNode == _coreTypes.intClass;

  ir.DartType? _inferConstantType(ir.Constant constant) {
    if (constant is ir.IntConstant) return _coreTypes.intNonNullableRawType;
    if (constant is ir.DoubleConstant) {
      return _coreTypes.doubleNonNullableRawType;
    }
    if (constant is ir.BoolConstant) return _coreTypes.boolNonNullableRawType;
    if (constant is ir.StringConstant) {
      return _coreTypes.stringNonNullableRawType;
    }
    if (constant is ir.NullConstant) return const ir.NullType();
    return null;
  }

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

  /// Maps int operator names to opcodes.
  static int? _intArithOp(String name) => switch (name) {
        '+' => Op.addInt,
        '-' => Op.subInt,
        '*' => Op.mulInt,
        '~/' => Op.divInt,
        '%' => Op.modInt,
        _ => null,
      };

  // ── Helpers ──

  bool _isPlatformLibrary(ir.Library lib) => lib.importUri.isScheme('dart');

  static final _haltBytecode =
      Uint32List.fromList([encodeAx(Op.halt, 0)]);
}
