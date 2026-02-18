/// Scope-level register allocator for the Phase 1 compiler.
///
/// Manages a single register namespace (value or ref) using incrementing
/// allocation with a free-pool for reuse. When variables leave scope, their
/// registers are batch-released back to the pool.
///
/// Design rationale: This is far simpler than LSRA (which requires CFG +
/// live-range analysis) while being adequate for Dart functions with <50
/// locals and the 8-bit register encoding limit of 256.
///
/// See: docs/design/05-compiler.md "寄存器分配" appendix
class RegisterAllocator {
  /// Creates an allocator starting at [initialOffset].
  ///
  /// For the ref stack, pass `initialOffset: 3` to reserve slots 0-2
  /// for ITA, FTA, and `this`.
  RegisterAllocator({int initialOffset = 0})
      : _next = initialOffset,
        _max = initialOffset;

  int _next;
  int _max;
  final List<int> _freePool = [];

  /// Allocates a register, reusing from the free pool if available.
  int alloc() {
    if (_freePool.isNotEmpty) return _freePool.removeLast();
    final r = _next++;
    if (_next > _max) _max = _next;
    return r;
  }

  /// Returns a register to the free pool for reuse.
  void free(int reg) => _freePool.add(reg);

  /// Batch-returns multiple registers to the free pool.
  void freeAll(List<int> regs) => _freePool.addAll(regs);

  /// High-water mark: the total number of register slots needed to size
  /// the stack frame (count, not max-index).
  int get maxUsed => _max;

  /// Saves the current allocator state as a checkpoint.
  ///
  /// Used by the compiler to temporarily allocate "outgoing" registers
  /// for call arguments. After the call, [restore] undoes these
  /// allocations so they don't inflate `maxUsed` (and hence
  /// `valueRegCount` / `refRegCount` in the function proto).
  ({int next, int max, int poolLen}) checkpoint() =>
      (next: _next, max: _max, poolLen: _freePool.length);

  /// Restores the allocator to a previously saved checkpoint.
  void restore(({int next, int max, int poolLen}) saved) {
    _next = saved.next;
    _max = saved.max;
    _freePool.length = saved.poolLen;
  }
}
