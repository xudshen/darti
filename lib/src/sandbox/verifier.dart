/// Bytecode verifier for DarticModule structural integrity validation.
///
/// Validates a deserialized [DarticModule] before execution to ensure all
/// internal references are in-bounds and structurally sound. If verification
/// passes, the runtime dispatch loop can operate with zero safety overhead.
///
/// See: docs/design/08-sandbox.md
library;

import '../bytecode/constant_pool.dart';
import '../bytecode/module.dart';
import '../bytecode/opcodes.dart';

/// Validates a [DarticModule] for structural integrity.
///
/// Usage:
/// ```dart
/// final verifier = DarticVerifier();
/// if (!verifier.verify(module)) {
///   throw DarticLoadError(verifier.errors);
/// }
/// ```
class DarticVerifier {
  /// Accumulated error messages from the most recent [verify] call.
  final List<String> errors = [];

  /// Validates the given [module].
  ///
  /// Returns `true` if all checks pass, `false` if any errors were found.
  /// Errors are collected in [errors] — the verifier does NOT stop at the
  /// first failure.
  bool verify(DarticModule module) {
    errors.clear();
    _verifyEntryPoint(module);
    _verifyConstantPool(module.constantPool);
    for (final func in module.functions) {
      _verifyFunction(func, module);
    }
    _verifyClassTable(module);
    return errors.isEmpty;
  }

  // ── Valid opcode set (O(1) lookup) ──

  static final Set<int> _validOpcodes = {
    Op.nop,
    Op.loadConst,
    Op.loadNull,
    Op.loadTrue,
    Op.loadFalse,
    Op.loadInt,
    Op.loadConstInt,
    Op.loadConstDbl,
    Op.moveRef,
    Op.moveVal,
    Op.loadUpvalue,
    Op.storeUpvalue,
    Op.addInt,
    Op.subInt,
    Op.mulInt,
    Op.divInt,
    Op.modInt,
    Op.negInt,
    Op.bitAnd,
    Op.bitOr,
    Op.bitXor,
    Op.bitNot,
    Op.shl,
    Op.shr,
    Op.ushr,
    Op.addIntImm,
    Op.addDbl,
    Op.subDbl,
    Op.mulDbl,
    Op.divDbl,
    Op.negDbl,
    Op.intToDbl,
    Op.dblToInt,
    Op.boxInt,
    Op.boxDouble,
    Op.boxBool,
    Op.unboxInt,
    Op.unboxDouble,
    Op.unboxBool,
    Op.notBool,
    Op.modDbl,
    Op.ltInt,
    Op.leInt,
    Op.gtInt,
    Op.geInt,
    Op.eqInt,
    Op.ltDbl,
    Op.leDbl,
    Op.gtDbl,
    Op.geDbl,
    Op.eqDbl,
    Op.eqRef,
    Op.eqGeneric,
    Op.jump,
    Op.jumpIfTrue,
    Op.jumpIfFalse,
    Op.jumpIfNull,
    Op.jumpIfNnull,
    Op.jumpAx,
    Op.call,
    Op.callStatic,
    Op.callHost,
    Op.callVirtual,
    Op.callSuper,
    Op.returnRef,
    Op.returnVal,
    Op.returnNull,
    Op.getFieldRef,
    Op.setFieldRef,
    Op.getFieldVal,
    Op.setFieldVal,
    Op.newInstance,
    Op.instanceOf,
    Op.cast,
    Op.getFieldDyn,
    Op.setFieldDyn,
    Op.closure,
    Op.closeUpvalue,
    Op.pushIta,
    Op.pushFta,
    Op.loadTypeArg,
    Op.instantiateType,
    Op.createTypeArgs,
    Op.allocGeneric,
    Op.checkCovariant,
    Op.initAsync,
    Op.await_,
    Op.asyncReturn,
    Op.asyncThrow,
    Op.initAsyncStar,
    Op.yield_,
    Op.yieldStar,
    Op.initSyncStar,
    Op.awaitStreamNext,
    Op.createList,
    Op.createMap,
    Op.createSet,
    Op.createRecord,
    Op.stringInterp,
    Op.addGeneric,
    Op.invokeDyn,
    Op.loadGlobal,
    Op.storeGlobal,
    Op.throw_,
    Op.rethrow_,
    Op.assert_,
    Op.nullCheck,
    Op.wide,
    Op.halt,
  };

