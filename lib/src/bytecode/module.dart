library;

import 'dart:typed_data';

import '../runtime/class_info.dart';
import 'constant_pool.dart';

/// A compiled bytecode module containing functions and constants.
///
/// This is the in-memory representation of a compilation unit.
/// Serialized to/from `.darb` format via [DarticSerializer]/[DarticDeserializer].
///
/// See: docs/design/01-bytecode-isa.md, docs/design/02-object-model.md
class DarticModule {
  DarticModule({
    required this.functions,
    required this.constantPool,
    required this.entryFuncId,
    this.globalCount = 0,
    this.globalInitializerIds = const [],
    this.classes = const [],
    this.coreTypeIds,
    this.bindingNames = const [],
  });

  /// Function table — indexed by funcId.
  final List<DarticFuncProto> functions;

  /// Shared constant pool for this module.
  final ConstantPool constantPool;

  /// The funcId of the entry point (typically `main`).
  final int entryFuncId;

  /// Number of global variable slots.
  final int globalCount;

  /// For each global: funcId of its initializer function, or -1 if none.
  /// Length must equal [globalCount].
  final List<int> globalInitializerIds;

  /// Class table — indexed by classId. Used by NEW_INSTANCE and CALL_VIRTUAL.
  final List<DarticClassInfo> classes;

  /// Core type classIds for runtime TypeRegistry creation.
  ///
  /// Populated by the compiler. When non-null, the interpreter uses these
  /// to auto-create a [TypeRegistry] for DarticType-based INSTANCEOF/CAST.
  final CoreTypeIds? coreTypeIds;

  /// Binding name table — symbol names for CALL_HOST instructions.
  ///
  /// Each entry is a [BindingEntry] containing the symbol name and arg count.
  /// CALL_HOST's Bx operand indexes into this table. At module load time,
  /// the interpreter resolves these names via [HostBindings] and stores the
  /// resolved ID map internally.
  ///
  /// See: docs/design/05-compiler.md "绑定名称表"
  final List<BindingEntry> bindingNames;
}

/// Maps core Dart types to their compiler-assigned classIds.
///
/// These are the first entries in the class table, registered before
/// user-defined classes.
class CoreTypeIds {
  const CoreTypeIds({
    required this.intId,
    required this.doubleId,
    required this.stringId,
    required this.boolId,
    required this.objectId,
    required this.numId,
  });

  final int intId;
  final int doubleId;
  final int stringId;
  final int boolId;
  final int objectId;
  final int numId;
}

/// A binding name table entry for CALL_HOST instructions.
///
/// Contains the symbolic name and argument count for a host function binding.
class BindingEntry {
  const BindingEntry({required this.name, required this.argCount});

  /// Symbolic binding name, e.g. `"dart:core::::print#1"`.
  final String name;

  /// Number of arguments expected by the host function.
  final int argCount;

  @override
  String toString() => 'BindingEntry($name, args=$argCount)';
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
    this.paramKinds,
    this.returnKind = StackKind.refDefault,
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

  /// Per-parameter stack kind for [DarticInterpreter.invokeClosure] routing.
  ///
  /// Length equals [paramCount]. Each byte encodes a [StackKind] index:
  /// `0` = ref, `1` = boolVal, `2` = intVal, `3` = doubleVal.
  /// When null, invokeClosure falls back to writing all args to the ref stack
  /// (backward compatible with hand-crafted test protos).
  final Uint8List? paramKinds;

  /// Return value classification for [DarticInterpreter.invokeClosure] boxing.
  ///
  /// `0` = ref, `1` = boolVal, `2` = intVal, `3` = doubleVal.
  /// Defaults to `0` (ref). Used by invokeClosure to convert RETURN_VAL results
  /// back to the correct Dart type before handing to the host.
  final int returnKind;

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
  ICEntry({required this.methodNameIndex, this.argCount = 0});

  /// Method name index in the constant pool `names` partition.
  final int methodNameIndex;

  /// Number of arguments (excluding the receiver).
  /// Used to construct [Invocation] for noSuchMethod fallback.
  final int argCount;

  /// Cached class ID for monomorphic dispatch (-1 = uncached).
  int cachedClassId = -1;

  /// Cached funcId of the resolved method (valid only when cachedClassId != -1).
  int cachedFuncId = 0;

  @override
  String toString() => 'ICEntry(name=$methodNameIndex, args=$argCount, '
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

  /// Catch type discriminator:
  /// - `-1`: catch-all (untyped `catch (e)` or `finally`)
  /// - `>= 0`: constant pool index of a [TypeTemplate] for typed catch
  ///   (`on SomeType catch (e)`)
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
