import 'dart:async';
import 'dart:typed_data';

import '../bridge/callback_proxy.dart';
import '../bridge/host_function_registry.dart';
import '../bridge/dynamic_dispatch.dart';
import '../bytecode/module.dart';
import '../bytecode/opcodes.dart';
import '../compiler/type_template.dart';
import 'call_stack.dart';
import 'class_info.dart' show StackKind;
import 'closure.dart';
import 'dartic_invocation.dart';
import 'dartic_type.dart';
import 'error.dart';
import 'frame.dart';
import 'global_table.dart';
import 'object.dart';
import 'ref_stack.dart';
import 'subtype_checker.dart';
import 'sync_star.dart';
import 'type_resolver.dart';
import 'value_stack.dart';

/// Bytecode interpreter with register-based dispatch loop.
///
/// Supports synchronous execution, async/await (via Completer bridging),
/// sync* generators (via SyncStarIterable), and async* generators (via
/// StreamController). Async suspend/resume uses frame-as-continuation:
/// DarticFrame snapshots stack regions on suspend, restores at stack top
/// on resume, and microtask scheduling drives the continuation.
///
/// See: docs/design/03-execution-engine.md, docs/design/07-async.md
class DarticInterpreter {
  DarticInterpreter({
    ValueStack? valueStack,
    RefStack? refStack,
    CallStack? callStack,
    this.typeRegistry,
    this.hostFunctionRegistry,
    this.fuelBudget = defaultFuelBudget,
  })  : valueStack = valueStack ?? ValueStack(),
        refStack = refStack ?? RefStack(),
        callStack = callStack ?? CallStack();

  static const int defaultFuelBudget = 50000;

  final ValueStack valueStack;
  final RefStack refStack;
  final CallStack callStack;
  final int fuelBudget;

  /// Type registry for generics support. If null, generics instructions throw.
  final TypeRegistry? typeRegistry;

  /// Host function bindings for CALL_HOST. If null, CALL_HOST throws.
  final HostFunctionRegistry? hostFunctionRegistry;

  /// Global variable table — initialized per-module in [execute].
  DarticGlobalTable? _globalTable;

  /// Subtype checker for DarticType-based INSTANCEOF/CAST.
  SubtypeChecker? _subtypeChecker;

  /// Remaining fuel — shared across initializer and main execution.
  int _fuel = 0;

  /// Open upvalue tracking: maps absolute ref stack index to the open
  /// [Upvalue] cell. When CLOSURE captures a local variable, it looks up
  /// or creates an entry here. When CLOSE_UPVALUE fires, matching entries
  /// are removed and their cells transition to closed state.
  final Map<int, Upvalue> _openUpvalues = {};

  /// Parallel stack of upvalue lists for each call frame. Stores the
  /// current frame's closure upvalues (or null for non-closure calls).
  /// Pushed on CALL/CALL_STATIC, popped on RETURN.
  final List<List<Upvalue>?> _upvalueStack = [];

  /// The entry function's result after [execute], or `null` if void.
  Object? get entryResult => _lastEntryResult;
  Object? _lastEntryResult;

  /// The currently executing module — set in [execute], used by [invokeClosure].
  DarticModule? _activeModule;

  /// Return value from a callback that exited via HOST_BOUNDARY RETURN.
  Object? _callbackResult;

  /// Runtime-resolved binding ID map: local index → HostFunctionRegistry runtime ID.
  ///
  /// Filled during [execute] via `HostFunctionRegistry.resolveBindingTable`.
  /// Read by CALL_HOST in the dispatch loop.
  List<int> _bindingIdMap = const [];

  /// Dynamic dispatch registry for host (VM-native) objects.
  /// Initialized per-execution from [hostFunctionRegistry].
  HostDispatchRegistry? _hostClassRegistry;

  /// The current async frame being executed. Set when an async function is
  /// entered via INIT_ASYNC. Used by AWAIT/ASYNC_RETURN/ASYNC_THROW to
  /// access the DarticFrame across _executeLoop invocations.
  DarticFrame? _currentAsyncFrame;

  /// The active sync* iterator being driven. Non-null only while inside
  /// [driveSyncStar]. Used by the YIELD and RETURN_NULL handlers to
  /// distinguish sync* context from other contexts.
  SyncStarIterator<Object?>? _activeSyncStarIterator;

  /// Result status from the last sync* drive step. Set by YIELD or
  /// RETURN_NULL when in sync* context, read by [driveSyncStar] after
  /// _executeLoop returns.
  SyncStarStatus? _syncStarStatus;

  /// Suspended frame from a YIELD in sync* context. Set by the YIELD handler,
  /// read by [driveSyncStar] to update the iterator's frame reference.
  DarticFrame? _syncStarSuspendedFrame;

  /// The current async* frame being executed. Non-null only while inside
  /// an async* generator body. Used by YIELD and RETURN_NULL to distinguish
  /// async* context from sync* and regular async contexts.
  DarticFrame? _currentAsyncStarFrame;

  /// Executes [module] starting from its entry function.
  ///
  /// Runs the dispatch loop until HALT is reached or fuel is exhausted.
  void execute(DarticModule module) {
    _fuel = fuelBudget;
    _lastEntryResult = null;
    _activeModule = module;
    _openUpvalues.clear();
    _upvalueStack.clear();
    _currentAsyncFrame = null;

    // Auto-create TypeRegistry + SubtypeChecker from module metadata.
    _provisionTypeSystem(module);

    // Resolve binding name table for CALL_HOST.
    _resolveBindings(module);

    // Initialize dynamic dispatch registry for host objects.
    final hfr = hostFunctionRegistry;
    _hostClassRegistry = hfr != null ? HostDispatchRegistry(hfr) : null;

    // Set up global table and run initializers.
    if (module.globalCount > 0) {
      _globalTable = DarticGlobalTable(module.globalCount);
      // Run initializers (each ends with STORE_GLOBAL + HALT).
      for (var i = 0; i < module.globalCount; i++) {
        final initFuncId = module.globalInitializerIds[i];
        if (initFuncId >= 0) {
          _executeEntry(module, initFuncId);
        }
      }
    }

    // Run main.
    _executeEntry(module, module.entryFuncId);
  }

  /// Creates TypeRegistry and SubtypeChecker from module metadata if available.
  void _provisionTypeSystem(DarticModule module) {
    final ids = module.coreTypeIds;
    if (ids != null && typeRegistry == null) {
      _effectiveTypeRegistry = TypeRegistry(
        intClassId: ids.intId,
        doubleClassId: ids.doubleId,
        stringClassId: ids.stringId,
        boolClassId: ids.boolId,
        objectClassId: ids.objectId,
        numClassId: ids.numId,
      );
    }
    final active = _activeTypeRegistry;
    if (active != null) {
      _subtypeChecker = SubtypeChecker(
        classes: module.classes,
        registry: active,
      );
    }
  }

  /// The effective type registry: either user-provided or auto-created from
  /// module metadata.
  TypeRegistry? _effectiveTypeRegistry;

  /// Returns the active TypeRegistry (user-provided or auto-provisioned).
  TypeRegistry? get _activeTypeRegistry => _effectiveTypeRegistry ?? typeRegistry;

  /// Resolves the module's binding name table using [hostFunctionRegistry].
  ///
  /// Maps each symbolic name in [module.bindingNames] to a runtime ID via
  /// [HostFunctionRegistry.resolveBindingTable]. Unresolved names get -1.
  void _resolveBindings(DarticModule module) {
    if (module.bindingNames.isEmpty) return;
    final hb = hostFunctionRegistry;
    if (hb == null) {
      throw DarticError(
        'Module has ${module.bindingNames.length} host bindings '
        'but no HostFunctionRegistry provided',
      );
    }
    _bindingIdMap = hb.resolveBindingTable(
      [for (final entry in module.bindingNames) entry.name],
    );
  }

  /// Runs the dispatch loop for a single entry function within [module].
  ///
  /// Used for both global initializer functions and the main entry point.
  void _executeEntry(DarticModule module, int entryFuncId) {
    final entryFunc = module.functions[entryFuncId];

    // Set up initial frame.
    final vBase = valueStack.sp;
    final rBase = refStack.sp;

    callStack.pushFrame(
      funcId: entryFunc.funcId,
      returnPC: 0,
      savedFP: callStack.fp,
      savedVSP: vBase,
      savedRSP: rBase,
      resultReg: 0,
    );

    valueStack.sp += entryFunc.valueRegCount;
    refStack.sp += entryFunc.refRegCount;

    _executeLoop(module, vBase, rBase, entryFunc.bytecode, 0, null);
  }

  /// Invokes an interpreter [closure] with [args] from the host VM.
  ///
  /// Used by [DarticCallbackProxy] to bridge VM callbacks (e.g. list.map)
  /// back into the interpreter. Pushes a HOST_BOUNDARY sentinel frame,
  /// executes the closure's bytecode, and returns the result.
  ///
  /// Re-entrant: can be called from within a CALL_HOST handler, nesting
  /// dispatch loops on the Dart call stack.
  ///
  /// See: docs/design/03-execution-engine.md "invokeClosure 机制"
  Object? invokeClosure(DarticClosure closure, List<Object?> args) {
    final module = _activeModule;
    if (module == null) {
      throw DarticError('invokeClosure called outside of execute()');
    }
    final proto = closure.funcProto;

    return _runNestedDispatch(
      module: module,
      proto: proto,
      args: args,
      upvalues: closure.upvalues,
    );
  }

  /// Calls a DarticObject method synchronously with proper result boxing.
  ///
  /// Used by dynamic dispatch (INVOKE_DYN, GET_FIELD_DYN, SET_FIELD_DYN)
  /// when dispatching to DarticObject methods. Runs a nested dispatch loop
  /// via HOST_BOUNDARY, ensuring value-type returns (int, double, bool) are
  /// properly boxed to Object? for the ref-stack result expected by dynamic
  /// dispatch instructions.
  Object? _callDarticMethod(
    DarticModule module,
    DarticFuncProto method,
    Object receiver,
    List<Object?> args,
  ) {
    return _runNestedDispatch(
      module: module,
      proto: method,
      receiver: receiver,
      args: args,
    );
  }

  /// Shared implementation for [invokeClosure] and [_callDarticMethod].
  ///
  /// Pushes a HOST_BOUNDARY sentinel frame, allocates a callee frame, routes
  /// arguments to the correct stacks, executes a nested dispatch loop, and
  /// returns the boxed result.
  Object? _runNestedDispatch({
    required DarticModule module,
    required DarticFuncProto proto,
    required List<Object?> args,
    Object? receiver,
    List<Upvalue>? upvalues,
  }) {
    final vs = valueStack;
    final rs = refStack;

    // Stack overflow checks.
    if (vs.sp + proto.valueRegCount > vs.capacity ||
        rs.sp + proto.refRegCount > rs.capacity) {
      throw DarticError('Stack overflow');
    }
    if (callStack.depth + 2 >= callStack.maxFrames) {
      throw DarticError('Maximum call depth exceeded');
    }

    // Save pre-callback stack state for exception cleanup.
    final savedVSP = vs.sp;
    final savedRSP = rs.sp;

    // Push HOST_BOUNDARY sentinel frame.
    callStack.pushFrame(
      funcId: CallStack.sentinelHostBoundary,
      returnPC: 0,
      savedFP: callStack.fp,
      savedVSP: savedVSP,
      savedRSP: savedRSP,
      resultReg: 0,
    );
    _upvalueStack.add(null);

    // Allocate callee frame.
    final vBase = vs.sp;
    final rBase = rs.sp;
    vs.sp += proto.valueRegCount;
    rs.sp += proto.refRegCount;

    // Place receiver at rBase+2 (this) if provided.
    if (receiver != null) {
      rs.write(rBase + 2, receiver);
    }

    // Route args to the correct stacks via paramKinds metadata.
    // The refArgStart offset only matters for the legacy fallback path
    // (when paramKinds is null): methods use rBase+3, closures use rBase+2.
    _routeArgs(proto, args, vBase, rBase, receiver != null ? 3 : 2);

    // Push callee frame.
    callStack.pushFrame(
      funcId: proto.funcId,
      returnPC: 0,
      savedFP: callStack.fp,
      savedVSP: vBase,
      savedRSP: rBase,
      resultReg: 0,
    );

    // Execute nested dispatch loop.
    try {
      _executeLoop(module, vBase, rBase, proto.bytecode, 0, upvalues);
    } on Object {
      // Exception propagated past HOST_BOUNDARY — restore stacks.
      vs.sp = savedVSP;
      rs.sp = savedRSP;
      if (callStack.isHostBoundary) {
        callStack.popFrame();
        _upvalueStack.removeLast();
      }
      rethrow;
    }

    // Read result and clean up.
    final result = _callbackResult;
    _callbackResult = null;

    // Pop HOST_BOUNDARY sentinel.
    callStack.popFrame();
    _upvalueStack.removeLast();

    return result;
  }