  // ── Check 11: Entry point ──

  void _verifyEntryPoint(DarticModule module) {
    if (module.entryFuncId < 0 ||
        module.entryFuncId >= module.functions.length) {
      errors.add(
        'Entry point funcId ${module.entryFuncId} out of range '
        '[0, ${module.functions.length})',
      );
    }
  }

  // ── Check 1: Constant pool internal bounds ──

  void _verifyConstantPool(ConstantPool pool) {
    // The four-partition pool (refs, ints, doubles, names) uses independent
    // index spaces. Partition lengths are non-negative by construction.
    //
    // Per-instruction constant pool index bounds are validated in
    // _verifyConstantPoolRefs (LOAD_CONST, LOAD_CONST_INT, LOAD_CONST_DBL).
    //
    // Known gap: cross-partition references (e.g., TypeTemplate entries in
    // the refs partition referencing class IDs) are not validated here.
  }

  // ── Check 10: Class table ──

  void _verifyClassTable(DarticModule module) {
    final classCount = module.classes.length;
    final funcIdSet = <int>{
      for (final f in module.functions) f.funcId,
    };

    for (final cls in module.classes) {
      // superClassId must be -1 (root) or a valid class index.
      if (cls.superClassId != -1 &&
          (cls.superClassId < 0 || cls.superClassId >= classCount)) {
        errors.add(
          'Class ${cls.name}#${cls.classId}: superClassId '
          '${cls.superClassId} out of range [0, $classCount) or -1',
        );
      }

      // Method references must point to functions in the module.
      for (final entry in cls.methods.entries) {
        final methodFunc = entry.value;
        if (!funcIdSet.contains(methodFunc.funcId)) {
          errors.add(
            'Class ${cls.name}#${cls.classId}: method nameIndex '
            '${entry.key} references funcId ${methodFunc.funcId} '
            'not found in module functions',
          );
        }
      }
    }
  }

  // ── Per-function verification ──

