import '../bytecode/module.dart';

/// Mutable cell for captured variables (open/closed upvalue semantics).
///
/// **Open upvalue**: Points to a ref stack slot (absolute index). Both the
/// outer function (via register access) and the closure (via
/// LOAD_UPVALUE/STORE_UPVALUE) read/write the SAME stack location.
///
/// **Closed upvalue**: Holds the value directly. Created when CLOSE_UPVALUE
/// executes (variable goes out of scope). Closures that escaped still have
/// access to the captured value.
///
/// See: docs/design/02-object-model.md "上值对象",
///      docs/design/03-execution-engine.md "CLOSURE 操作码"
class Upvalue {
  /// Absolute ref stack index (-1 when closed).
  int _stackIndex;

  /// The captured value. For closed upvalues this holds the actual value;
  /// for open upvalues it is unused (reads/writes go through the stack).
  ///
  /// Mutable: STORE_UPVALUE on a closed upvalue updates this directly.
  Object? value;

  /// Creates an open upvalue pointing to [stackIndex] in the ref stack.
  Upvalue.open(this._stackIndex) : value = null;

  /// Creates a closed upvalue holding [value] directly.
  Upvalue.closed(this.value) : _stackIndex = -1;

  /// Whether this upvalue still points to a live stack slot.
  bool get isOpen => _stackIndex >= 0;

  /// The absolute ref stack index (only valid when [isOpen] is true).
  int get stackIndex => _stackIndex;

  /// Closes this upvalue: saves [closedValue] and detaches from the stack.
  ///
  /// After closing, reads/writes go through [value] instead of the stack.
  void close(Object? closedValue) {
    value = closedValue;
    _stackIndex = -1;
  }
}

/// A closure: a function prototype paired with captured upvalues.
///
/// Created by the CLOSURE instruction. When CALL executes on a
/// DarticClosure, the interpreter extracts [funcProto] for the callee's
/// bytecode and [upvalues] for LOAD_UPVALUE/STORE_UPVALUE access.
///
/// See: docs/design/02-object-model.md "DarticClosure",
///      docs/design/03-execution-engine.md "CALL 指令"
class DarticClosure {
  DarticClosure({required this.funcProto, required this.upvalues});

  /// The compiled function this closure wraps.
  final DarticFuncProto funcProto;

  /// Captured upvalue cells. Indexed by the upvalue descriptor index.
  final List<Upvalue> upvalues;

  @override
  String toString() =>
      'DarticClosure(${funcProto.name}#${funcProto.funcId}, '
      'upvalues=${upvalues.length})';
}
