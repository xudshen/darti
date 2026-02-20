import 'dart:typed_data';

import '../bytecode/module.dart';

/// Heap-allocated execution frame for a function invocation.
///
/// DarticFrame is created at top-level entry (`execute()`) and for async
/// resume. Synchronous nested calls do NOT create new DarticFrames — they
/// use CallStack's frame metadata instead.
///
/// Phase 1 implements basic + stack snapshot fields only.
/// Async/generator fields are deferred to Phase 6.
///
/// See: docs/design/02-object-model.md "执行帧 — DarticFrame"
class DarticFrame {
  DarticFrame({
    required this.funcProto,
    this.upvalues = const [],
  });

  // ── Basic fields ──

  /// Current function prototype (bytecode, IC table, exception table, etc.).
  final DarticFuncProto funcProto;

  /// Program counter — saved when suspended, restored when resumed.
  int pc = 0;

  /// Upvalue table (from DarticClosure for closure calls, empty otherwise).
  final List<Object?> upvalues;

  // ── Stack snapshot fields (for async suspend/resume) ──

  /// Value stack frame base at suspend time.
  int savedVBase = 0;

  /// Ref stack frame base at suspend time.
  int savedRBase = 0;

  /// Value stack pointer at suspend time.
  int savedVSP = 0;

  /// Ref stack pointer at suspend time.
  int savedRSP = 0;

  /// Value stack snapshot (frame region), null when not suspended.
  Int64List? savedValueSlots;

  /// Ref stack snapshot (frame region), null when not suspended.
  List<Object?>? savedRefSlots;

  @override
  String toString() => 'DarticFrame(func=#${funcProto.funcId}, pc=$pc)';

  // TODO(phase6): async/generator control fields
  // - resultCompleter, thenCallback, errorCallback
  // - streamController, streamPaused, isSuspendedAtYield, cancelled
  // - awaitDestReg, resumeValue, resumeException, resumeStackTrace
  // - capturedZone, awaiterFrame
}
