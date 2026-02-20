/// Host function registry for cross-boundary calls.
///
/// Maps symbolic binding names (e.g. `"dart:core::::print#1"`) to integer IDs
/// and stores typed wrapper closures for O(1) dispatch at runtime.
///
/// See: docs/design/04-interop.md "HostFunctionRegistry（宿主函数注册表）"
library;

/// Registry of host VM functions callable from the interpreter via CALL_HOST.
///
/// Binding names follow the format: `"libraryURI::className::methodName#argCount"`.
/// For top-level functions, className is empty: `"dart:core::::print#1"`.
class HostFunctionRegistry {
  /// Typed wrapper closures indexed by runtime ID.
  final List<Object? Function(List<Object?>)> _functions = [];

  /// Symbol name → runtime ID mapping.
  final Map<String, int> _nameToId = {};

  /// Registers a host function binding.
  ///
  /// Returns the assigned runtime ID. Re-registering the same [name]
  /// returns the same ID (idempotent) — the wrapper is updated.
  int register(String name, Object? Function(List<Object?>) wrapper) {
    final existing = _nameToId[name];
    if (existing != null) {
      _functions[existing] = wrapper;
      return existing;
    }
    final id = _functions.length;
    _functions.add(wrapper);
    _nameToId[name] = id;
    return id;
  }

  /// Invokes the host function at [id] with [args].
  ///
  /// Throws [RangeError] if [id] is out of bounds.
  Object? invoke(int id, List<Object?> args) {
    return _functions[id](args);
  }

  /// Looks up the runtime ID for [name].
  ///
  /// Returns -1 if the binding is not registered.
  int lookupByName(String name) {
    return _nameToId[name] ?? -1;
  }

  /// Batch-resolves a list of binding symbol names to runtime IDs.
  ///
  /// Used during module loading to map the .darb binding name table
  /// to runtime IDs. Unresolved names get -1.
  List<int> resolveBindingTable(List<String> names) {
    return [for (final name in names) lookupByName(name)];
  }
}
