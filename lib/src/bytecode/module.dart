import 'dart:typed_data';

import 'constant_pool.dart';

/// A compiled bytecode module containing functions and constants.
///
/// This is the in-memory representation of a compilation unit.
/// Serialization to/from `.darticb` format is deferred to Batch 1.5.
///
/// See: docs/design/01-bytecode-isa.md, docs/design/02-object-model.md
class DarticModule {
  DarticModule({
    required this.functions,
    required this.constantPool,
    required this.entryFuncId,
  });

  /// Function table — indexed by funcId.
  final List<DarticFuncProto> functions;

  /// Shared constant pool for this module.
  final ConstantPool constantPool;

  /// The funcId of the entry point (typically `main`).
  final int entryFuncId;
}

/// Compiled function prototype — the compiler's core output.
///
/// Encapsulates all compile-time metadata for a single function.
/// Multiple DarticFrames or DarticClosures may share the same proto.
///
/// See: docs/design/02-object-model.md "函数原型"
class DarticFuncProto {
  DarticFuncProto({
    required this.funcId,
    required this.bytecode,
    required this.valueRegCount,
    required this.refRegCount,
    required this.paramCount,
    this.name = '',
    this.icTable = const [],
    this.exceptionTable = const [],
    this.upvalueDescriptors = const [],
  });

  /// Human-readable function name (for debugging and serialization).
  final String name;

  /// Unique function identifier, used for CallStack frame records
  /// and global function table indexing.
  final int funcId;

  /// 32-bit fixed-width instruction sequence.
  final Uint32List bytecode;

  /// Value stack frame space requirement (params + locals + temporaries).
  final int valueRegCount;

  /// Reference stack frame space requirement.
  final int refRegCount;

  /// Number of parameters.
  final int paramCount;

  /// Inline cache table — one entry per `CALL_VIRTUAL` instruction.
  final List<ICEntry> icTable;

  /// Exception handler table, sorted by (startPC, endPC) range.
  final List<ExceptionHandler> exceptionTable;

  /// Upvalue descriptors for `CLOSURE` instruction.
  final List<UpvalueDescriptor> upvalueDescriptors;

  @override
  String toString() => 'FuncProto($name#$funcId, '
      'vRegs=$valueRegCount, rRegs=$refRegCount, '
      'params=$paramCount, codeLen=${bytecode.length})';
}

/// Inline cache entry for virtual method dispatch.
///
/// Each `CALL_VIRTUAL` instruction references one IC entry via its
/// C operand (funcProto.icTable[C]).
///
/// See: docs/design/01-bytecode-isa.md "内联缓存"
class ICEntry {
  ICEntry({required this.methodNameIndex});

  /// Method name index in the constant pool `names` partition.
  final int methodNameIndex;

  /// Cached class ID for monomorphic dispatch (-1 = uncached).
  int cachedClassId = -1;

  /// Cached method entry offset (valid only when cachedClassId != -1).
  int cachedMethodOffset = 0;

  @override
  String toString() => 'ICEntry(name=$methodNameIndex, '
      'cached=${cachedClassId == -1 ? "miss" : "cls$cachedClassId"})';
}

/// Exception handler descriptor within a function.
///
/// The dispatch loop scans the exception table when an exception is thrown,
/// looking for a handler whose [startPC, endPC) range covers the current PC.
///
/// See: docs/design/02-object-model.md
class ExceptionHandler {
  const ExceptionHandler({
    required this.startPC,
    required this.endPC,
    required this.handlerPC,
    this.catchType = -1,
    this.valStackDP = 0,
    this.refStackDP = 0,
    required this.exceptionReg,
    required this.stackTraceReg,
  });

  /// Start of the guarded bytecode range (inclusive).
  final int startPC;

  /// End of the guarded bytecode range (exclusive).
  final int endPC;

  /// PC to jump to when an exception is caught.
  final int handlerPC;

  /// Class ID of the catch type, or -1 for catch-all.
  final int catchType;

  /// Value stack depth to restore when entering the handler.
  final int valStackDP;

  /// Ref stack depth to restore when entering the handler.
  final int refStackDP;

  /// Register to store the caught exception object.
  final int exceptionReg;

  /// Register to store the stack trace.
  final int stackTraceReg;

  @override
  String toString() => 'ExHandler(pc=[$startPC,$endPC)→$handlerPC, '
      'catch=${catchType == -1 ? "all" : "type$catchType"})';
}

/// Upvalue descriptor — tells `CLOSURE` how to capture variables.
///
/// See: docs/design/02-object-model.md "上值对象"
class UpvalueDescriptor {
  const UpvalueDescriptor({
    required this.isLocal,
    required this.index,
  });

  /// `true` = capture from the immediate enclosing frame's ref stack slot.
  /// `false` = pass through from the enclosing closure's upvalue table.
  final bool isLocal;

  /// When [isLocal]: ref stack slot offset in the enclosing frame.
  /// When not: index into the enclosing closure's upvalues list.
  final int index;
}