  /// Wraps any [DarticClosure] entries in [args] as Dart [Function] objects
  /// via [DarticCallbackProxy], mutating the list in place.
  void _wrapClosureArgs(List<Object?> args) {
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg is DarticClosure) {
        final proxy = DarticCallbackProxy(this, arg);
        args[i] = switch (arg.funcProto.paramCount) {
          0 => proxy.proxy0(),
          1 => proxy.proxy1(),
          2 => proxy.proxy2(),
          3 => proxy.proxy3(),
          _ => throw DarticError(
              'DarticCallbackProxy: unsupported arity '
              '${arg.funcProto.paramCount}'),
        };
      }
    }
  }

  /// Routes [args] to the correct stack positions based on [proto.paramKinds].
  ///
  /// Convention: ref[0]=ITA, ref[1]=FTA, ref[2]=this (reserved).
  /// Ref params start at rBase+3; value params start at vBase+0.
  /// When paramKinds is null (hand-crafted test protos), all args go to the
  /// ref stack starting at rBase+[refArgStart].
  void _routeArgs(
    DarticFuncProto proto,
    List<Object?> args,
    int vBase,
    int rBase,
    int refArgStart,
  ) {
    final paramKinds = proto.paramKinds;
    if (paramKinds == null) {
      // No paramKinds metadata — write all args to ref stack.
      for (var i = 0; i < args.length; i++) {
        refStack.write(rBase + refArgStart + i, args[i]);
      }
      return;
    }

    var valArgIdx = 0;
    var refArgIdx = 3; // After ITA(0), FTA(1), this(2)
    for (var i = 0; i < args.length; i++) {
      final kind =
          i < paramKinds.length ? paramKinds[i] : StackKind.refDefault;
      switch (kind) {
        case StackKind.refDefault:
          refStack.write(rBase + refArgIdx, args[i]);
          refArgIdx++;
        case StackKind.intDefault:
          valueStack.writeInt(vBase + valArgIdx, args[i] as int);
          valArgIdx++;
        case StackKind.boolDefault:
          final v = args[i];
          valueStack.writeInt(
              vBase + valArgIdx, v is bool ? (v ? 1 : 0) : v as int);
          valArgIdx++;
        default: // StackKind.doubleVal
          valueStack.writeDouble(
              vBase + valArgIdx, (args[i] as num).toDouble());
          valArgIdx++;
      }
    }
  }

  /// Saves the value-stack and ref-stack regions owned by [frame] into its
  /// snapshot fields ([DarticFrame.savedValueSlots], [DarticFrame.savedRefSlots]).
  ///
  /// After snapshotting, the original ref-stack slots are set to null so that
  /// objects referenced only by this frame become eligible for GC.
  ///
  /// See: docs/design/07-async.md "挂起流程（Suspend）"
  void suspendFrame(DarticFrame frame) {
    final vBase = frame.savedVBase;
    final vSize = frame.savedVSP - vBase;
    final rBase = frame.savedRBase;
    final rSize = frame.savedRSP - rBase;

    if (vSize > 0) {
      frame.savedValueSlots = Int64List(vSize);
      frame.savedValueSlots!.setRange(0, vSize, valueStack.intView, vBase);
    }

    if (rSize > 0) {
      frame.savedRefSlots = List<Object?>.filled(rSize, null);
      for (int i = 0; i < rSize; i++) {
        frame.savedRefSlots![i] = refStack.slots[rBase + i];
        refStack.slots[rBase + i] = null; // Release references for GC.
      }
    }
  }

  /// Restores [frame]'s saved stack data at the **current stack top** (not
  /// the original position).
  ///
  /// Allocates space at [valueStack.sp]/[refStack.sp], copies the snapshot
  /// back, updates the frame's base/sp fields to the new positions, and
  /// advances the global stack pointers. The snapshot fields are set to null
  /// after restoration.
  ///
  /// See: docs/design/07-async.md "恢复 — _restoreFrameStack"
  void restoreFrameStack(DarticFrame frame) {
    final vSize = frame.savedValueSlots?.length ?? 0;
    final rSize = frame.savedRefSlots?.length ?? 0;

    final newVBase = valueStack.sp;
    final newRBase = refStack.sp;

    if (newVBase + vSize > valueStack.capacity) {
      throw StateError('ValueStack overflow during frame restore '
          '(need ${newVBase + vSize}, capacity ${valueStack.capacity})');
    }
    if (newRBase + rSize > refStack.capacity) {
      throw StateError('RefStack overflow during frame restore '
          '(need ${newRBase + rSize}, capacity ${refStack.capacity})');
    }

    if (frame.savedValueSlots != null) {
      valueStack.intView.setRange(
          newVBase, newVBase + vSize, frame.savedValueSlots!);
      frame.savedValueSlots = null;
    }

    if (frame.savedRefSlots != null) {
      for (int i = 0; i < rSize; i++) {
        refStack.slots[newRBase + i] = frame.savedRefSlots![i];
      }
      frame.savedRefSlots = null;
    }

    frame.savedVBase = newVBase;
    frame.savedRBase = newRBase;
    frame.savedVSP = newVBase + vSize;
    frame.savedRSP = newRBase + rSize;
    valueStack.sp = newVBase + vSize;
    refStack.sp = newRBase + rSize;
  }

  /// Registers then/error callbacks on a Future or schedules immediate resume
  /// for a non-Future value.
  ///
  /// For async* frames (identified by `frame.streamController != null`),
  /// routes to [_resumeAsyncStarFrame] instead of [_resumeFrame].
  void _registerAwaitCallbacks(
    DarticFrame frame, Object? value, DarticModule module,
  ) {
    final zone = frame.capturedZone ?? Zone.current;

    // Choose the correct resume function based on frame type.
    // Capture a single resume closure to avoid re-allocating on every callback.
    final isAsyncStar = frame.streamController != null;
    final void Function() resume = isAsyncStar
        ? () => _resumeAsyncStarFrame(frame, module)
        : () => _resumeFrame(frame, module);

    if (value is Future) {
      // Lazily create cached callbacks for this frame.
      frame.thenCallback ??= (Object? result) {
        frame.resumeValue = result;
        zone.scheduleMicrotask(resume);
      };
      frame.errorCallback ??= (Object error, StackTrace stackTrace) {
        frame.resumeException = error;
        frame.resumeStackTrace = stackTrace;
        zone.scheduleMicrotask(resume);
      };
      value.then(
        frame.thenCallback! as void Function(Object?),
        onError: frame.errorCallback! as void Function(Object, StackTrace),
      );
    } else {
      // Non-Future value: schedule immediate resume via microtask.
      frame.resumeValue = value;
      zone.scheduleMicrotask(resume);
    }
  }

  /// Delivers the async function's Future to the synchronous caller.
  ///
  /// Called once per async function when the Future is first returned to the
  /// caller (at the first AWAIT, or at ASYNC_RETURN/ASYNC_THROW if no AWAIT
  /// was reached). Sets [DarticFrame.futureReturned] to true.
  ///
  /// Returns the caller's loop state (vBase, rBase, code, pc, upvalues) if
  /// the caller's dispatch loop should continue, or `null` if `_executeLoop`
  /// should return (entry function or host boundary).
  ({int vBase, int rBase, Uint32List code, int pc, List<Upvalue>? upvalues})?
      _deliverFutureToCaller(
    DarticFrame frame,
    Object? future,
    DarticModule module,
    int vBase,
    int rBase,
  ) {
    frame.futureReturned = true;

    // Entry function (no caller to return to).
    if (callStack.depth <= 1) {
      _lastEntryResult = future;
      valueStack.sp = vBase;
      refStack.sp = rBase;
      callStack.popFrame();
      _upvalueStack.removeLast();
      _currentAsyncFrame = null;
      return null;
    }

    // Pop callee frame, restore caller state.
    final callerVSP = callStack.savedVSP;
    final callerRSP = callStack.savedRSP;
    final retPC = callStack.returnPC;
    final resReg = callStack.resultReg;

    valueStack.sp = vBase;
    refStack.sp = rBase;

    callStack.popFrame();

    if (callStack.isHostBoundary) {
      _callbackResult = future;
      _upvalueStack.removeLast();
      _currentAsyncFrame = null;
      return null;
    }

    // Write future to caller's result register.
    refStack.write(callerRSP + resReg, future);

    final callerCode = module.functions[callStack.funcId].bytecode;
    final callerUpvalues = _upvalueStack.removeLast();

    _currentAsyncFrame = frame.callerAsyncFrame;

    return (
      vBase: callerVSP,
      rBase: callerRSP,
      code: callerCode,
      pc: retPC,
      upvalues: callerUpvalues,
    );
  }

  /// Resumes a suspended async frame after a Future completes.
  ///
  /// Called from a microtask scheduled by the AWAIT handler. Restores the
  /// frame's stack data at the current stack top, writes the resume value
  /// (or routes the exception to a handler), then starts a new
  /// [_executeLoop] invocation to continue execution.
  void _resumeFrame(DarticFrame frame, DarticModule module) {
    // Restore frame stack data at the current stack top.
    restoreFrameStack(frame);

    final vBase = frame.savedVBase;
    final rBase = frame.savedRBase;

    // Push a call stack entry for the resumed frame.
    callStack.pushFrame(
      funcId: frame.funcProto.funcId,
      returnPC: 0,
      savedFP: callStack.fp,
      savedVSP: vBase,
      savedRSP: rBase,
      resultReg: 0,
    );
    // Push upvalue stack entry to keep it in sync with the call stack.
    // Resumed frames don't capture upvalues from a closure caller, so
    // push null (matching the entry-frame pattern in _executeEntry).
    _upvalueStack.add(null);

    int pc = frame.pc;

    // Check if we're resuming with an exception.
    if (frame.resumeException != null) {
      final exception = frame.resumeException;
      final stackTrace = frame.resumeStackTrace;
      frame.resumeException = null;
      frame.resumeStackTrace = null;

      // Search at the AWAIT instruction's PC (pc - 1), not the resume PC.
      // The exception occurred during the await expression, so the AWAIT's
      // PC is the correct point for handler lookup. The resume PC (pc) may
      // fall outside the try handler's [startPC, endPC) range.
      final funcProto = frame.funcProto;
      final handler = _findHandler(
          funcProto, pc - 1, exception, module, rBase, refStack);
      if (handler != null) {
        refStack.clearRange(rBase + handler.refStackDP, refStack.sp);
        valueStack.sp = vBase + handler.valStackDP;
        refStack.sp = rBase + handler.refStackDP;
        refStack.write(rBase + handler.exceptionReg, exception);
        if (handler.stackTraceReg >= 0) {
          refStack.write(rBase + handler.stackTraceReg, stackTrace);
        }
        pc = handler.handlerPC;
      } else {
        // No handler found — complete the async completer with error.
        valueStack.sp = vBase;
        refStack.sp = rBase;
        callStack.popFrame();
        _upvalueStack.removeLast();
        frame.resultCompleter!.completeError(
            exception!,
            stackTrace is StackTrace ? stackTrace : StackTrace.empty);
        _currentAsyncFrame = null;
        return;
      }
    } else {
      // Normal resume: write resumeValue to the await destination register.
      refStack.write(rBase + frame.awaitDestReg, frame.resumeValue);
      frame.resumeValue = null;
    }

    // Set the async frame context and start a new dispatch loop.
    _currentAsyncFrame = frame;
    try {
      _executeLoop(
        module,
        vBase,
        rBase,
        frame.funcProto.bytecode,
        pc,
        null,
      );
    } on Object catch (e, st) {
      // Uncaught exception from the async body — complete the Completer
      // with error. This handles throws that escape the dispatch loop
      // without being caught by an exception handler (e.g., throw after
      // await with no enclosing try/catch).
      // Clean up stacks left by the escaped exception.
      valueStack.sp = vBase;
      refStack.sp = rBase;
      callStack.popFrame();
      _upvalueStack.removeLast();

      final completer = frame.resultCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(e, st);
      }
      _currentAsyncFrame = null;
    }
  }

  /// Starts the async* generator body for the first time.
  ///
  /// Called from the StreamController's onListen callback (via microtask).
  /// Restores the frame's saved argument snapshot, pushes a call stack entry,
  /// sets the async* context, and starts a dispatch loop.
  void _startAsyncStarBody(DarticFrame frame, DarticModule module) {
    // Restore the saved argument snapshot at the current stack top.
    restoreFrameStack(frame);

    final vBase = frame.savedVBase;
    final rBase = frame.savedRBase;

    // Cast upvalues from List<Object?> to List<Upvalue> (they were
    // constructed as List<Upvalue> in INIT_ASYNC_STAR).
    final upvalues = frame.upvalues.isNotEmpty
        ? frame.upvalues.cast<Upvalue>()
        : null;

    // Push a call stack entry for the async* body.
    callStack.pushFrame(
      funcId: frame.funcProto.funcId,
      returnPC: 0,
      savedFP: callStack.fp,
      savedVSP: vBase,
      savedRSP: rBase,
      resultReg: 0,
    );
    _upvalueStack.add(upvalues);

    // Set async* context.
    _currentAsyncStarFrame = frame;
    // Also set _currentAsyncFrame so AWAIT works inside async* bodies.
    _currentAsyncFrame = frame;

    try {
      _executeLoop(
        module,
        vBase,
        rBase,
        frame.funcProto.bytecode,
        frame.pc,
        upvalues,
      );
    } on Object catch (e, st) {
      // Uncaught exception from the async* body — route to the stream.
      final controller = frame.streamController;
      if (controller != null && !controller.isClosed) {
        controller.addError(e, st);
        controller.close();
      }
      _currentAsyncStarFrame = null;
      _currentAsyncFrame = null;
    }
  }

  /// Resumes a suspended async* generator frame (after pause/yield resume,
  /// cancel, or await completion).
  ///
  /// Called from onResume/onCancel callbacks or from await resume (via
  /// microtask). Similar to [_resumeFrame] but uses async* context.
  void _resumeAsyncStarFrame(DarticFrame frame, DarticModule module) {
    // Restore frame stack data at the current stack top.
    restoreFrameStack(frame);

    final vBase = frame.savedVBase;
    final rBase = frame.savedRBase;

    // Cast upvalues from List<Object?> to List<Upvalue>.
    final upvalues = frame.upvalues.isNotEmpty
        ? frame.upvalues.cast<Upvalue>()
        : null;

    // Push a call stack entry for the resumed frame.
    callStack.pushFrame(
      funcId: frame.funcProto.funcId,
      returnPC: 0,
      savedFP: callStack.fp,
      savedVSP: vBase,
      savedRSP: rBase,
      resultReg: 0,
    );
    _upvalueStack.add(upvalues);

    int pc = frame.pc;

    // Check if we're resuming with an exception (from a failed await).
    if (frame.resumeException != null) {
      final exception = frame.resumeException;
      final stackTrace = frame.resumeStackTrace;
      frame.resumeException = null;
      frame.resumeStackTrace = null;

      // Search at the AWAIT instruction's PC (pc - 1), not the resume PC.
      // The exception occurred during the await expression, so the AWAIT's
      // PC is the correct point for handler lookup. The resume PC (pc) may
      // fall outside the try handler's [startPC, endPC) range.
      final funcProto = frame.funcProto;
      final handler = _findHandler(
          funcProto, pc - 1, exception, module, rBase, refStack);
      if (handler != null) {
        refStack.clearRange(rBase + handler.refStackDP, refStack.sp);
        valueStack.sp = vBase + handler.valStackDP;
        refStack.sp = rBase + handler.refStackDP;
        refStack.write(rBase + handler.exceptionReg, exception);
        if (handler.stackTraceReg >= 0) {
          refStack.write(rBase + handler.stackTraceReg, stackTrace);
        }
        pc = handler.handlerPC;
      } else {
        // No handler found — add error to stream and close.
        valueStack.sp = vBase;
        refStack.sp = rBase;
        callStack.popFrame();
        _upvalueStack.removeLast();
        final controller = frame.streamController;
        if (controller != null && !controller.isClosed) {
          controller.addError(
              exception!,
              stackTrace is StackTrace ? stackTrace : StackTrace.empty);
          controller.close();
        }
        _currentAsyncStarFrame = null;
        _currentAsyncFrame = null;
        return;
      }
    } else if (frame.awaitDestReg >= 0) {
      // Normal resume from await: write resumeValue (may be null) to dest reg.
      refStack.write(rBase + frame.awaitDestReg, frame.resumeValue);
      frame.resumeValue = null;
    }

    // Set the async* frame context and start a new dispatch loop.
    _currentAsyncStarFrame = frame;
    _currentAsyncFrame = frame;
    try {
      _executeLoop(
        module,
        vBase,
        rBase,
        frame.funcProto.bytecode,
        pc,
        upvalues,
      );
    } on Object catch (e, st) {
      // Uncaught exception from the async* body — route to the stream.
      final controller = frame.streamController;
      if (controller != null && !controller.isClosed) {
        controller.addError(e, st);
        controller.close();
      }
      _currentAsyncStarFrame = null;
      _currentAsyncFrame = null;
    }
  }

  /// Drives a sync* generator frame synchronously until YIELD or completion.
  ///
  /// Called by [SyncStarIterator.moveNext]. On the first call,
  /// [capturedArgs] provides the argument snapshot to restore into the new
  /// frame's stack region. On subsequent calls (resume), the iterator's saved
  /// [DarticFrame] is restored via [restoreFrameStack].
  ///
  /// Returns [SyncStarStatus.yielded] when the generator yields a value
  /// (already set on [iterator] via [SyncStarIterator.setCurrent]), or
  /// [SyncStarStatus.done] when the generator body finishes.
  ///
  /// Exceptions thrown by the generator body propagate to the caller
  /// (i.e., to [SyncStarIterator.moveNext]).
  SyncStarStatus driveSyncStar(
    DarticFuncProto proto,
    int startPC,
    DarticModule module,
    SyncStarIterator<Object?> iterator, {
    List<Upvalue> upvalues = const [],
    ({List<int> valueSlots, List<Object?> refSlots})? capturedArgs,
  }) {
    final vs = valueStack;
    final rs = refStack;

    int vBase;
    int rBase;
    int pc;
    List<Upvalue>? loopUpvalues = upvalues.isNotEmpty ? upvalues : null;

    final existingFrame = iterator.frame;

    if (capturedArgs != null && existingFrame == null) {
      // First call: allocate stack space and restore captured arguments.
      vBase = vs.sp;
      rBase = rs.sp;
      vs.sp += proto.valueRegCount;
      rs.sp += proto.refRegCount;

      // Restore captured value slots.
      final vSlots = capturedArgs.valueSlots;
      for (var i = 0; i < vSlots.length; i++) {
        vs.writeInt(vBase + i, vSlots[i]);
      }

      // Restore captured ref slots.
      final rSlots = capturedArgs.refSlots;
      for (var i = 0; i < rSlots.length; i++) {
        rs.write(rBase + i, rSlots[i]);
      }

      pc = startPC;
    } else if (existingFrame != null) {
      // Resume: restore frame stack data at current stack top.
      restoreFrameStack(existingFrame);
      vBase = existingFrame.savedVBase;
      rBase = existingFrame.savedRBase;
      pc = existingFrame.pc;
    } else {
      throw DarticError('driveSyncStar: no frame and no capturedArgs');
    }

    // Push a call stack entry for this drive invocation.
    callStack.pushFrame(
      funcId: proto.funcId,
      returnPC: 0,
      savedFP: callStack.fp,
      savedVSP: vBase,
      savedRSP: rBase,
      resultReg: 0,
    );
    _upvalueStack.add(null);

    // Set sync* context so YIELD and RETURN_NULL know they're in a generator.
    final savedIterator = _activeSyncStarIterator;
    _activeSyncStarIterator = iterator;
    _syncStarStatus = null;
    _syncStarSuspendedFrame = null;

    try {
      _executeLoop(
        module,
        vBase,
        rBase,
        proto.bytecode,
        pc,
        loopUpvalues,
      );
    } on Object {
      // Exception from the generator body propagates to moveNext() caller.
      _activeSyncStarIterator = savedIterator;
      _syncStarStatus = null;
      _syncStarSuspendedFrame = null;
      rethrow;
    }

    // If YIELD suspended, store the suspended frame on the iterator for the
    // next moveNext() call.
    if (_syncStarSuspendedFrame != null) {
      iterator.frame = _syncStarSuspendedFrame;
      _syncStarSuspendedFrame = null;
    }

    _activeSyncStarIterator = savedIterator;
    final status = _syncStarStatus ?? SyncStarStatus.done;
    _syncStarStatus = null;
    return status;
  }

  /// Core dispatch loop shared by [_executeEntry] and [invokeClosure].
  ///
  /// Runs bytecode until HALT, HOST_BOUNDARY RETURN, or fuel exhaustion.
  /// Parameters are copied to hot-path locals for performance.
  void _executeLoop(
    DarticModule module,
    int vBase,
    int rBase,
    Uint32List code,
    int pc,
    List<Upvalue>? currentUpvalues,
  ) {
    final cp = module.constantPool;
    final vs = valueStack;
    final rs = refStack;

    // Push upvalue entry for the initial frame (entry or callback closure).
    _upvalueStack.add(currentUpvalues);

    // Helper: unwind frames searching for an exception handler starting at
    // [startPC]. If found, restores stacks, writes exception/stackTrace into
    // the handler's registers, and returns the handler PC. If no handler
    // exists, rethrows [exception] to the host VM.
    //
    // Side effects: mutates vBase, rBase, code, currentUpvalues via closure.
    int unwindToHandler(int startPC, Object? exception, Object? stackTrace) {
      var searchPC = startPC;
      while (true) {
        final funcProto = module.functions[callStack.funcId];
        final handler = _findHandler(
            funcProto, searchPC, exception, module, rBase, rs);
        if (handler != null) {
          rs.clearRange(rBase + handler.refStackDP, rs.sp);
          vs.sp = vBase + handler.valStackDP;
          rs.sp = rBase + handler.refStackDP;
          rs.write(rBase + handler.exceptionReg, exception);
          if (handler.stackTraceReg >= 0) {
            rs.write(rBase + handler.stackTraceReg, stackTrace);
          }
          return handler.handlerPC;
        }
        if (callStack.depth <= 1) throw exception!;
        rs.clearRange(rBase, rs.sp);
        vs.sp = vBase;
        rs.sp = rBase;
        final callerVSP = callStack.savedVSP;
        final callerRSP = callStack.savedRSP;
        searchPC = callStack.returnPC - 1;
        // Restore _currentAsyncFrame when unwinding past an async function
        // boundary.  Without this, ASYNC_RETURN in a catching caller would
        // complete the callee's Completer instead of its own.
        if (_currentAsyncFrame != null &&
            _currentAsyncFrame!.funcProto.funcId == callStack.funcId) {
          _currentAsyncFrame = _currentAsyncFrame!.callerAsyncFrame;
        }
        callStack.popFrame();
        // HOST_BOUNDARY: exception propagates to VM caller.
        if (callStack.isHostBoundary) {
          _upvalueStack.removeLast();
          throw exception!;
        }
        vBase = callerVSP;
        rBase = callerRSP;
        code = module.functions[callStack.funcId].bytecode;
        currentUpvalues = _upvalueStack.removeLast();
      }
    }

    // Cache the name index for 'noSuchMethod' — looked up lazily.
    var cachedNsmNameIdx = -2; // -2 = not yet computed
    int nsmNameIdx() {
      if (cachedNsmNameIdx == -2) {
        cachedNsmNameIdx = cp.lookupNameIndex('noSuchMethod');
      }
      return cachedNsmNameIdx;
    }

    // Helper: dispatch noSuchMethod on a receiver.
    //
    // For DarticObject: looks up 'noSuchMethod' in the class method table.
    //   - If found (user override): pushes a call frame for the override,
    //     places the Invocation at rBase+3, and returns true. The caller
    //     must NOT write the result register — the RETURN instruction will.
    //   - If not found (no override): calls the host-side Object.noSuchMethod
    //     which throws NoSuchMethodError. Routes through unwindToHandler.
    //
    // For host objects: calls Object.noSuchMethod on the receiver (which
    //   throws NoSuchMethodError). Routes through unwindToHandler.
    //
    // Returns true if a user-defined noSuchMethod was dispatched as a
    // frame push (caller should `continue` the dispatch loop).
    // Returns false if the exception was routed to an exception handler
    // (caller should jump to the returned PC).
    (bool pushed, int handlerPC) dispatchNoSuchMethod(
      Object receiver,
      Invocation invocation,
      int resultReg,
    ) {
      if (receiver is DarticObject) {
        final idx = nsmNameIdx();
        if (idx >= 0) {
          final classInfo = module.classes[receiver.classId];
          final nsmMethod = classInfo.methods[idx];
          if (nsmMethod != null) {
            // User has overridden noSuchMethod — push frame.
            if (vs.sp + nsmMethod.valueRegCount > vs.capacity ||
                rs.sp + nsmMethod.refRegCount > rs.capacity) {
              throw DarticError('Stack overflow');
            }
            if (callStack.depth >= callStack.maxFrames) {
              throw DarticError('Maximum call depth exceeded');
            }
            callStack.pushFrame(
              funcId: nsmMethod.funcId,
              returnPC: pc,
              savedFP: callStack.fp,
              savedVSP: vBase,
              savedRSP: rBase,
              resultReg: resultReg,
            );
            _upvalueStack.add(currentUpvalues);
            currentUpvalues = null;
            vBase = vs.sp;
            rBase = rs.sp;
            vs.sp += nsmMethod.valueRegCount;
            rs.sp += nsmMethod.refRegCount;
            // Place receiver at callee's rsp+2 (this), invocation at rsp+3.
            rs.write(rBase + 2, receiver);
            rs.write(rBase + 3, invocation);
            code = nsmMethod.bytecode;
            pc = 0;
            return (true, 0);
          }
        }
      }
      // No user override or host object: throw NoSuchMethodError.
      try {
        // ignore: unnecessary_cast
        (receiver as dynamic).noSuchMethod(invocation);
      } on Object catch (e, st) {
        final handlerPC = unwindToHandler(pc - 1, e, st);
        return (false, handlerPC);
      }
      // Should not reach here, but if it does, rethrow.
      throw NoSuchMethodError.withInvocation(receiver, invocation);
    }

    while (_fuel-- > 0) {
      final instr = code[pc++];
      final op = instr & 0xFF;

      switch (op) {
        // ── Load/Store (0x00-0x0B) ──

        case Op.nop: // NOP
          break;

        case Op.loadConst: // LOAD_CONST A, Bx — refStack[A] = constPool.refs[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          rs.write(rBase + a, cp.getRef(bx));

        case Op.loadNull: // LOAD_NULL A — refStack[A] = null
          rs.write(rBase + ((instr >> 8) & 0xFF), null);

        case Op.loadTrue: // LOAD_TRUE A — valueStack[A] = 1
          vs.writeInt(vBase + ((instr >> 8) & 0xFF), 1);

        case Op.loadFalse: // LOAD_FALSE A — valueStack[A] = 0
          vs.writeInt(vBase + ((instr >> 8) & 0xFF), 0);

        case Op.loadInt: // LOAD_INT A, sBx — valueStack[A] = sBx
          final a = (instr >> 8) & 0xFF;
          final sbx = ((instr >> 16) & 0xFFFF) - 0x7FFF;
          vs.writeInt(vBase + a, sbx);

        case Op.loadConstInt: // LOAD_CONST_INT A, Bx — valueStack[A] = intPool[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          vs.writeInt(vBase + a, cp.getInt(bx));

        case Op.loadConstDbl: // LOAD_CONST_DBL A, Bx — doubleView[A] = dblPool[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          vs.writeDouble(vBase + a, cp.getDouble(bx));

        case Op.moveRef: // MOVE_REF A, B — refStack[A] = refStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          rs.write(rBase + a, rs.read(rBase + b));

        case Op.moveVal: // MOVE_VAL A, B — valueStack[A] = valueStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b));

        case Op.loadUpvalue: // LOAD_UPVALUE A, Bx — refStack[A] = upvalue[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          final uv = currentUpvalues![bx];
          rs.write(
            rBase + a,
            uv.isOpen ? rs.read(uv.stackIndex) : uv.value,
          );

        case Op.storeUpvalue: // STORE_UPVALUE A, Bx — upvalue[Bx] = refStack[A]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          final uv = currentUpvalues![bx];
          final val = rs.read(rBase + a);
          if (uv.isOpen) {
            rs.write(uv.stackIndex, val);
          } else {
            uv.value = val;
          }

        // ── Type Conversion & Boxing (0x25-0x2D) ──
        // (intToDbl/dblToInt handled below in Float Arithmetic section)

        case Op.boxInt: // BOX_INT A, B — refStack[A] = valueStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          rs.write(rBase + a, vs.readInt(vBase + b));

        case Op.boxDouble: // BOX_DOUBLE A, B — refStack[A] = doubleView[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          rs.write(rBase + a, vs.readDouble(vBase + b));

        case Op.boxBool: // BOX_BOOL A, B — refStack[A] = (valueStack[B] != 0)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          rs.write(rBase + a, vs.readInt(vBase + b) != 0);

        case Op.unboxInt: // UNBOX_INT A, B — valueStack[A] = refStack[B] as int
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, rs.read(rBase + b) as int);

        case Op.unboxDouble: // UNBOX_DOUBLE A, B — doubleView[A] = refStack[B] as double
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeDouble(vBase + a, rs.read(rBase + b) as double);

        case Op.unboxBool: // UNBOX_BOOL A, B — valueStack[A] = (refStack[B] as bool) ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, (rs.read(rBase + b) as bool) ? 1 : 0);

        case Op.notBool: // NOT_BOOL A, B — valueStack[A] = valueStack[B] ^ 1
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) ^ 1);

        // ── Integer Arithmetic (0x10-0x1F) ──

        case Op.addInt: // ADD_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) + vs.readInt(vBase + c));

        case Op.subInt: // SUB_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) - vs.readInt(vBase + c));

        case Op.mulInt: // MUL_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) * vs.readInt(vBase + c));

        case Op.divInt: // DIV_INT A, B, C (truncating ~/)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) ~/ vs.readInt(vBase + c));

        case Op.modInt: // MOD_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) % vs.readInt(vBase + c));

        case Op.negInt: // NEG_INT A, B
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, -vs.readInt(vBase + b));

        case Op.bitAnd: // BIT_AND A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) & vs.readInt(vBase + c));

        case Op.bitOr: // BIT_OR A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) | vs.readInt(vBase + c));

        case Op.bitXor: // BIT_XOR A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) ^ vs.readInt(vBase + c));

        case Op.bitNot: // BIT_NOT A, B
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, ~vs.readInt(vBase + b));

        case Op.shl: // SHL A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) << vs.readInt(vBase + c));

        case Op.shr: // SHR A, B, C (arithmetic)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) >> vs.readInt(vBase + c));

        case Op.ushr: // USHR A, B, C (unsigned / logical)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) >>> vs.readInt(vBase + c));

        case Op.addIntImm: // ADD_INT_IMM A, B, C (C is unsigned 8-bit immediate)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a, vs.readInt(vBase + b) + c);

        // ── Float Arithmetic (0x20-0x2F) ──

        case Op.addDbl: // ADD_DBL A, B, C — doubleView[A] = doubleView[B] + doubleView[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeDouble(
              vBase + a, vs.readDouble(vBase + b) + vs.readDouble(vBase + c));

        case Op.subDbl: // SUB_DBL A, B, C — doubleView[A] = doubleView[B] - doubleView[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeDouble(
              vBase + a, vs.readDouble(vBase + b) - vs.readDouble(vBase + c));

        case Op.mulDbl: // MUL_DBL A, B, C — doubleView[A] = doubleView[B] * doubleView[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeDouble(
              vBase + a, vs.readDouble(vBase + b) * vs.readDouble(vBase + c));

        case Op.divDbl: // DIV_DBL A, B, C — doubleView[A] = doubleView[B] / doubleView[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeDouble(
              vBase + a, vs.readDouble(vBase + b) / vs.readDouble(vBase + c));

        case Op.modDbl: // MOD_DBL A, B, C — doubleView[A] = doubleView[B] % doubleView[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeDouble(
              vBase + a, vs.readDouble(vBase + b) % vs.readDouble(vBase + c));

        case Op.negDbl: // NEG_DBL A, B — doubleView[A] = -doubleView[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeDouble(vBase + a, -vs.readDouble(vBase + b));

        case Op.intToDbl: // INT_TO_DBL A, B — doubleView[A] = intView[B].toDouble()
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeDouble(vBase + a, vs.readInt(vBase + b).toDouble());

        case Op.dblToInt: // DBL_TO_INT A, B — intView[A] = doubleView[B].toInt()
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          vs.writeInt(vBase + a, vs.readDouble(vBase + b).toInt());

        // ── Comparison (0x30-0x3F) ──

        case Op.ltInt: // LT_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) < vs.readInt(vBase + c) ? 1 : 0);

        case Op.leInt: // LE_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readInt(vBase + b) <= vs.readInt(vBase + c) ? 1 : 0);

        case Op.gtInt: // GT_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(
              vBase + a, vs.readInt(vBase + b) > vs.readInt(vBase + c) ? 1 : 0);

        case Op.geInt: // GE_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readInt(vBase + b) >= vs.readInt(vBase + c) ? 1 : 0);

        case Op.eqInt: // EQ_INT A, B, C
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readInt(vBase + b) == vs.readInt(vBase + c) ? 1 : 0);

        case Op.ltDbl: // LT_DBL A, B, C — valueStack[A] = doubleView[B] < doubleView[C] ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readDouble(vBase + b) < vs.readDouble(vBase + c) ? 1 : 0);

        case Op.leDbl: // LE_DBL A, B, C — valueStack[A] = doubleView[B] <= doubleView[C] ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readDouble(vBase + b) <= vs.readDouble(vBase + c) ? 1 : 0);

        case Op.gtDbl: // GT_DBL A, B, C — valueStack[A] = doubleView[B] > doubleView[C] ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readDouble(vBase + b) > vs.readDouble(vBase + c) ? 1 : 0);

        case Op.geDbl: // GE_DBL A, B, C — valueStack[A] = doubleView[B] >= doubleView[C] ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readDouble(vBase + b) >= vs.readDouble(vBase + c) ? 1 : 0);

        case Op.eqDbl: // EQ_DBL A, B, C — valueStack[A] = doubleView[B] == doubleView[C] ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              vs.readDouble(vBase + b) == vs.readDouble(vBase + c) ? 1 : 0);

        case Op.eqRef: // EQ_REF A, B, C — identical(refStack[B], refStack[C])
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              identical(rs.read(rBase + b), rs.read(rBase + c)) ? 1 : 0);

        case Op.eqGeneric: // EQ_GENERIC A, B, C — valueStack[A] = refStack[B] == refStack[C] ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          vs.writeInt(vBase + a,
              rs.read(rBase + b) == rs.read(rBase + c) ? 1 : 0);

        // ── Control Flow (0x40-0x4F) ──

        case Op.jump: // JUMP sBx — PC += sBx (A unused)
          pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;

        case Op.jumpIfTrue: // JUMP_IF_TRUE A, sBx — if valueStack[A] != 0
          if (vs.readInt(vBase + ((instr >> 8) & 0xFF)) != 0) {
            pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
          }

        case Op.jumpIfFalse: // JUMP_IF_FALSE A, sBx — if valueStack[A] == 0
          if (vs.readInt(vBase + ((instr >> 8) & 0xFF)) == 0) {
            pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
          }

        case Op.jumpIfNull: // JUMP_IF_NULL A, sBx — if refStack[A] == null
          if (rs.read(rBase + ((instr >> 8) & 0xFF)) == null) {
            pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
          }

        case Op.jumpIfNnull: // JUMP_IF_NNULL A, sBx — if refStack[A] != null
          if (rs.read(rBase + ((instr >> 8) & 0xFF)) != null) {
            pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
          }

        case Op.jumpAx: // JUMP_AX sAx — PC += sAx (24-bit signed)
          pc += ((instr >> 8) & 0xFFFFFF) - 0x7FFFFF;

        // ── Call/Return (0x50-0x5F) ──

        case Op.call: // CALL A, B, C — call closure in refStack[B], result→reg A
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final closure = rs.read(rBase + b) as DarticClosure;
          final callee = closure.funcProto;

          // Overflow and call depth checks.
          if (vs.sp + callee.valueRegCount > vs.capacity ||
              rs.sp + callee.refRegCount > rs.capacity) {
            throw DarticError('Stack overflow');
          }
          if (callStack.depth >= callStack.maxFrames) {
            throw DarticError('Maximum call depth exceeded');
          }

          // Push frame — save caller state.
          callStack.pushFrame(
            funcId: callee.funcId,
            returnPC: pc,
            savedFP: callStack.fp,
            savedVSP: vBase,
            savedRSP: rBase,
            resultReg: a,
          );

          // Save caller's upvalues and switch to closure's upvalues.
          _upvalueStack.add(currentUpvalues);
          currentUpvalues = closure.upvalues;

          // Advance to callee frame.
          vBase = vs.sp;
          rBase = rs.sp;
          vs.sp += callee.valueRegCount;
          rs.sp += callee.refRegCount;

          // Switch to callee bytecode.
          code = callee.bytecode;
          pc = 0;

        case Op.callStatic: // CALL_STATIC A, Bx — call functions[Bx], result→reg A
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          final callee = module.functions[bx];

          // Overflow and call depth checks.
          if (vs.sp + callee.valueRegCount > vs.capacity ||
              rs.sp + callee.refRegCount > rs.capacity) {
            throw DarticError('Stack overflow');
          }
          if (callStack.depth >= callStack.maxFrames) {
            throw DarticError('Maximum call depth exceeded');
          }

          // Push frame — save caller state.
          callStack.pushFrame(
            funcId: callee.funcId,
            returnPC: pc,
            savedFP: callStack.fp,
            savedVSP: vBase,
            savedRSP: rBase,
            resultReg: a,
          );

          // Save caller's upvalues; static calls have no closure upvalues.
          _upvalueStack.add(currentUpvalues);
          currentUpvalues = null;

          // Advance to callee frame.
          vBase = vs.sp;
          rBase = rs.sp;
          vs.sp += callee.valueRegCount;
          rs.sp += callee.refRegCount;

          // Switch to callee bytecode.
          code = callee.bytecode;
          pc = 0;

        case Op.callHost: // CALL_HOST A, Bx — host function call (no frame push)
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;

          // Look up the runtime binding ID from the resolved map.
          final bindingMap = _bindingIdMap;
          if (bx >= bindingMap.length) {
            throw DarticError(
              'CALL_HOST binding index $bx out of range '
              '(table size: ${bindingMap.length})',
            );
          }
          final runtimeId = bindingMap[bx];
          if (runtimeId < 0) {
            final name = module.bindingNames[bx].name;
            throw DarticError('Unresolved host binding: $name');
          }

          // Collect args from ref stack: r[A+1], r[A+2], ..., r[A+argCount].
          final argCount = module.bindingNames[bx].argCount;
          final hostArgs = List<Object?>.generate(
            argCount,
            (i) => rs.read(rBase + a + 1 + i),
          );

          _wrapClosureArgs(hostArgs);

          // Invoke the host function and write result to refStack[A].
          try {
            final result = hostFunctionRegistry!.invoke(runtimeId, hostArgs);
            rs.write(rBase + a, result);
          } on Object catch (e, st) {
            // Host function threw — route through the exception handler.
            pc = unwindToHandler(pc - 1, e, st);
          }

        case Op.callVirtual: // CALL_VIRTUAL A, B, C — virtual method dispatch
          final a = (instr >> 8) & 0xFF; // result register
          final b = (instr >> 16) & 0xFF; // receiver register
          final c = (instr >> 24) & 0xFF; // IC table index

          // Read receiver and IC entry up front.
          final receiver = rs.read(rBase + b);
          final ic = module.functions[callStack.funcId].icTable[c];

          if (receiver is! DarticObject) {
            final methodName = cp.getName(ic.methodNameIndex);
            if (receiver == null) {
              throw DarticError(
                'NoSuchMethodError: method "$methodName" called on null',
              );
            }
            // Non-DarticObject: try HostDispatcher dynamic dispatch.
            // NOTE: only zero-arg getters are supported here — method calls on
            // host objects with arguments should go through CALL_HOST (compiler
            // routes them there for statically-typed receivers) or INVOKE_DYN
            // (for dynamic receivers). This fallback handles the edge case where
            // a zero-arg method/getter ends up via CALL_VIRTUAL.
            final hostWrapper = _hostClassRegistry?.lookup(receiver);
            if (hostWrapper != null) {
              final hostResult =
                  hostWrapper.getProperty(receiver, methodName);
              if (!identical(hostResult, BindingLookupDispatcher.notFound)) {
                rs.write(rBase + a, hostResult);
                continue;
              }
            }
            // noSuchMethod fallback for host objects.
            final nsmInvocation = _buildVirtualInvocation(
                ic, methodName, rBase + b, rs);
            final (nsmPushed, nsmHandlerPC) =
                dispatchNoSuchMethod(receiver, nsmInvocation, a);
            if (nsmPushed) continue;
            pc = nsmHandlerPC;
            continue;
          }

          // IC dispatch.
          DarticFuncProto callee;
          if (ic.cachedClassId == receiver.classId) {
            // IC hit — fast path.
            callee = module.functions[ic.cachedFuncId];
          } else {
            // IC miss — slow path: look up method in class info.
            final classInfo = module.classes[receiver.classId];
            final method = classInfo.methods[ic.methodNameIndex];
            if (method == null) {
              // noSuchMethod fallback for DarticObject.
              final name = cp.getName(ic.methodNameIndex);
              final nsmInvocation = _buildVirtualInvocation(
                  ic, name, rBase + b, rs);
              final (nsmPushed, nsmHandlerPC) =
                  dispatchNoSuchMethod(receiver, nsmInvocation, a);
              if (nsmPushed) continue;
              pc = nsmHandlerPC;
              continue;
            }
            callee = method;
            // Update IC cache.
            ic.cachedClassId = receiver.classId;
            ic.cachedFuncId = callee.funcId;
          }

          // Overflow and call depth checks.
          if (vs.sp + callee.valueRegCount > vs.capacity ||
              rs.sp + callee.refRegCount > rs.capacity) {
            throw DarticError('Stack overflow');
          }
          if (callStack.depth >= callStack.maxFrames) {
            throw DarticError('Maximum call depth exceeded');
          }

          // Push frame — save caller state.
          callStack.pushFrame(
            funcId: callee.funcId,
            returnPC: pc,
            savedFP: callStack.fp,
            savedVSP: vBase,
            savedRSP: rBase,
            resultReg: a,
          );

          // Save caller's upvalues.
          _upvalueStack.add(currentUpvalues);
          currentUpvalues = null;

          // Advance to callee frame.
          vBase = vs.sp;
          rBase = rs.sp;
          vs.sp += callee.valueRegCount;
          rs.sp += callee.refRegCount;

          // Place receiver at callee's rsp+2 (the `this` slot).
          rs.write(rBase + 2, receiver);

          // Auto-load ITA from receiver's runtimeType_ for generic classes.
          final rtType = receiver.runtimeType_;
          if (rtType is DarticInterfaceType && rtType.typeArgs.isNotEmpty) {
            rs.write(rBase + 0, rtType.typeArgs);
          }

          // Switch to callee bytecode.
          code = callee.bytecode;
          pc = 0;

        case Op.callSuper: // CALL_SUPER A, Bx — call super method functions[Bx], result→reg A
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          final callee = module.functions[bx];

          // Overflow and call depth checks.
          if (vs.sp + callee.valueRegCount > vs.capacity ||
              rs.sp + callee.refRegCount > rs.capacity) {
            throw DarticError('Stack overflow');
          }
          if (callStack.depth >= callStack.maxFrames) {
            throw DarticError('Maximum call depth exceeded');
          }

          // Push frame — save caller state.
          callStack.pushFrame(
            funcId: callee.funcId,
            returnPC: pc,
            savedFP: callStack.fp,
            savedVSP: vBase,
            savedRSP: rBase,
            resultReg: a,
          );

          // Save caller's upvalues; super calls have no closure upvalues.
          _upvalueStack.add(currentUpvalues);
          currentUpvalues = null;

          // Advance to callee frame.
          final callerRBase = rBase;
          vBase = vs.sp;
          rBase = rs.sp;
          vs.sp += callee.valueRegCount;
          rs.sp += callee.refRegCount;

          // Auto-load ITA from caller's `this` (rsp+2) runtimeType_ for
          // generic classes, so super methods can access class type params.
          final thisObj = rs.read(callerRBase + 2);
          if (thisObj is DarticObject) {
            final rtType = thisObj.runtimeType_;
            if (rtType is DarticInterfaceType && rtType.typeArgs.isNotEmpty) {
              rs.write(rBase + 0, rtType.typeArgs);
            }
          }

          // Switch to callee bytecode.
          code = callee.bytecode;
          pc = 0;

        // RETURN_REF / RETURN_VAL / RETURN_NULL share identical frame-restore
        // logic. The only difference: what is captured before and written after.
        case Op.returnRef: // RETURN_REF A — return refStack[A] to caller
        case Op.returnVal: // RETURN_VAL A — return valueStack[A] to caller
        case Op.returnNull: // RETURN_NULL — return null to caller
          // sync* generator: RETURN_NULL signals generator done.
          if (op == Op.returnNull && _activeSyncStarIterator != null) {
            _syncStarStatus = SyncStarStatus.done;
            // Clean up stacks and return from _executeLoop.
            rs.clearRange(rBase, rs.sp);
            vs.sp = vBase;
            rs.sp = rBase;
            callStack.popFrame();
            _upvalueStack.removeLast();
            return;
          }

          // async* generator: RETURN_NULL signals generator done ->
          // controller.close().
          if (op == Op.returnNull && _currentAsyncStarFrame != null) {
            final asyncStarFrame = _currentAsyncStarFrame!;
            final controller = asyncStarFrame.streamController;
            if (controller != null && !controller.isClosed) {
              controller.close();
            }
            // Clean up stacks and return from _executeLoop.
            rs.clearRange(rBase, rs.sp);
            vs.sp = vBase;
            rs.sp = rBase;
            callStack.popFrame();
            _upvalueStack.removeLast();
            _currentAsyncStarFrame = null;
            return;
          }

          // Capture return value before frame teardown.
          final Object? retRef;
          final int retVal;
          final int retValIdx; // absolute value-stack index for HOST_BOUNDARY reads
          if (op == Op.returnRef) {
            retRef = rs.read(rBase + ((instr >> 8) & 0xFF));
            retVal = 0;
            retValIdx = 0;
          } else if (op == Op.returnVal) {
            retRef = null;
            retValIdx = vBase + ((instr >> 8) & 0xFF);
            retVal = vs.readInt(retValIdx);
          } else {
            retRef = null;
            retVal = 0;
            retValIdx = 0;
          }

          // Read caller state from current (callee) frame.
          final calleeFuncId = callStack.funcId;
          final callerVSP = callStack.savedVSP;
          final callerRSP = callStack.savedRSP;
          final retPC = callStack.returnPC;
          final resReg = callStack.resultReg;

          // Clear callee's ref slots for GC safety.
          rs.clearRange(rBase, rs.sp);

          // Restore stack pointers (deallocate callee frame).
          vs.sp = vBase;
          rs.sp = rBase;
          vBase = callerVSP;
          rBase = callerRSP;

          // Pop callee frame, then check for HOST_BOUNDARY.
          callStack.popFrame();

          if (callStack.isHostBoundary) {
            // Callback complete — store result for invokeClosure to read.
            // At HOST_BOUNDARY, value-stack results cross into Dart Object? land,
            // so we must read with the correct view based on returnKind.
            if (op == Op.returnVal) {
              switch (module.functions[calleeFuncId].returnKind) {
                case StackKind.boolDefault:
                  _callbackResult = retVal != 0;
                case StackKind.doubleDefault:
                  _callbackResult = vs.readDouble(retValIdx);
                default: // intVal or ref (shouldn't be ref for RETURN_VAL)
                  _callbackResult = retVal;
              }
            } else {
              _callbackResult = retRef;
            }
            _upvalueStack.removeLast();
            return;
          }

          // Normal return — look up caller's bytecode.
          code = module.functions[callStack.funcId].bytecode;
          pc = retPC;

          // Restore caller's upvalues.
          currentUpvalues = _upvalueStack.removeLast();

          // Write return value to caller's register.
          if (op == Op.returnVal) {
            vs.writeInt(callerVSP + resReg, retVal);
          } else {
            rs.write(callerRSP + resReg, retRef);
          }

        // ── Global Variables (0xA0-0xA1) ──

        case Op.loadGlobal: // LOAD_GLOBAL A, Bx — refStack[A] = globals[Bx]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          rs.write(rBase + a, _globalTable!.load(bx));

        case Op.storeGlobal: // STORE_GLOBAL A, Bx — globals[Bx] = refStack[A]
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          _globalTable!.store(bx, rs.read(rBase + a));

        // ── Object Operations (0x60-0x64) ──

        case Op.getFieldRef: // GET_FIELD_REF A, B, C — refStack[A] = refStack[B].refFields[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final obj = rs.read(rBase + b) as DarticObject;
          rs.write(rBase + a, obj.refFields[c]);

        case Op.setFieldRef: // SET_FIELD_REF A, B, C — refStack[A].refFields[C] = refStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final obj = rs.read(rBase + a) as DarticObject;
          obj.refFields[c] = rs.read(rBase + b);

        case Op.getFieldVal: // GET_FIELD_VAL A, B, C — valueStack[A] = refStack[B].valueFields[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final obj = rs.read(rBase + b) as DarticObject;
          vs.writeInt(vBase + a, obj.valueFields[c]);

        case Op.setFieldVal: // SET_FIELD_VAL A, B, C — refStack[A].valueFields[C] = valueStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final obj = rs.read(rBase + a) as DarticObject;
          obj.valueFields[c] = vs.readInt(vBase + b);

        case Op.newInstance: // NEW_INSTANCE A, Bx — refStack[A] = new DarticObject(class[Bx])
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          final classInfo = module.classes[bx];
          rs.write(rBase + a, DarticObject(classInfo));

        // ── Type Operations (0x65-0x66) ──

        case Op.instanceOf: // INSTANCEOF A, B, C — valStack[A] = isSubtypeOf(extractType(refStack[B]), refStack[C]) ? 1 : 0
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final targetType = rs.read(rBase + c) as DarticType;
          final value = rs.read(rBase + b);
          final checker = _subtypeChecker!;
          final reg = _activeTypeRegistry!;
          final objType = extractType(value, reg, module.classes);
          vs.writeInt(vBase + a, checker.isSubtypeOf(objType, targetType) ? 1 : 0);

        case Op.cast: // CAST A, B, C — refStack[A] = refStack[B] if subtype, else throw TypeError
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final targetType = rs.read(rBase + c) as DarticType;
          final value = rs.read(rBase + b);
          final checker = _subtypeChecker!;
          final reg = _activeTypeRegistry!;
          final objType = extractType(value, reg, module.classes);
          if (checker.isSubtypeOf(objType, targetType)) {
            rs.write(rBase + a, value);
          } else {
            throw TypeError();
          }

        // ── Exception Handling (0xA4-0xA5) ──

        case Op.throw_: // THROW A — throw refStack[A]
          final a = (instr >> 8) & 0xFF;
          final exception = rs.read(rBase + a);
          pc = unwindToHandler(pc - 1, exception, StackTrace.current);

        case Op.rethrow_: // RETHROW A, B — rethrow refStack[A] with stackTrace refStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final exception = rs.read(rBase + a);
          // Read stackTrace BEFORE unwinding — the source register may fall
          // within the range that gets nullified during stack unwinding.
          final stackTrace = b > 0 ? rs.read(rBase + b) : null;
          pc = unwindToHandler(pc - 1, exception, stackTrace);

        case Op.assert_: // ASSERT A, Bx — if valueStack[A] == 0 → throw AssertionError
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          if (vs.readInt(vBase + a) == 0) {
            final message =
                bx != 0xFFFF ? module.constantPool.getRef(bx) : null;
            final exception = AssertionError(message?.toString());
            pc = unwindToHandler(pc - 1, exception, StackTrace.current);
          }

        // ── Closure (0x70-0x71) ──

        case Op.closure: // CLOSURE A, Bx — refStack[A] = DarticClosure(funcProto[Bx])
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          final proto = module.functions[bx];
          final upvalues = <Upvalue>[];
          for (final desc in proto.upvalueDescriptors) {
            if (desc.isLocal) {
              final absIndex = rBase + desc.index;
              upvalues.add(
                _openUpvalues.putIfAbsent(
                    absIndex, () => Upvalue.open(absIndex)),
              );
            } else {
              upvalues.add(currentUpvalues![desc.index]);
            }
          }
          rs.write(
            rBase + a,
            DarticClosure(funcProto: proto, upvalues: upvalues),
          );

        case Op.closeUpvalue: // CLOSE_UPVALUE A — close all open upvalues at rBase+A and above
          final minIndex = rBase + ((instr >> 8) & 0xFF);
          _openUpvalues.removeWhere((stackIndex, uv) {
            if (stackIndex >= minIndex) {
              uv.close(rs.read(stackIndex));
              return true;
            }
            return false;
          });

        // ── Generics & Types (0x78-0x7F) ──

        case Op.pushIta: // PUSH_ITA A — refStack[A] = refStack[0] (ITA slot)
          rs.write(
            rBase + ((instr >> 8) & 0xFF),
            rs.read(rBase + 0),
          );

        case Op.pushFta: // PUSH_FTA A — refStack[A] = refStack[1] (FTA slot)
          rs.write(
            rBase + ((instr >> 8) & 0xFF),
            rs.read(rBase + 1),
          );

        case Op.loadTypeArg: // LOAD_TYPE_ARG A, B, C — refStack[A] = (refStack[B] as List<DarticType>)[C]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final typeArgs = rs.read(rBase + b) as List<DarticType>;
          rs.write(rBase + a, typeArgs[c]);

        case Op.instantiateType: // INSTANTIATE_TYPE A, Bx — refStack[A] = resolveType(constPool.refs[Bx], ITA, FTA)
          final a = (instr >> 8) & 0xFF;
          final bx = (instr >> 16) & 0xFFFF;
          final template = cp.getRef(bx) as TypeTemplate;
          final ita = rs.read(rBase + 0) as List<DarticType>?;
          final fta = rs.read(rBase + 1) as List<DarticType>?;
          rs.write(
              rBase + a, resolveType(template, ita, fta, _activeTypeRegistry!));

        case Op.createTypeArgs: // CREATE_TYPE_ARGS A, B, C — refStack[C] = [refStack[B]..refStack[B+A-1]]
          final count = (instr >> 8) & 0xFF;
          final startReg = (instr >> 16) & 0xFF;
          final destReg = (instr >> 24) & 0xFF;
          final typeArgs = <DarticType>[
            for (var i = 0; i < count; i++)
              rs.read(rBase + startReg + i) as DarticType,
          ];
          rs.write(rBase + destReg, typeArgs);

        case Op.allocGeneric: // ALLOC_GENERIC A, B — refStack[A] = new DarticObject with runtimeType from refStack[B]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final type = rs.read(rBase + b) as DarticInterfaceType;
          final classInfo = module.classes[type.classId];
          final obj = DarticObject(classInfo);
          obj.runtimeType_ = type;
          rs.write(rBase + a, obj);

        // ── Null Safety (0xA7) ──

        case Op.nullCheck: // NULL_CHECK A — if refStack[A] == null → throw
          if (rs.read(rBase + ((instr >> 8) & 0xFF)) == null) {
            throw DarticError(
                'Null check operator used on a null value');
          }

        // ── Collection Creation (0x90-0x92) ──

        case Op.createList: // CREATE_LIST A, B, C — refStack[A] = List from refStack[B..B+C-1]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final list = List<Object?>.generate(c, (i) => rs.read(rBase + b + i));
          rs.write(rBase + a, list);

        case Op.createMap: // CREATE_MAP A, B, C — refStack[A] = Map from C key/value pairs starting at B
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final map = <Object?, Object?>{};
          for (var i = 0; i < c; i++) {
            final key = rs.read(rBase + b + i * 2);
            final value = rs.read(rBase + b + i * 2 + 1);
            map[key] = value;
          }
          rs.write(rBase + a, map);

        case Op.createSet: // CREATE_SET A, B, C — refStack[A] = Set from refStack[B..B+C-1]
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final set = <Object?>{};
          for (var i = 0; i < c; i++) {
            set.add(rs.read(rBase + b + i));
          }
          rs.write(rBase + a, set);

        // ── String & Dynamic (0x98-0x9F) ──

        case Op.stringInterp: // STRING_INTERP A, B, C — refStack[A] = concat(refStack[B..B+C-1])
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final buf = StringBuffer();
          for (var i = 0; i < c; i++) {
            final part = rs.read(rBase + b + i);
            buf.write(part);
          }
          rs.write(rBase + a, buf.toString());

        // ── Dynamic Dispatch (0x67-0x68, 0x9A) ──

        case Op.getFieldDyn: // GET_FIELD_DYN A, B, C — refStack[A] = refStack[B].getProperty(names[C])
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final receiver = rs.read(rBase + b);
          final name = cp.getName(c);
          if (receiver == null) {
            throw DarticError(
              'NoSuchMethodError: getter "$name" called on null',
            );
          }

          // DarticObject: look up field, then getter method.
          if (receiver is DarticObject) {
            final classInfo = module.classes[receiver.classId];
            final nameIdx = cp.lookupNameIndex(name);
            // Try field lookup first.
            if (nameIdx >= 0) {
              final fieldLayout = classInfo.fields[nameIdx];
              if (fieldLayout != null) {
                final fieldVal = switch (fieldLayout.kind) {
                  StackKind.ref => receiver.refFields[fieldLayout.offset],
                  StackKind.doubleVal => receiver.valueFields.buffer
                      .asFloat64List()[fieldLayout.offset],
                  StackKind.boolVal =>
                    receiver.valueFields[fieldLayout.offset] != 0,
                  StackKind.intVal =>
                    receiver.valueFields[fieldLayout.offset],
                };
                rs.write(rBase + a, fieldVal);
                continue;
              }
              // Try getter method — call via _callDarticMethod for boxing.
              final getter = classInfo.methods[nameIdx];
              if (getter != null) {
                try {
                  final getterResult =
                      _callDarticMethod(module, getter, receiver, const []);
                  rs.write(rBase + a, getterResult);
                } on Object catch (e, st) {
                  pc = unwindToHandler(pc - 1, e, st);
                }
                continue;
              }
            }
            // noSuchMethod fallback.
            final nsmInvocation = DarticInvocation.getter(Symbol(name));
            final (nsmPushed, nsmHandlerPC) =
                dispatchNoSuchMethod(receiver, nsmInvocation, a);
            if (nsmPushed) continue;
            pc = nsmHandlerPC;
            continue;
          }

          // Host object: try HostDispatcher.
          final hostWrapper = _hostClassRegistry?.lookup(receiver);
          if (hostWrapper != null) {
            final hostResult = hostWrapper.getProperty(receiver, name);
            if (!identical(hostResult, BindingLookupDispatcher.notFound)) {
              rs.write(rBase + a, hostResult);
              continue;
            }
          }
          // noSuchMethod fallback for host objects.
          final invocation = DarticInvocation.getter(Symbol(name));
          final (pushed, handlerPC) =
              dispatchNoSuchMethod(receiver, invocation, a);
          if (pushed) continue;
          pc = handlerPC;
          continue;

        case Op.setFieldDyn: // SET_FIELD_DYN A, B, C — refStack[A].setProperty(names[C], refStack[B])
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          final c = (instr >> 24) & 0xFF;
          final receiver = rs.read(rBase + a);
          final value = rs.read(rBase + b);
          final name = cp.getName(c);
          if (receiver == null) {
            throw DarticError(
              'NoSuchMethodError: setter "$name" called on null',
            );
          }

          // DarticObject: look up field, then setter method.
          if (receiver is DarticObject) {
            final classInfo = module.classes[receiver.classId];
            final nameIdx = cp.lookupNameIndex(name);
            // Try field write first.
            if (nameIdx >= 0) {
              final fieldLayout = classInfo.fields[nameIdx];
              if (fieldLayout != null) {
                switch (fieldLayout.kind) {
                  case StackKind.ref:
                    receiver.refFields[fieldLayout.offset] = value;
                  case StackKind.doubleVal:
                    receiver.valueFields.buffer
                        .asFloat64List()[fieldLayout.offset] =
                        (value as num).toDouble();
                  case StackKind.boolVal:
                    receiver.valueFields[fieldLayout.offset] =
                        (value is bool ? (value ? 1 : 0) : value as int);
                  case StackKind.intVal:
                    receiver.valueFields[fieldLayout.offset] = value as int;
                }
                continue;
              }
              // Try setter method (convention: "name=") — call via helper.
              final setterNameIdx = cp.lookupNameIndex('$name=');
              if (setterNameIdx >= 0) {
                final setter = classInfo.methods[setterNameIdx];
                if (setter != null) {
                  try {
                    _callDarticMethod(module, setter, receiver, [value]);
                  } on Object catch (e, st) {
                    pc = unwindToHandler(pc - 1, e, st);
                  }
                  continue;
                }
              }
            }
            // noSuchMethod fallback. Use b (value reg) as dummy result to
            // avoid overwriting the receiver register a.
            final nsmInvocation = DarticInvocation.setter(Symbol(name), value);
            final (nsmPushed, nsmHandlerPC) =
                dispatchNoSuchMethod(receiver, nsmInvocation, b);
            if (nsmPushed) continue;
            pc = nsmHandlerPC;
            continue;
          }

          // Host object: dynamic set dispatches through HostDispatcher.
          final hostWrapper = _hostClassRegistry?.lookup(receiver);
          if (hostWrapper != null) {
            final hostResult =
                hostWrapper.invokeMethod(receiver, '$name=', [value]);
            if (!identical(hostResult, BindingLookupDispatcher.notFound)) {
              continue;
            }
          }
          // noSuchMethod fallback for host objects. Use b as dummy result reg.
          final invocation = DarticInvocation.setter(Symbol(name), value);
          final (pushed, handlerPC) =
              dispatchNoSuchMethod(receiver, invocation, b);
          if (pushed) continue;
          pc = handlerPC;
          continue;

        case Op.invokeDyn: // INVOKE_DYN A, B, C — refStack[A] = dynamicDispatch(refStack[A+1], names[C], args)
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF; // arg count (including receiver)
          final c = (instr >> 24) & 0xFF;
          final receiver = rs.read(rBase + a + 1);
          final name = cp.getName(c);
          if (receiver == null) {
            throw DarticError(
              'NoSuchMethodError: method "$name" called on null',
            );
          }

          final explicitArgCount = b - 1;

          // DarticObject: look up method in class info.
          if (receiver is DarticObject) {
            final classInfo = module.classes[receiver.classId];
            final nameIdx = cp.lookupNameIndex(name);
            if (nameIdx >= 0) {
              final method = classInfo.methods[nameIdx];
              if (method != null) {
                // Found method — call via _callDarticMethod for proper boxing.
                final methodArgs = List<Object?>.generate(
                  explicitArgCount,
                  (i) => rs.read(rBase + a + 2 + i),
                );
                try {
                  final methodResult = _callDarticMethod(
                      module, method, receiver, methodArgs);
                  rs.write(rBase + a, methodResult);
                } on Object catch (e, st) {
                  pc = unwindToHandler(pc - 1, e, st);
                }
                continue;
              }
            }
            // noSuchMethod fallback for DarticObject.
            final nsmArgs = List<Object?>.generate(
              explicitArgCount,
              (i) => rs.read(rBase + a + 2 + i),
            );
            final nsmInvocation =
                DarticInvocation.method(Symbol(name), nsmArgs);
            final (nsmPushed, nsmHandlerPC) =
                dispatchNoSuchMethod(receiver, nsmInvocation, a);
            if (nsmPushed) continue;
            pc = nsmHandlerPC;
            continue;
          }

          // Host object: try HostDispatcher, then noSuchMethod fallback.
          final hostArgs = List<Object?>.generate(
            explicitArgCount,
            (i) => rs.read(rBase + a + 2 + i),
          );
          final hostWrapper = _hostClassRegistry?.lookup(receiver);
          if (hostWrapper != null) {
            _wrapClosureArgs(hostArgs);
            final hostResult =
                hostWrapper.invokeMethod(receiver, name, hostArgs);
            if (!identical(hostResult, BindingLookupDispatcher.notFound)) {
              rs.write(rBase + a, hostResult);
              continue;
            }
          }
          // noSuchMethod fallback for host objects.
          final invocation =
              DarticInvocation.method(Symbol(name), hostArgs);
          final (pushed, handlerPC) =
              dispatchNoSuchMethod(receiver, invocation, a);
          if (pushed) continue;
          pc = handlerPC;
          continue;

        // ── Async & Generators (0x80-0x8F) ──

        case Op.initAsync: // INIT_ASYNC A, Bx — create Completer<T>, refStack[A] = completer.future
          {
            final a = (instr >> 8) & 0xFF;
            // Bx = constant pool index for emittedValueType TypeTemplate.
            // Phase 1: use Completer<dynamic> (typed Completer deferred).
            // final bx = (instr >> 16) & 0xFFFF;
            final completer = Completer<Object?>();

            // Create a DarticFrame to hold the async state.
            final frame = DarticFrame(funcProto: module.functions[callStack.funcId]);
            frame.resultCompleter = completer;
            frame.capturedZone = Zone.current;
            frame.futureReg = a;

            // Save the caller's async frame so it can be restored when this
            // async function returns its future to the caller via `continue`.
            frame.callerAsyncFrame = _currentAsyncFrame;

            _currentAsyncFrame = frame;

            // Store the future in the designated ref register.
            rs.write(rBase + a, completer.future);
          }

        case Op.await_: // AWAIT A, Bx — suspend frame, register callbacks on future
          {
            final a = (instr >> 8) & 0xFF;
            final bx = (instr >> 16) & 0xFFFF;

            final frame = _currentAsyncFrame!;
            frame.awaitDestReg = a;
            frame.pc = bx; // Resume PC

            // Read the awaited value BEFORE suspending (suspend nulls the slots).
            final Object? value = rs.read(rBase + a);

            // If this is the first suspension point, we need to return the
            // future to the caller. The async function was called via
            // CALL_STATIC/CALL, so the caller is waiting for a return value.
            final bool needsReturnToCaller = !frame.futureReturned;
            final Object? future = needsReturnToCaller
                ? rs.read(rBase + frame.futureReg)
                : null;

            // Save stack bounds on frame before suspending.
            frame.savedVBase = vBase;
            frame.savedRBase = rBase;
            frame.savedVSP = vs.sp;
            frame.savedRSP = rs.sp;

            // Suspend: snapshot stack data to frame object.
            suspendFrame(frame);

            if (needsReturnToCaller) {
              final callerState = _deliverFutureToCaller(
                  frame, future, module, vBase, rBase);
              if (callerState == null) {
                // Entry function or host boundary — register callbacks + exit.
                _registerAwaitCallbacks(frame, value, module);
                return;
              }
              // Restore caller loop state and register callbacks.
              vBase = callerState.vBase;
              rBase = callerState.rBase;
              code = callerState.code;
              pc = callerState.pc;
              currentUpvalues = callerState.upvalues;
              _registerAwaitCallbacks(frame, value, module);
              continue;
            } else {
              // Already returned the future on a previous AWAIT.
              // This is a resumed frame — just suspend and return.
              vs.sp = vBase;
              rs.sp = rBase;
              callStack.popFrame();
              _upvalueStack.removeLast();

              _registerAwaitCallbacks(frame, value, module);
              _currentAsyncFrame = null;
              _currentAsyncStarFrame = null;
              return; // Exit dispatch loop — will be resumed via microtask.
            }
          }

        case Op.asyncReturn: // ASYNC_RETURN A — completer.complete(refStack[A])
          {
            final a = (instr >> 8) & 0xFF;
            final frame = _currentAsyncFrame!;
            final result = rs.read(rBase + a);
            frame.resultCompleter!.complete(result);

            if (!frame.futureReturned) {
              final future = rs.read(rBase + frame.futureReg);
              rs.clearRange(rBase, rs.sp);
              final callerState = _deliverFutureToCaller(
                  frame, future, module, vBase, rBase);
              if (callerState == null) return;
              vBase = callerState.vBase;
              rBase = callerState.rBase;
              code = callerState.code;
              pc = callerState.pc;
              currentUpvalues = callerState.upvalues;
              continue;
            } else {
              // Resumed frame completing: just clean up and return.
              rs.clearRange(rBase, rs.sp);
              vs.sp = vBase;
              rs.sp = rBase;
              callStack.popFrame();
              _upvalueStack.removeLast();
              _currentAsyncFrame = null;
              return;
            }
          }

        case Op.asyncThrow: // ASYNC_THROW A, B — completer.completeError(refStack[A], refStack[B])
          {
            final a = (instr >> 8) & 0xFF;
            final b = (instr >> 16) & 0xFF;
            final frame = _currentAsyncFrame!;
            final error = rs.read(rBase + a);
            final stackTrace = rs.read(rBase + b);
            frame.resultCompleter!.completeError(
              error!,
              stackTrace is StackTrace ? stackTrace : StackTrace.empty,
            );

            if (!frame.futureReturned) {
              final future = rs.read(rBase + frame.futureReg);
              rs.clearRange(rBase, rs.sp);
              final callerState = _deliverFutureToCaller(
                  frame, future, module, vBase, rBase);
              if (callerState == null) return;
              vBase = callerState.vBase;
              rBase = callerState.rBase;
              code = callerState.code;
              pc = callerState.pc;
              currentUpvalues = callerState.upvalues;
              continue;
            } else {
              rs.clearRange(rBase, rs.sp);
              vs.sp = vBase;
              rs.sp = rBase;
              callStack.popFrame();
              _upvalueStack.removeLast();
              _currentAsyncFrame = null;
              return;
            }
          }

        // ── Async* Generator (0x84) ──

        case Op.initAsyncStar: // INIT_ASYNC_STAR A, Bx — create StreamController
          {
            final a = (instr >> 8) & 0xFF;
            // Bx = constant pool index for emittedValueType TypeTemplate.
            // (reserved for future typed StreamController; currently unused).
            // final bx = (instr >> 16) & 0xFFFF;

            final funcProto = module.functions[callStack.funcId];

            // bodyStartPC = pc + 1 (skip the upcoming RETURN_REF, land on
            // the body). The compiler emits:
            //   INIT_ASYNC_STAR -> RETURN_REF -> body...
            final bodyStartPC = pc + 1; // skip RETURN_REF

            // Snapshot the current stack state so onListen can start the body
            // with a copy of the function arguments.
            final vSize = vs.sp - vBase;
            final rSize = rs.sp - rBase;
            final valueSlots = <int>[];
            for (var i = 0; i < vSize; i++) {
              valueSlots.add(vs.readInt(vBase + i));
            }
            final refSlots = List<Object?>.filled(rSize, null);
            for (var i = 0; i < rSize; i++) {
              refSlots[i] = rs.read(rBase + i);
            }

            // Build upvalue list from current context.
            final upvalueList = <Upvalue>[];
            final uv = currentUpvalues;
            if (uv != null) {
              upvalueList.addAll(uv);
            }

            // Create a DarticFrame to hold the async* state.
            final frame = DarticFrame(
              funcProto: funcProto,
              upvalues: upvalueList,
            );
            frame.pc = bodyStartPC;
            frame.capturedZone = Zone.current;
            // Mark futureReturned=true so AWAIT takes the "already returned"
            // path (the stream was returned synchronously, not via AWAIT).
            frame.futureReturned = true;

            // Save the argument snapshot on the frame for initial startup.
            frame.savedVBase = 0;
            frame.savedRBase = 0;
            frame.savedVSP = vSize;
            frame.savedRSP = rSize;
            if (vSize > 0) {
              frame.savedValueSlots = Int64List(vSize);
              for (var i = 0; i < vSize; i++) {
                frame.savedValueSlots![i] = valueSlots[i];
              }
            }
            if (rSize > 0) {
              frame.savedRefSlots = List<Object?>.of(refSlots);
            }

            // Create the StreamController with lifecycle callbacks.
            final controller = StreamController<Object?>(
              onListen: () {
                // Start executing the body via microtask.
                final zone = frame.capturedZone ?? Zone.current;
                zone.scheduleMicrotask(
                    () => _startAsyncStarBody(frame, module));
              },
              onPause: () {
                frame.streamPaused = true;
              },
              onResume: () {
                frame.streamPaused = false;
                if (frame.isSuspendedAtYield) {
                  frame.isSuspendedAtYield = false;
                  final zone = frame.capturedZone ?? Zone.current;
                  zone.scheduleMicrotask(
                      () => _resumeAsyncStarFrame(frame, module));
                }
              },
              onCancel: () {
                frame.cancelled = true;
                if (frame.isSuspendedAtYield) {
                  frame.isSuspendedAtYield = false;
                  final zone = frame.capturedZone ?? Zone.current;
                  zone.scheduleMicrotask(
                      () => _resumeAsyncStarFrame(frame, module));
                }
              },
            );

            frame.streamController = controller;

            // Store the stream in the designated ref register.
            rs.write(rBase + a, controller.stream);
            // Fall through to the next instruction (RETURN_REF A), which
            // will return the stream to the caller synchronously.
          }

        // ── Sync* Generator (0x85, 0x87) ──

        case Op.initSyncStar: // INIT_SYNC_STAR A, Bx — create lazy SyncStarIterable
          {
            final a = (instr >> 8) & 0xFF;
            // Bx = constant pool index for emittedValueType TypeTemplate
            // (reserved for future typed iterable; currently unused).
            // final bx = (instr >> 16) & 0xFFFF;

            final funcProto = module.functions[callStack.funcId];

            // bodyStartPC = pc (the instruction after INIT_SYNC_STAR, which
            // is RETURN_REF). The SyncStarIterable records pc+1 (skip the
            // RETURN_REF) as the actual body start. But it's simpler to just
            // record pc here and let the iterable use bodyStartPC directly.
            // The compiler emits: INIT_SYNC_STAR -> RETURN_REF -> body...
            // So bodyStartPC = pc + 1 (skip RETURN_REF, land on body start).
            final bodyStartPC = pc + 1; // skip the upcoming RETURN_REF

            // Snapshot the current stack state so each iterator can start
            // with a copy of the function arguments.
            final vSize = vs.sp - vBase;
            final rSize = rs.sp - rBase;
            final valueSlots = <int>[];
            for (var i = 0; i < vSize; i++) {
              valueSlots.add(vs.readInt(vBase + i));
            }
            final refSlots = List<Object?>.filled(rSize, null);
            for (var i = 0; i < rSize; i++) {
              refSlots[i] = rs.read(rBase + i);
            }

            // Build upvalue list from current context (same as CLOSURE).
            final upvalues = <Upvalue>[];
            final uv = currentUpvalues;
            if (uv != null) {
              upvalues.addAll(uv);
            }

            final iterable = SyncStarIterable<Object?>(
              interpreter: this,
              module: module,
              funcProto: funcProto,
              bodyStartPC: bodyStartPC,
              upvalues: upvalues,
              capturedArgs: (valueSlots: valueSlots, refSlots: refSlots),
            );

            rs.write(rBase + a, iterable);
            // Fall through to the next instruction (RETURN_REF A), which
            // will return the iterable to the caller synchronously.
          }

        case Op.yield_: // YIELD A, Bx — yield refStack[A], resume at Bx
          {
            final a = (instr >> 8) & 0xFF;
            final bx = (instr >> 16) & 0xFFFF;

            final syncIter = _activeSyncStarIterator;
            if (syncIter != null) {
              // sync* context: set iterator.current, suspend, return.
              final value = rs.read(rBase + a);
              syncIter.setCurrent(value);

              // Save frame state for resume.
              final frame = DarticFrame(
                funcProto: module.functions[callStack.funcId],
                upvalues: currentUpvalues ?? const [],
              );
              frame.pc = bx; // resume PC

              // Save stack bounds.
              frame.savedVBase = vBase;
              frame.savedRBase = rBase;
              frame.savedVSP = vs.sp;
              frame.savedRSP = rs.sp;

              // Snapshot stack data.
              suspendFrame(frame);

              // Store the suspended frame on the interpreter; driveSyncStar()
              // reads it after _executeLoop returns and assigns it to the
              // iterator.
              _syncStarSuspendedFrame = frame;

              _syncStarStatus = SyncStarStatus.yielded;

              // Clean up stacks and return from _executeLoop.
              vs.sp = vBase;
              rs.sp = rBase;
              callStack.popFrame();
              _upvalueStack.removeLast();
              return;
            }

            // async* context: add value to stream, check pause/cancel.
            final asyncStarFrame = _currentAsyncStarFrame;
            if (asyncStarFrame != null &&
                asyncStarFrame.streamController != null) {
              final value = rs.read(rBase + a);
              final controller = asyncStarFrame.streamController!;

              // Add value to the stream.
              controller.add(value);

              // Check if cancelled — if so, suspend (finally will run).
              if (asyncStarFrame.cancelled) {
                asyncStarFrame.pc = bx; // resume PC

                // Save stack bounds.
                asyncStarFrame.savedVBase = vBase;
                asyncStarFrame.savedRBase = rBase;
                asyncStarFrame.savedVSP = vs.sp;
                asyncStarFrame.savedRSP = rs.sp;

                // Snapshot stack data.
                suspendFrame(asyncStarFrame);

                // Clean up and return from _executeLoop.
                vs.sp = vBase;
                rs.sp = rBase;
                callStack.popFrame();
                _upvalueStack.removeLast();
                _currentAsyncStarFrame = null;

                // Schedule resume to execute finally blocks.
                final zone = asyncStarFrame.capturedZone ?? Zone.current;
                zone.scheduleMicrotask(
                    () => _resumeAsyncStarFrame(asyncStarFrame, module));
                return;
              }

              // Check if stream is paused — if so, suspend at yield.
              if (asyncStarFrame.streamPaused) {
                asyncStarFrame.isSuspendedAtYield = true;
                asyncStarFrame.pc = bx; // resume PC
                asyncStarFrame.awaitDestReg = -1; // Not an await resume

                // Save stack bounds.
                asyncStarFrame.savedVBase = vBase;
                asyncStarFrame.savedRBase = rBase;
                asyncStarFrame.savedVSP = vs.sp;
                asyncStarFrame.savedRSP = rs.sp;

                // Snapshot stack data.
                suspendFrame(asyncStarFrame);

                // Clean up and return from _executeLoop.
                vs.sp = vBase;
                rs.sp = rBase;
                callStack.popFrame();
                _upvalueStack.removeLast();
                _currentAsyncStarFrame = null;
                return;
              }

              // Not paused, not cancelled — continue execution.
              break;
            }

            throw DarticError('YIELD in non-generator context');
          }

        case Op.yieldStar: // YIELD_STAR A, Bx — yield* refStack[A], resume at Bx
          {
            final a = (instr >> 8) & 0xFF;
            final bx = (instr >> 16) & 0xFFFF;

            final delegateValue = rs.read(rBase + a);

            final syncIter = _activeSyncStarIterator;
            if (syncIter != null) {
              // sync* context: yield* an Iterable.
              // Get the delegate's iterator. Since the value is a host-level
              // Dart Iterable (List, SyncStarIterable, etc.), call .iterator
              // directly.
              final iterable = delegateValue as Iterable;
              final delegateIterator = iterable.iterator;

              // Check if the delegate has any elements. If it does, set it on
              // the sync* iterator and suspend. If empty, just continue.
              if (delegateIterator.moveNext()) {
                // Set the first value as current.
                syncIter.setCurrent(delegateIterator.current);

                // Store the delegate on the iterator for subsequent moveNext()
                // calls to drain.
                syncIter.setDelegateIterator(delegateIterator);

                // Save frame state for resume (when delegate is exhausted,
                // moveNext() will resume the generator from bx).
                final frame = DarticFrame(
                  funcProto: module.functions[callStack.funcId],
                  upvalues: currentUpvalues ?? const [],
                );
                frame.pc = bx; // resume PC (after delegate is done)

                // Save stack bounds.
                frame.savedVBase = vBase;
                frame.savedRBase = rBase;
                frame.savedVSP = vs.sp;
                frame.savedRSP = rs.sp;

                // Snapshot stack data.
                suspendFrame(frame);

                _syncStarSuspendedFrame = frame;
                _syncStarStatus = SyncStarStatus.yielded;

                // Clean up stacks and return from _executeLoop.
                vs.sp = vBase;
                rs.sp = rBase;
                callStack.popFrame();
                _upvalueStack.removeLast();
                return;
              }

              // Delegate is empty — continue execution from next instruction
              // (which is Bx, the resume PC, same as falling through).
              break;
            }

            // async* context: yield* a Stream.
            final asyncStarFrame = _currentAsyncStarFrame;
            if (asyncStarFrame != null &&
                asyncStarFrame.streamController != null) {
              final controller = asyncStarFrame.streamController!;
              final delegateStream = delegateValue as Stream;

              // Save frame state for resume (when the delegate stream is done).
              asyncStarFrame.pc = bx;
              asyncStarFrame.awaitDestReg = -1; // Not an await resume
              asyncStarFrame.savedVBase = vBase;
              asyncStarFrame.savedRBase = rBase;
              asyncStarFrame.savedVSP = vs.sp;
              asyncStarFrame.savedRSP = rs.sp;

              // Snapshot stack data.
              suspendFrame(asyncStarFrame);

              // Subscribe to the delegate stream: forward events to our
              // controller, and resume the generator frame when done.
              final zone = asyncStarFrame.capturedZone ?? Zone.current;
              delegateStream.listen(
                (value) {
                  controller.add(value);
                },
                onError: (Object error, StackTrace stackTrace) {
                  controller.addError(error, stackTrace);
                },
                onDone: () {
                  // Delegate stream is done — resume the generator from Bx.
                  zone.scheduleMicrotask(
                      () => _resumeAsyncStarFrame(asyncStarFrame, module));
                },
              );

              // Clean up and return from _executeLoop (frame is suspended).
              vs.sp = vBase;
              rs.sp = rBase;
              callStack.popFrame();
              _upvalueStack.removeLast();
              _currentAsyncStarFrame = null;
              _currentAsyncFrame = null;
              return;
            }

            throw DarticError('YIELD_STAR in non-generator context');
          }

        // ── System ──

        case Op.halt: // HALT ABC: A=resultReg, B=kind+1, C=unused
          // Extract result BEFORE resetting stack pointers.
          // B encodes StackKind.index + 1, where 0 means void/no result.
          final a = (instr >> 8) & 0xFF;
          final b = (instr >> 16) & 0xFF;
          if (b == 0) {
            _lastEntryResult = null; // void
          } else {
            switch (b - 1) {
              case StackKind.refDefault:
                _lastEntryResult = rs.read(rBase + a);
              case StackKind.boolDefault:
                _lastEntryResult = vs.readInt(vBase + a) != 0;
              case StackKind.intDefault:
                _lastEntryResult = vs.readInt(vBase + a);
              case StackKind.doubleDefault:
                _lastEntryResult = vs.readDouble(vBase + a);
              default:
                _lastEntryResult = null;
            }
          }
          vs.sp = vBase;
          rs.sp = rBase;
          callStack.popFrame();
          _upvalueStack.removeLast();
          return;

        default:
          throw DarticError(
            'Unimplemented opcode: '
            '0x${op.toRadixString(16).padLeft(2, '0')}',
          );
      }
    }
    // Fuel exhausted — Phase 1: silently return.
  }

  /// Builds a [DarticInvocation] for a CALL_VIRTUAL noSuchMethod fallback.
  ///
  /// If the IC entry has zero args, returns a getter invocation.
  /// Otherwise, reads [ic.argCount] args from the ref stack starting at
  /// [receiverBase] + 3 and returns a method invocation.
  static Invocation _buildVirtualInvocation(
    ICEntry ic,
    String methodName,
    int receiverBase,
    RefStack rs,
  ) {
    if (ic.argCount == 0) {
      return DarticInvocation.getter(Symbol(methodName));
    }
    final args = List<Object?>.generate(
      ic.argCount,
      (i) => rs.read(receiverBase + 3 + i),
    );
    return DarticInvocation.method(Symbol(methodName), args);
  }

  /// Searches [funcProto]'s exception table for a handler matching [pc].
  ///
  /// Returns the first matching [ExceptionHandler] where
  /// `startPC <= pc < endPC`, or null if no handler matches.
  ///
  /// For typed catch (`catchType >= 0`), resolves the guard TypeTemplate
  /// from the constant pool and checks if the exception's runtime type is
  /// a subtype of the guard type.
  ExceptionHandler? _findHandler(
    DarticFuncProto funcProto,
    int pc,
    Object? exception,
    DarticModule module,
    int rBase,
    RefStack rs,
  ) {
    for (final handler in funcProto.exceptionTable) {
      if (pc >= handler.startPC && pc < handler.endPC) {
        if (handler.catchType == -1) return handler; // catch-all
        // Typed catch: resolve guard type and check subtype.
        final guardTemplate =
            module.constantPool.getRef(handler.catchType) as TypeTemplate;
        final ita = rs.read(rBase + 0) as List<DarticType>?;
        final fta = rs.read(rBase + 1) as List<DarticType>?;
        final reg = _activeTypeRegistry!;
        final guardType = resolveType(guardTemplate, ita, fta, reg);
        final exType = extractType(exception, reg, module.classes);
        if (_subtypeChecker!.isSubtypeOf(exType, guardType)) {
          return handler;
        }
      }
    }
    return null;
  }
}
