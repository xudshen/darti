import 'package:kernel/ast.dart' as ir;

import 'register_allocator.dart';

/// Where a compiled variable lives — mirrors [ResultLoc] but avoids
/// circular dependency by being defined alongside Scope.
///
/// This is re-exported from compiler.dart as [ResultLoc].
enum StackKind {
  /// int, bool (encoded as 0/1) — ValueStack intView.
  intVal,

  /// double — ValueStack doubleView.
  doubleVal,

  /// String, object instances, closures, null, dynamic, num — RefStack.
  ref;

  /// Whether this kind uses the value stack (intVal or doubleVal).
  bool get isValue => this != ref;
}

/// A variable binding within a [Scope].
class VarBinding {
  const VarBinding({
    required this.reg,
    required this.kind,
  });

  /// Register number on the appropriate stack.
  final int reg;

  /// Which stack this variable lives on.
  final StackKind kind;
}

/// Lexical scope for variable bindings and register lifecycle management.
///
/// Scopes form a stack (not a tree) during compilation. Each scope tracks
/// the registers it allocated so they can be batch-released when the scope
/// exits.
///
/// See: docs/design/05-compiler.md "作用域分析"
class Scope {
  Scope({
    required this.valueAlloc,
    required this.refAlloc,
    this.parent,
  });

  final RegisterAllocator valueAlloc;
  final RegisterAllocator refAlloc;
  final Scope? parent;

  /// Variables declared in this scope. Maps Kernel VariableDeclaration
  /// to its binding (register + stack kind).
  final Map<ir.VariableDeclaration, VarBinding> _bindings = {};

  /// Registers allocated in this scope, tracked for batch release on exit.
  final List<int> _valueRegs = [];
  final List<int> _refRegs = [];

  /// Declares a variable in this scope and allocates a register for it.
  VarBinding declare(ir.VariableDeclaration decl, StackKind kind) {
    final reg = kind.isValue
        ? valueAlloc.alloc()
        : refAlloc.alloc();
    final binding = VarBinding(reg: reg, kind: kind);
    _bindings[decl] = binding;
    if (kind.isValue) {
      _valueRegs.add(reg);
    } else {
      _refRegs.add(reg);
    }
    return binding;
  }

  /// Declares a variable with a pre-allocated register (e.g., function
  /// parameters whose registers are assigned by the calling convention).
  VarBinding declareWithReg(
    ir.VariableDeclaration decl,
    StackKind kind,
    int reg,
  ) {
    final binding = VarBinding(reg: reg, kind: kind);
    _bindings[decl] = binding;
    // Don't track in _valueRegs/_refRegs — the register is owned externally
    // (e.g., parameter registers are part of the frame layout, not scope-managed).
    return binding;
  }

  /// Looks up a variable in this scope or any ancestor scope.
  VarBinding? lookup(ir.VariableDeclaration decl) {
    return _bindings[decl] ?? parent?.lookup(decl);
  }

  /// Releases all registers allocated in this scope back to their pools.
  void release() {
    valueAlloc.freeAll(_valueRegs);
    refAlloc.freeAll(_refRegs);
  }
}