  void _verifyFunction(DarticFuncProto func, DarticModule module) {
    final code = func.bytecode;
    final codeLength = code.length;
    final pool = module.constantPool;

    final prefix = '[func ${func.name}#${func.funcId}]';

    for (var pc = 0; pc < codeLength; pc++) {
      final instr = code[pc];
      final op = instr & 0xFF;

      // Check 2: Opcode validity.
      if (!_validOpcodes.contains(op)) {
        errors.add(
          '$prefix Invalid opcode 0x${op.toRadixString(16)} at pc=$pc',
        );
        continue;
      }

      // Check 6: WIDE prefix handling.
      if (op == Op.wide) {
        if (pc + 2 >= codeLength) {
          errors.add(
            '$prefix WIDE prefix at pc=$pc needs 2 more words but '
            'only ${codeLength - pc - 1} available',
          );
          break; // can't safely continue
        }
        // Validate the widened instruction's opcode (at pc+2).
        final widenedInstr = code[pc + 2];
        final widenedOp = widenedInstr & 0xFF;
        if (!_validOpcodes.contains(widenedOp)) {
          errors.add(
            '$prefix WIDE at pc=$pc: widened opcode '
            '0x${widenedOp.toRadixString(16)} is invalid',
          );
        } else if (widenedOp == Op.wide) {
          errors.add(
            '$prefix WIDE at pc=$pc: nested WIDE is not allowed',
          );
        }
        // Skip extension word and the actual instruction word.
        // Note: extended-range operand bounds are not deeply validated
        // because WIDE encoding uses different bit layouts.
        pc += 2;
        continue;
      }

      // Decode common operands.
      final a = (instr >> 8) & 0xFF;
      final b = (instr >> 16) & 0xFF;
      final c = (instr >> 24) & 0xFF;
      final bx = (instr >> 16) & 0xFFFF;
      final sbx = bx - 0x7FFF;
      final ax = (instr >> 8) & 0xFFFFFF;
      final sax = ax - 0x7FFFFF;

      // Check 3: Jump targets.
      if (_isJumpOp(op)) {
        final target = _jumpTarget(op, pc, sbx, sax);
        if (target < 0 || target >= codeLength) {
          errors.add(
            '$prefix Jump target $target out of range '
            '[0, $codeLength) at pc=$pc',
          );
        }
      }

      // Check 4: Register bounds.
      _verifyRegisterBounds(op, a, b, c, func, prefix, pc);

      // Check 5: Constant pool indices.
      _verifyConstantPoolRefs(op, bx, pool, prefix, pc);

      // Check 7: Function/method/binding references.
      _verifyFunctionRefs(op, a, b, c, bx, func, module, prefix, pc);

      // Check 12: IC table references (from CALL_VIRTUAL C operand).
      if (op == Op.callVirtual) {
        if (c >= func.icTable.length) {
          errors.add(
            '$prefix CALL_VIRTUAL C=$c >= icTable.length '
            '${func.icTable.length} at pc=$pc',
          );
        }
      }

      // Names pool references (getFieldDyn, setFieldDyn, invokeDyn).
      if (op == Op.getFieldDyn || op == Op.setFieldDyn) {
        if (c >= pool.nameCount) {
          errors.add(
            '$prefix names pool index C=$c >= nameCount '
            '${pool.nameCount} at pc=$pc',
          );
        }
      }
      if (op == Op.invokeDyn) {
        if (c >= pool.nameCount) {
          errors.add(
            '$prefix names pool index C=$c >= nameCount '
            '${pool.nameCount} at pc=$pc',
          );
        }
      }

      // Global index bounds.
      if (op == Op.loadGlobal || op == Op.storeGlobal) {
        if (bx >= module.globalCount) {
          errors.add(
            '$prefix global index Bx=$bx >= globalCount '
            '${module.globalCount} at pc=$pc',
          );
        }
      }
    }

    // Check 8: Exception handler table.
    for (var i = 0; i < func.exceptionTable.length; i++) {
      final h = func.exceptionTable[i];
      if (h.startPC >= h.endPC) {
        errors.add(
          '$prefix Exception handler #$i: startPC ${h.startPC} '
          '>= endPC ${h.endPC}',
        );
      }
      if (h.endPC > codeLength) {
        errors.add(
          '$prefix Exception handler #$i: endPC ${h.endPC} '
          '> codeLength $codeLength',
        );
      }
      if (h.startPC < 0 || h.startPC >= codeLength) {
        errors.add(
          '$prefix Exception handler #$i: startPC ${h.startPC} '
          'out of range [0, $codeLength)',
        );
      }
      if (h.handlerPC < 0 || h.handlerPC >= codeLength) {
        errors.add(
          '$prefix Exception handler #$i: handlerPC ${h.handlerPC} '
          'out of range [0, $codeLength)',
        );
      }
      if (h.valStackDP < 0 || h.valStackDP > func.valueRegCount) {
        errors.add(
          '$prefix Exception handler #$i: valStackDP ${h.valStackDP} '
          'out of range [0, ${func.valueRegCount}]',
        );
      }
      if (h.refStackDP < 0 || h.refStackDP > func.refRegCount) {
        errors.add(
          '$prefix Exception handler #$i: refStackDP ${h.refStackDP} '
          'out of range [0, ${func.refRegCount}]',
        );
      }
      if (h.exceptionReg >= func.refRegCount) {
        errors.add(
          '$prefix Exception handler #$i: exceptionReg ${h.exceptionReg} '
          '>= refRegCount ${func.refRegCount}',
        );
      }
      // stackTraceReg: -1 means "no stack trace register" (sentinel);
      // otherwise must be in [0, refRegCount).
      if (h.stackTraceReg != -1 &&
          (h.stackTraceReg < 0 || h.stackTraceReg >= func.refRegCount)) {
        errors.add(
          '$prefix Exception handler #$i: stackTraceReg ${h.stackTraceReg} '
          'out of range (expected -1 or [0, ${func.refRegCount}))',
        );
      }
    }

    // Check 12: IC table name indices.
    for (var i = 0; i < func.icTable.length; i++) {
      final ic = func.icTable[i];
      if (ic.methodNameIndex >= pool.nameCount) {
        errors.add(
          '$prefix IC entry #$i: methodNameIndex ${ic.methodNameIndex} '
          '>= nameCount ${pool.nameCount}',
        );
      }
    }

    // Check 9: Upvalue descriptors.
    for (var i = 0; i < func.upvalueDescriptors.length; i++) {
      final uv = func.upvalueDescriptors[i];
      if (uv.isLocal && uv.index >= func.refRegCount) {
        errors.add(
          '$prefix Upvalue descriptor #$i: isLocal index ${uv.index} '
          '>= refRegCount ${func.refRegCount}',
        );
      }
    }
  }

