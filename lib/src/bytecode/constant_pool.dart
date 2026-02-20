library;

import 'dart:typed_data';

/// Four-partition constant pool for the dartic bytecode format.
///
/// Each partition uses an independent index space starting from 0:
/// - **refs**: `List<Object?>` — strings, types, function protos, null
/// - **ints**: `Int64List` — 64-bit integers (zero-boxing)
/// - **doubles**: `Float64List` — double-precision floats (zero-boxing)
/// - **names**: `List<String>` — property/method names for dynamic access
///
/// All partitions support deduplication: adding an identical value returns
/// the existing index instead of allocating a new slot.
///
/// See: docs/design/01-bytecode-isa.md "四分区常量池"
class ConstantPool {
  /// Creates an empty ConstantPool.
  ConstantPool();

  /// Creates a ConstantPool pre-populated with data (for deserialization).
  ConstantPool.from({
    required List<Object?> refs,
    required Int64List ints,
    required Float64List doubles,
    required List<String> names,
  }) {
    for (final r in refs) {
      addRef(r);
    }
    for (final v in ints) {
      addInt(v);
    }
    for (final v in doubles) {
      addDouble(v);
    }
    for (final n in names) {
      addName(n);
    }
  }

  // ── refs partition ──

  final List<Object?> _refs = [];
  final Map<Object?, int> _refDedup = {};

  int addRef(Object? value) =>
      _refDedup.putIfAbsent(value, () {
        _refs.add(value);
        return _refs.length - 1;
      });

  Object? getRef(int index) => _refs[index];
  int get refCount => _refs.length;

  // ── ints partition ──

  Int64List _ints = Int64List(8);
  int _intLen = 0;
  final Map<int, int> _intDedup = {};

  int addInt(int value) =>
      _intDedup.putIfAbsent(value, () {
        if (_intLen == _ints.length) {
          final grown = Int64List(_ints.length * 2);
          grown.setAll(0, _ints);
          _ints = grown;
        }
        _ints[_intLen] = value;
        return _intLen++;
      });

  int getInt(int index) => _ints[index];
  int get intCount => _intLen;

  // ── doubles partition ──

  Float64List _doubles = Float64List(8);
  int _dblLen = 0;
  final Map<int, int> _dblDedup = {}; // keyed by bit pattern for NaN handling

  int addDouble(double value) {
    final bits = _doubleToBits(value);
    return _dblDedup.putIfAbsent(bits, () {
      if (_dblLen == _doubles.length) {
        final grown = Float64List(_doubles.length * 2);
        grown.setAll(0, _doubles);
        _doubles = grown;
      }
      _doubles[_dblLen] = value;
      return _dblLen++;
    });
  }

  double getDouble(int index) => _doubles[index];
  int get doubleCount => _dblLen;

  // ── names partition ──

  final List<String> _names = [];
  final Map<String, int> _nameDedup = {};

  int addName(String value) =>
      _nameDedup.putIfAbsent(value, () {
        _names.add(value);
        return _names.length - 1;
      });

  String getName(int index) => _names[index];
  int get nameCount => _names.length;

  /// Reverse-looks up the index of [name] in the names partition.
  /// Returns -1 if the name has not been added.
  int lookupNameIndex(String name) => _nameDedup[name] ?? -1;

  // ── read-only accessors (for serialization) ──

  /// Returns an unmodifiable view of the refs partition.
  List<Object?> get refs => List.unmodifiable(_refs);

  /// Returns a copy of the ints partition (only the used portion).
  Int64List get ints => Int64List.fromList(_ints.sublist(0, _intLen));

  /// Returns a copy of the doubles partition (only the used portion).
  Float64List get doubles => Float64List.fromList(_doubles.sublist(0, _dblLen));

  /// Returns an unmodifiable view of the names partition.
  List<String> get names => List.unmodifiable(_names);

  // ── helpers ──

  /// Shared conversion buffer. Single-isolate only; not reentrant.
  static final _bitsBuffer = ByteData(8);

  static int _doubleToBits(double value) {
    _bitsBuffer.setFloat64(0, value);
    return _bitsBuffer.getInt64(0);
  }
}
