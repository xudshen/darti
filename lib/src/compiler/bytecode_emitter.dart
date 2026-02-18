import 'dart:typed_data';

/// Low-level bytecode emission buffer.
///
/// Wraps a growing `List<int>` and provides:
/// - `emit(instruction)` — append one 32-bit instruction word
/// - `emitPlaceholder()` — reserve a slot for later patching (jumps)
/// - `patchJump(offset, instruction)` — overwrite a previously emitted slot
/// - `currentPC` — number of instructions emitted so far
/// - `toUint32List()` — finalize to immutable bytecode
///
/// See: docs/design/05-compiler.md "字节码发射"
class BytecodeEmitter {
  final List<int> _buffer = [];

  /// Current program counter (number of instructions emitted).
  int get currentPC => _buffer.length;

  /// Appends a 32-bit instruction word.
  void emit(int instruction) => _buffer.add(instruction);

  /// Emits a placeholder (zero) and returns its offset for later patching.
  ///
  /// Used for forward jumps where the target PC is not yet known.
  int emitPlaceholder() {
    final offset = _buffer.length;
    _buffer.add(0);
    return offset;
  }

  /// Overwrites the instruction at [offset] with [instruction].
  ///
  /// Typically used to patch jump targets after the destination is known.
  void patchJump(int offset, int instruction) {
    assert(offset >= 0 && offset < _buffer.length,
        'patchJump offset $offset out of range [0, ${_buffer.length})');
    _buffer[offset] = instruction;
  }

  /// Returns the finalized bytecode as a [Uint32List].
  Uint32List toUint32List() => Uint32List.fromList(_buffer);
}
