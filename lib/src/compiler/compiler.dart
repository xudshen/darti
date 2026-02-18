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

  // ── Per-function compilation state ──
  // Reset in _compileProcedure for each function.

  late BytecodeEmitter _emitter;
  late RegisterAllocator _valueAlloc;
  late RegisterAllocator _refAlloc;
  late Scope _scope;
  bool _isEntryFunction = false;

  /// Pending outgoing arg MOVE instructions to patch after the function is
  /// fully compiled. Each entry records the bytecode offset of a placeholder
  /// MOVE_VAL instruction, the source register, and the arg index.
  ///
  /// The calling convention places args at positions `valueRegCount + argIndex`
  /// (beyond the frame), but `valueRegCount` is only known after compilation.
  /// So we emit placeholder MOVEs and patch them in `_compileProcedure`.
  final List<({int pc, int srcReg, int argIdx})> _pendingArgMoves = [];

  /// Compiles the component and returns a [DarticModule].
  ///
  /// Two-pass strategy:
  /// 1. Collect all user procedures → assign funcIds
  /// 2. Compile each procedure's body → emit bytecode
  DarticModule compile() {
    // Pass 1: assign funcIds to all user-defined procedures.
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

    // Determine entry point.
    final mainProc = _component.mainMethod;
    if (mainProc != null) {
      final id = _procToFuncId[mainProc.reference];
      if (id != null) _entryFuncId = id;
    }
    if (_entryFuncId < 0 && _functions.isNotEmpty) {
      _entryFuncId = 0; // fallback
    }

    // Pass 2: compile each procedure.
    for (final lib in _component.libraries) {
      if (_isPlatformLibrary(lib)) continue;
      for (final proc in lib.procedures) {
        _compileProcedure(proc);
      }
    }

    return DarticModule(
      functions: _functions,
      constantPool: _constantPool,
      entryFuncId: _entryFuncId,
    );
  }

  // ── Procedure compilation ──

  void _compileProcedure(ir.Procedure proc) {
    final funcId = _procToFuncId[proc.reference]!;
    final fn = proc.function;

    // Reset per-function state.
    _emitter = BytecodeEmitter();
    _valueAlloc = RegisterAllocator();
    _refAlloc = RegisterAllocator(initialOffset: 3); // Reserve ITA/FTA/this
    _isEntryFunction = funcId == _entryFuncId;
    _pendingArgMoves.clear();

    // Create the function-level scope.
    _scope = Scope(valueAlloc: _valueAlloc, refAlloc: _refAlloc);

    // Register function parameters as variable bindings.
    // Parameters get dedicated registers via the allocator (not scope-managed
    // for release — they live for the entire function).
    for (final param in fn.positionalParameters) {
      final kind = _classifyStackKind(param.type);
      final reg = kind == StackKind.value
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

    // Patch outgoing arg MOVE placeholders now that valueRegCount is known.
    // Each call places args at consecutive positions starting at
    // valueRegCount (the first slot beyond the caller's frame).
    // The VM's CALL_STATIC sets callee.vBase = caller.vBase + valueRegCount,
    // so outgoing[argIdx] becomes callee.v[argIdx].
    final valRegCount = _valueAlloc.maxUsed;
    for (final move in _pendingArgMoves) {
      final destReg = valRegCount + move.argIdx;
      _emitter.patchJump(
        move.pc,
        encodeABC(Op.moveVal, destReg, move.srcReg, 0),
      );
    }
    _pendingArgMoves.clear();

    _functions[funcId] = DarticFuncProto(
      funcId: funcId,
      name: proc.name.text,
      bytecode: _emitter.toUint32List(),
      valueRegCount: valRegCount,
      refRegCount: _refAlloc.maxUsed,
      paramCount: fn.positionalParameters.length,
    );
  }

  // ── Register allocation helpers ──

  int _allocValueReg() => _valueAlloc.alloc();

  int _allocRefReg() => _refAlloc.alloc();

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
      // The declared type `kind` is intentionally not compared to `initLoc`
      // here — in Phase 1 we assume they always agree.
      _scope.declareWithReg(
        decl,
        initLoc == ResultLoc.value ? StackKind.value : StackKind.ref,
        initReg,
      );
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
      binding.kind == StackKind.value ? ResultLoc.value : ResultLoc.ref,
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
    if (binding.kind == StackKind.value) {
      _emitter.emit(encodeABC(Op.moveVal, binding.reg, srcReg, 0));
    } else {
      _emitter.emit(encodeABC(Op.moveRef, binding.reg, srcReg, 0));
    }
    return (
      binding.reg,
      binding.kind == StackKind.value ? ResultLoc.value : ResultLoc.ref,
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
    // register is `valueRegCount + argIdx`, but valueRegCount isn't known
    // yet (the function is still being compiled). We record these positions
    // and patch them in _compileProcedure after compilation finishes.
    for (var i = 0; i < argTemps.length; i++) {
      final (srcReg, _) = argTemps[i];
      final movePC = _emitter.emitPlaceholder();
      _pendingArgMoves.add((pc: movePC, srcReg: srcReg, argIdx: i));
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

  /// Classifies a DartType for expression result location (value or ref).
  ResultLoc _classifyType(ir.DartType type) {
    if (type is ir.InterfaceType) {
      final cls = type.classNode;
      if (cls == _coreTypes.intClass) return ResultLoc.value;
      if (cls == _coreTypes.doubleClass) return ResultLoc.value;
      if (cls == _coreTypes.boolClass) return ResultLoc.value;
    }
    return ResultLoc.ref;
  }

  /// Classifies a DartType for scope-level register allocation.
  StackKind _classifyStackKind(ir.DartType type) {
    if (type is ir.InterfaceType) {
      final cls = type.classNode;
      if (cls == _coreTypes.intClass) return StackKind.value;
      if (cls == _coreTypes.doubleClass) return StackKind.value;
      if (cls == _coreTypes.boolClass) return StackKind.value;
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
