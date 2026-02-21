import 'dart:typed_data';

import 'error.dart';

/// Synchronous call stack storing frame metadata as packed uint32 fields.
///
/// Each frame occupies [frameSize] (6) uint32 slots:
///   0: funcId     — current function ID
///   1: returnPC   — caller's PC
///   2: savedFP    — caller's frame pointer
///   3: savedVSP   — caller's value stack pointer
///   4: savedRSP   — caller's ref stack pointer
///   5: resultReg  — caller's return-value register
///
/// See: docs/design/02-object-model.md "CallStack" 段
class CallStack {
  CallStack({int maxFrames = defaultMaxFrames})
      : _maxFrames = maxFrames,
        _data = Uint32List(maxFrames * frameSize);

  static const int defaultMaxFrames = 512;

  /// Number of uint32 fields per frame.
  static const int frameSize = 6;

  // Field offsets within a frame (relative to frame base).
  static const int _funcId = 0;
  static const int _returnPC = 1;
  static const int _savedFP = 2;
  static const int _savedVSP = 3;
  static const int _savedRSP = 4;
  static const int _resultReg = 5;

  /// Sentinel funcId marking a HOST_BOUNDARY frame.
  static const int sentinelHostBoundary = 0xFFFFFFFF;

  final int _maxFrames;
  final Uint32List _data;

  /// Frame pointer — points to the base of the current frame.
  /// Before any push, fp is 0 (no frame). After first push, fp = frameSize.
  int _fp = 0;
  int _depth = 0;

  /// Current frame pointer.
  int get fp => _fp;

  /// Number of frames on the stack.
  int get depth => _depth;

  /// Maximum number of frames.
  int get maxFrames => _maxFrames;

  /// Pushes a new frame onto the call stack.
  ///
  /// Throws [DarticError] if the stack is already at capacity.
  void pushFrame({
    required int funcId,
    required int returnPC,
    required int savedFP,
    required int savedVSP,
    required int savedRSP,
    required int resultReg,
  }) {
    if (_depth >= _maxFrames) {
      throw DarticError('Call stack overflow: exceeded $_maxFrames frames');
    }
    final base = _fp;
    _data[base + _funcId] = funcId;
    _data[base + _returnPC] = returnPC;
    _data[base + _savedFP] = savedFP;
    _data[base + _savedVSP] = savedVSP;
    _data[base + _savedRSP] = savedRSP;
    _data[base + _resultReg] = resultReg;
    _fp = base + frameSize;
    _depth++;
  }

  /// Pops the current frame, restoring fp to the previous frame.
  void popFrame() {
    _fp = _data[_fp - frameSize + _savedFP];
    _depth--;
  }

  // ── Current frame field accessors ──
  // Read from (fp - frameSize) since fp points past the current frame.

  int get _base => _fp - frameSize;

  int get funcId => _data[_base + _funcId];
  int get returnPC => _data[_base + _returnPC];
  int get savedFP => _data[_base + _savedFP];
  int get savedVSP => _data[_base + _savedVSP];
  int get savedRSP => _data[_base + _savedRSP];
  int get resultReg => _data[_base + _resultReg];

  /// Returns `true` if the current frame is a HOST_BOUNDARY sentinel.
  bool get isHostBoundary => funcId == sentinelHostBoundary;

  /// Resets the call stack to its initial empty state.
  ///
  /// Used by [DarticInterpreter._resetState] for error recovery after
  /// resource limit errors (FuelExhaustedError, ExecutionTimeoutError).
  void reset() {
    _fp = 0;
    _depth = 0;
  }
}
