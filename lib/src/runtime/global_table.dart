import 'error.dart';

/// Stores static fields and top-level variables.
///
/// Each slot is initially `_uninitialized`. On first LOAD_GLOBAL access,
/// the interpreter triggers lazy initialization (if an initializer is configured).
///
/// Three-state sentinel pattern:
/// - `_uninitialized`: not yet initialized
/// - `_initializing`: initialization in progress (cycle detection)
/// - any other value: initialized
class DarticGlobalTable {
  DarticGlobalTable(int count)
      : _slots = List<Object?>.filled(count, _uninitialized);

  final List<Object?> _slots;

  // Sentinels — identity-based detection via `identical()`.
  static final Object _uninitialized = Object();
  static final Object _initializing = Object();

  int get count => _slots.length;

  /// Reads the global at [index].
  ///
  /// Returns the stored value. Throws if uninitialized or circular.
  Object? load(int index) {
    final value = _slots[index];
    if (identical(value, _initializing)) {
      throw DarticError('Circular dependency: global variable $index');
    }
    if (identical(value, _uninitialized)) {
      throw DarticError('Uninitialized global variable $index');
    }
    return value;
  }

  /// Writes [value] to the global at [index].
  void store(int index, Object? value) {
    _slots[index] = value;
  }

  /// Returns true if the global at [index] has been initialized.
  bool isInitialized(int index) {
    return !identical(_slots[index], _uninitialized) &&
        !identical(_slots[index], _initializing);
  }

  /// Marks the global as currently initializing (for cycle detection).
  void markInitializing(int index) {
    _slots[index] = _initializing;
  }

  /// Resets the global to uninitialized (for error rollback).
  void resetToUninitialized(int index) {
    _slots[index] = _uninitialized;
  }
}