  // ── Jump helpers ──

  static bool _isJumpOp(int op) =>
      op == Op.jump ||
      op == Op.jumpIfTrue ||
      op == Op.jumpIfFalse ||
      op == Op.jumpIfNull ||
      op == Op.jumpIfNnull ||
      op == Op.jumpAx;

  static int _jumpTarget(int op, int pc, int sbx, int sax) {
    if (op == Op.jumpAx) return pc + 1 + sax;
    return pc + 1 + sbx;
  }

  // ── Register bounds ──

  void _verifyRegisterBounds(
    int op,
    int a,
    int b,
    int c,
    DarticFuncProto func,
    String prefix,
    int pc,
  ) {
    final vrc = func.valueRegCount;
    final rrc = func.refRegCount;

    switch (op) {
      // Format ABC: three value-stack registers (A, B, C all value)
      case Op.addInt:
      case Op.subInt:
      case Op.mulInt:
      case Op.divInt:
      case Op.modInt:
      case Op.bitAnd:
      case Op.bitOr:
      case Op.bitXor:
      case Op.shl:
      case Op.shr:
      case Op.ushr:
      case Op.addDbl:
      case Op.subDbl:
      case Op.mulDbl:
      case Op.divDbl:
      case Op.modDbl:
      case Op.ltInt:
      case Op.leInt:
      case Op.gtInt:
      case Op.geInt:
      case Op.eqInt:
      case Op.ltDbl:
      case Op.leDbl:
      case Op.gtDbl:
      case Op.geDbl:
      case Op.eqDbl:
        _checkVal(a, vrc, 'A', prefix, pc, op);
        _checkVal(b, vrc, 'B', prefix, pc, op);
        _checkVal(c, vrc, 'C', prefix, pc, op);

      // ABC: A=value result, B=ref, C=ref
      case Op.eqRef:
      case Op.eqGeneric:
        _checkVal(a, vrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);
        _checkRef(c, rrc, 'C', prefix, pc, op);

      // addIntImm: A=val, B=val, C=immediate (not checked)
      case Op.addIntImm:
        _checkVal(a, vrc, 'A', prefix, pc, op);
        _checkVal(b, vrc, 'B', prefix, pc, op);

      // Format AB: value-to-value (A=val, B=val)
      case Op.moveVal:
      case Op.negInt:
      case Op.bitNot:
      case Op.negDbl:
      case Op.intToDbl:
      case Op.dblToInt:
      case Op.notBool:
        _checkVal(a, vrc, 'A', prefix, pc, op);
        _checkVal(b, vrc, 'B', prefix, pc, op);

      // Format AB: ref-to-ref
      case Op.moveRef:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // Box: A=ref(result), B=val(source)
      case Op.boxInt:
      case Op.boxDouble:
      case Op.boxBool:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkVal(b, vrc, 'B', prefix, pc, op);

      // Unbox: A=val(result), B=ref(source)
      case Op.unboxInt:
      case Op.unboxDouble:
      case Op.unboxBool:
        _checkVal(a, vrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // Format A only: ref register
      case Op.loadNull:
      case Op.returnRef:
      case Op.throw_:
      case Op.nullCheck:
      case Op.closeUpvalue:
      case Op.pushIta:
      case Op.pushFta:
      case Op.asyncReturn:
        _checkRef(a, rrc, 'A', prefix, pc, op);

      // Format A only: value register
      case Op.loadTrue:
      case Op.loadFalse:
      case Op.returnVal:
        _checkVal(a, vrc, 'A', prefix, pc, op);

      // Format ABx: A=ref
      case Op.loadConst:
      case Op.loadUpvalue:
      case Op.storeUpvalue:
      case Op.callStatic:
      case Op.callSuper:
      case Op.callHost:
      case Op.newInstance:
      case Op.closure:
      case Op.instantiateType:
      case Op.checkCovariant:
      case Op.initAsync:
      case Op.await_:
      case Op.initAsyncStar:
      case Op.yield_:
      case Op.yieldStar:
      case Op.initSyncStar:
      case Op.awaitStreamNext:
      case Op.createRecord:
      case Op.loadGlobal:
      case Op.storeGlobal:
        _checkRef(a, rrc, 'A', prefix, pc, op);

      // Format ABx: A=val
      case Op.loadConstInt:
      case Op.loadConstDbl:
        _checkVal(a, vrc, 'A', prefix, pc, op);

      // Format AsBx: A=val, loadInt
      case Op.loadInt:
        _checkVal(a, vrc, 'A', prefix, pc, op);

      // Format AsBx: jumps — A=val (condition) or unused
      case Op.jump:
        break; // A unused
      case Op.jumpIfTrue:
      case Op.jumpIfFalse:
        _checkVal(a, vrc, 'A', prefix, pc, op);
      case Op.jumpIfNull:
      case Op.jumpIfNnull:
        _checkRef(a, rrc, 'A', prefix, pc, op);

      // jumpAx: no register operands
      case Op.jumpAx:
        break;

      // call: A=ref(result), B=ref(closure), C=argCount (not register)
      case Op.call:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // callVirtual: A=ref(result), B=ref(receiver), C=IC index (not register)
      case Op.callVirtual:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // getFieldRef/setFieldRef: A=ref, B=ref, C=field offset (not checked)
      case Op.getFieldRef:
      case Op.setFieldRef:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // getFieldVal/setFieldVal: A=val, B=ref, C=field offset
      case Op.getFieldVal:
      case Op.setFieldVal:
        _checkVal(a, vrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // instanceOf: A=val(result), B=ref, C=type pool (not register)
      case Op.instanceOf:
        _checkVal(a, vrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // cast: A=ref(result), B=ref, C=type pool (not register)
      case Op.cast:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // getFieldDyn/setFieldDyn: A=ref, B=ref, C=names pool index
      case Op.getFieldDyn:
      case Op.setFieldDyn:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // loadTypeArg: A=ref, B=ref, C=immediate
      case Op.loadTypeArg:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // createTypeArgs: A=ref, B=count (not register)
      case Op.createTypeArgs:
        _checkRef(a, rrc, 'A', prefix, pc, op);

      // allocGeneric: A=ref, B=ref
      case Op.allocGeneric:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // createList/createMap/createSet: A=ref, B=ref(typeArgs), C=count
      case Op.createList:
      case Op.createMap:
      case Op.createSet:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // stringInterp: A=ref, B=count (not register)
      case Op.stringInterp:
        _checkRef(a, rrc, 'A', prefix, pc, op);

      // addGeneric: A=ref, B=ref, C=ref
      case Op.addGeneric:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);
        _checkRef(c, rrc, 'C', prefix, pc, op);

      // invokeDyn: A=ref, B=ref, C=names pool index
      case Op.invokeDyn:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // rethrow_: A=ref, B=ref
      case Op.rethrow_:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // asyncThrow: A=ref, B=ref
      case Op.asyncThrow:
        _checkRef(a, rrc, 'A', prefix, pc, op);
        _checkRef(b, rrc, 'B', prefix, pc, op);

      // assert_: A=val (condition bool on value stack), Bx=refs pool
      case Op.assert_:
        _checkVal(a, vrc, 'A', prefix, pc, op);

      // nop, returnNull, halt, wide: no register operands
      case Op.nop:
      case Op.returnNull:
      case Op.halt:
      case Op.wide:
        break;
    }
  }

  void _checkVal(
      int reg, int max, String name, String prefix, int pc, int op) {
    if (reg >= max) {
      errors.add(
        '$prefix Value register $name=$reg >= valueRegCount $max '
        'at pc=$pc (op=0x${op.toRadixString(16)})',
      );
    }
  }

  void _checkRef(
      int reg, int max, String name, String prefix, int pc, int op) {
    if (reg >= max) {
      errors.add(
        '$prefix Ref register $name=$reg >= refRegCount $max '
        'at pc=$pc (op=0x${op.toRadixString(16)})',
      );
    }
  }

  // ── Constant pool index checks ──

  void _verifyConstantPoolRefs(
    int op,
    int bx,
    ConstantPool pool,
    String prefix,
    int pc,
  ) {
    switch (op) {
      case Op.loadConst:
        if (bx >= pool.refCount) {
          errors.add(
            '$prefix Constant pool refs index Bx=$bx >= refCount '
            '${pool.refCount} at pc=$pc',
          );
        }
      case Op.loadConstInt:
        if (bx >= pool.intCount) {
          errors.add(
            '$prefix Constant pool ints index Bx=$bx >= intCount '
            '${pool.intCount} at pc=$pc',
          );
        }
      case Op.loadConstDbl:
        if (bx >= pool.doubleCount) {
          errors.add(
            '$prefix Constant pool doubles index Bx=$bx >= doubleCount '
            '${pool.doubleCount} at pc=$pc',
          );
        }
    }
  }

  // ── Function/method/binding reference checks ──

  void _verifyFunctionRefs(
    int op,
    int a,
    int b,
    int c,
    int bx,
    DarticFuncProto func,
    DarticModule module,
    String prefix,
    int pc,
  ) {
    switch (op) {
      case Op.callStatic:
        if (bx >= module.functions.length) {
          errors.add(
            '$prefix CALL_STATIC Bx=$bx >= functions.length '
            '${module.functions.length} at pc=$pc',
          );
        }
      case Op.callSuper:
        if (bx >= module.functions.length) {
          errors.add(
            '$prefix CALL_SUPER Bx=$bx >= functions.length '
            '${module.functions.length} at pc=$pc',
          );
        }
      case Op.callHost:
        if (bx >= module.bindingNames.length) {
          errors.add(
            '$prefix CALL_HOST Bx=$bx >= bindingNames.length '
            '${module.bindingNames.length} at pc=$pc',
          );
        }
      case Op.closure:
        if (bx >= module.functions.length) {
          errors.add(
            '$prefix closure Bx=$bx >= functions.length '
            '${module.functions.length} at pc=$pc',
          );
        }
      case Op.newInstance:
        if (bx >= module.classes.length) {
          errors.add(
            '$prefix NEW_INSTANCE Bx=$bx >= classes.length '
            '${module.classes.length} at pc=$pc',
          );
        }
    }
  }
}
