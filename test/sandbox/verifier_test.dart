import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/class_info.dart';
import 'package:dartic/src/sandbox/load_error.dart';
import 'package:dartic/src/sandbox/verifier.dart';
import 'package:test/test.dart';

// ── Helper functions ──

/// Creates a minimal valid DarticModule with a single function containing
/// the given bytecode. Defaults to a single HALT instruction.
DarticModule makeModule({
  Uint32List? bytecode,
  int valueRegCount = 1,
  int refRegCount = 1,
  int paramCount = 0,
  List<ICEntry> icTable = const [],
  List<ExceptionHandler> exceptionTable = const [],
  List<UpvalueDescriptor> upvalueDescriptors = const [],
  ConstantPool? constantPool,
  List<DarticClassInfo> classes = const [],
  List<BindingEntry> bindingNames = const [],
  int entryFuncId = 0,
  List<DarticFuncProto>? extraFunctions,
  int globalCount = 0,
  List<int> globalInitializerIds = const [],
}) {
  bytecode ??= Uint32List.fromList([encodeAx(Op.halt, 0)]);
  final pool = constantPool ?? ConstantPool();

  final mainFunc = DarticFuncProto(
    funcId: 0,
    name: 'main',
    bytecode: bytecode,
    valueRegCount: valueRegCount,
    refRegCount: refRegCount,
    paramCount: paramCount,
    icTable: icTable,
    exceptionTable: exceptionTable,
    upvalueDescriptors: upvalueDescriptors,
  );

  final functions = [mainFunc, ...?extraFunctions];

  return DarticModule(
    functions: functions,
    constantPool: pool,
    entryFuncId: entryFuncId,
    classes: classes,
    bindingNames: bindingNames,
    globalCount: globalCount,
    globalInitializerIds: globalInitializerIds,
  );
}

void main() {
  late DarticVerifier verifier;

  setUp(() {
    verifier = DarticVerifier();
  });

  group('DarticLoadError', () {
    test('toString lists all errors', () {
      final err = DarticLoadError(['err1', 'err2'], modulePath: '/test.darb');
      expect(err.toString(), contains('2 error(s)'));
      expect(err.toString(), contains('err1'));
      expect(err.toString(), contains('err2'));
      expect(err.errors.length, 2);
      expect(err.modulePath, '/test.darb');
    });
  });

  group('DarticVerifier', () {
    // ── 1. Valid module passes ──
    test('valid module with HALT instruction passes', () {
      final module = makeModule();
      expect(verifier.verify(module), isTrue);
      expect(verifier.errors, isEmpty);
    });

    test('valid module with multiple instructions passes', () {
      final pool = ConstantPool.from(
        refs: ['hello'],
        ints: Int64List.fromList([42]),
        doubles: Float64List.fromList([3.14]),
        names: ['toString'],
      );
      final bytecode = Uint32List.fromList([
        encodeABx(Op.loadConst, 0, 0), // loadConst r0, refs[0]
        encodeABx(Op.loadConstInt, 0, 0), // loadConstInt v0, ints[0]
        encodeABx(Op.loadConstDbl, 0, 0), // loadConstDbl v0, doubles[0]
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(
        bytecode: bytecode,
        constantPool: pool,
        valueRegCount: 2,
        refRegCount: 2,
      );
      expect(verifier.verify(module), isTrue);
      expect(verifier.errors, isEmpty);
    });

    // ── 2. Invalid opcode detected ──
    test('detects invalid opcode', () {
      final bytecode = Uint32List.fromList([
        0x000000AA, // invalid opcode 0xAA
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors.length, 1);
      expect(verifier.errors[0], contains('Invalid opcode'));
      expect(verifier.errors[0], contains('0xaa'));
    });

    // ── 3. Jump target out of range (past codeLength) ──
    test('detects jump target past end of code', () {
      // jump with sBx = +100, code length = 2
      // target = pc + 1 + 100 = 101, far past code end
      final bytecode = Uint32List.fromList([
        encodeAsBx(Op.jump, 0, 100),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('Jump target'));
    });

    // ── 4. Jump target negative (before 0) ──
    test('detects jump target before start of code', () {
      // At pc=0: jump with sBx = -10 => target = 0 + 1 + (-10) = -9
      final bytecode = Uint32List.fromList([
        encodeAsBx(Op.jump, 0, -10),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('Jump target'));
    });

    test('detects jumpIfTrue target out of range', () {
      final bytecode = Uint32List.fromList([
        encodeAsBx(Op.jumpIfTrue, 0, 100),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('Jump target'));
    });

    test('detects jumpIfFalse target out of range', () {
      final bytecode = Uint32List.fromList([
        encodeAsBx(Op.jumpIfFalse, 0, 100),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
    });

    test('detects jumpIfNull target out of range', () {
      final bytecode = Uint32List.fromList([
        encodeAsBx(Op.jumpIfNull, 0, 100),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
    });

    test('detects jumpIfNnull target out of range', () {
      final bytecode = Uint32List.fromList([
        encodeAsBx(Op.jumpIfNnull, 0, 100),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
    });

    test('detects jumpAx target out of range', () {
      final bytecode = Uint32List.fromList([
        encodesAx(Op.jumpAx, 1000),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('Jump target'));
    });

    test('valid jump targets pass', () {
      // jump forward by 1 (skip one instruction)
      final bytecode = Uint32List.fromList([
        encodeAsBx(Op.jump, 0, 1), // target = 0 + 1 + 1 = 2
        encodeAx(Op.nop, 0), // skipped
        encodeAx(Op.halt, 0), // target
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isTrue);
      expect(verifier.errors, isEmpty);
    });

    // ── 5. Register index out of range ──
    test('detects value register A out of range for addInt', () {
      // addInt: A=val, B=val, C=val — all must be < valueRegCount
      // valueRegCount = 2, but A = 5
      final bytecode = Uint32List.fromList([
        encodeABC(Op.addInt, 5, 0, 1),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode, valueRegCount: 2);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('register'));
    });

    test('detects ref register A out of range for loadConst', () {
      final pool = ConstantPool.from(
        refs: ['test'],
        ints: Int64List(0),
        doubles: Float64List(0),
        names: [],
      );
      // loadConst: A=ref, Bx=refs pool index. refRegCount = 1, A = 5
      final bytecode = Uint32List.fromList([
        encodeABx(Op.loadConst, 5, 0),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(
        bytecode: bytecode,
        constantPool: pool,
        refRegCount: 1,
      );
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors.any((e) => e.contains('register')), isTrue);
    });

    test('detects ref register B out of range for moveRef', () {
      // moveRef: A=ref, B=ref — both must be < refRegCount
      final bytecode = Uint32List.fromList([
        encodeABC(Op.moveRef, 0, 10, 0),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode, refRegCount: 2);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
    });

    // ── 6. Constant pool index out of range ──
    test('detects LOAD_CONST Bx out of range', () {
      // empty constant pool, but Bx = 5
      final bytecode = Uint32List.fromList([
        encodeABx(Op.loadConst, 0, 5),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('Constant pool'));
    });

    test('detects LOAD_CONST_INT Bx out of range', () {
      final bytecode = Uint32List.fromList([
        encodeABx(Op.loadConstInt, 0, 5),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('Constant pool'));
    });

    test('detects LOAD_CONST_DBL Bx out of range', () {
      final bytecode = Uint32List.fromList([
        encodeABx(Op.loadConstDbl, 0, 3),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('Constant pool'));
    });

    // ── 7. WIDE at end of code ──
    test('detects WIDE prefix at end of code (last position)', () {
      final bytecode = Uint32List.fromList([
        encodeAx(Op.nop, 0),
        Op.wide, // WIDE at position 1, but code only has 2 words
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('WIDE'));
    });

    test('detects WIDE prefix at second-to-last position', () {
      final bytecode = Uint32List.fromList([
        Op.wide, // WIDE at position 0, needs 2 more words but only 1 available
        0x00000000, // extension word, but no original instruction after
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('WIDE'));
    });

    test('valid WIDE prefix passes', () {
      // WIDE + extension + loadConst instruction (3 words)
      final pool = ConstantPool.from(
        refs: ['val'],
        ints: Int64List(0),
        doubles: Float64List(0),
        names: [],
      );
      final wideWords = encodeWideABx(Op.loadConst, 0, 0);
      final bytecode = Uint32List.fromList([
        ...wideWords,
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(
        bytecode: bytecode,
        constantPool: pool,
        refRegCount: 2,
      );
      expect(verifier.verify(module), isTrue);
      expect(verifier.errors, isEmpty);
    });

    // ── 8. CALL_STATIC Bx out of range ──
    test('detects CALL_STATIC Bx out of range', () {
      // functions.length = 1 (only main), but callStatic references funcId 5
      final bytecode = Uint32List.fromList([
        encodeABx(Op.callStatic, 0, 5),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('CALL_STATIC'));
    });

    test('valid CALL_STATIC passes', () {
      final targetFunc = DarticFuncProto(
        funcId: 1,
        name: 'target',
        bytecode: Uint32List.fromList([encodeAx(Op.halt, 0)]),
        valueRegCount: 1,
        refRegCount: 1,
        paramCount: 0,
      );
      final bytecode = Uint32List.fromList([
        encodeABx(Op.callStatic, 0, 1), // call function at index 1
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(
        bytecode: bytecode,
        extraFunctions: [targetFunc],
      );
      expect(verifier.verify(module), isTrue);
      expect(verifier.errors, isEmpty);
    });

    // ── 9. Exception handler invalid range ──
    test('detects exception handler with startPC >= endPC', () {
      final bytecode = Uint32List.fromList([
        encodeAx(Op.nop, 0),
        encodeAx(Op.nop, 0),
        encodeAx(Op.halt, 0),
      ]);
      final handler = ExceptionHandler(
        startPC: 2,
        endPC: 1, // invalid: start >= end
        handlerPC: 0,
        exceptionReg: 0,
        stackTraceReg: 0,
      );
      final module = makeModule(
        bytecode: bytecode,
        exceptionTable: [handler],
        refRegCount: 2,
      );
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('Exception handler'));
    });

    // ── 10. Exception handler PC out of range ──
    test('detects exception handler handlerPC out of range', () {
      final bytecode = Uint32List.fromList([
        encodeAx(Op.nop, 0),
        encodeAx(Op.halt, 0),
      ]);
      final handler = ExceptionHandler(
        startPC: 0,
        endPC: 1,
        handlerPC: 100, // way past codeLength
        exceptionReg: 0,
        stackTraceReg: 0,
      );
      final module = makeModule(
        bytecode: bytecode,
        exceptionTable: [handler],
        refRegCount: 2,
      );
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors.any((e) => e.contains('handlerPC')), isTrue);
    });

    test('detects exception handler exceptionReg out of range', () {
      final bytecode = Uint32List.fromList([
        encodeAx(Op.nop, 0),
        encodeAx(Op.nop, 0),
        encodeAx(Op.halt, 0),
      ]);
      final handler = ExceptionHandler(
        startPC: 0,
        endPC: 1,
        handlerPC: 1,
        exceptionReg: 50, // way past refRegCount
        stackTraceReg: 0,
      );
      final module = makeModule(
        bytecode: bytecode,
        exceptionTable: [handler],
        refRegCount: 2,
      );
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors.any((e) => e.contains('exceptionReg')), isTrue);
    });

    // ── 11. Upvalue descriptor out of range ──
    test('detects upvalue descriptor isLocal index out of range', () {
      final bytecode = Uint32List.fromList([encodeAx(Op.halt, 0)]);
      final module = makeModule(
        bytecode: bytecode,
        refRegCount: 2,
        upvalueDescriptors: [
          UpvalueDescriptor(isLocal: true, index: 50), // way past refRegCount
        ],
      );
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('Upvalue'));
    });

    // ── 12. Class table superClassId out of range ──
    test('detects class with superClassId out of range', () {
      final classInfo = DarticClassInfo(
        classId: 0,
        name: 'TestClass',
        superClassId: 99, // way past classes.length
        refFieldCount: 0,
        valueFieldCount: 0,
      );
      final module = makeModule(classes: [classInfo]);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('superClassId'));
    });

    test('class with superClassId -1 (root) passes', () {
      final classInfo = DarticClassInfo(
        classId: 0,
        name: 'Object',
        superClassId: -1,
        refFieldCount: 0,
        valueFieldCount: 0,
      );
      final module = makeModule(classes: [classInfo]);
      expect(verifier.verify(module), isTrue);
      expect(verifier.errors, isEmpty);
    });

    test('class with valid superClassId passes', () {
      final parent = DarticClassInfo(
        classId: 0,
        name: 'Parent',
        superClassId: -1,
        refFieldCount: 0,
        valueFieldCount: 0,
      );
      final child = DarticClassInfo(
        classId: 1,
        name: 'Child',
        superClassId: 0,
        refFieldCount: 0,
        valueFieldCount: 0,
      );
      final module = makeModule(classes: [parent, child]);
      expect(verifier.verify(module), isTrue);
      expect(verifier.errors, isEmpty);
    });

    // ── 13. Entry point out of range ──
    test('detects entryFuncId out of range', () {
      final module = makeModule(entryFuncId: 99);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('Entry point'));
    });

    // ── 14. IC table nameIndex out of range ──
    test('detects IC table methodNameIndex out of range', () {
      final pool = ConstantPool(); // empty names
      final bytecode = Uint32List.fromList([encodeAx(Op.halt, 0)]);
      final module = makeModule(
        bytecode: bytecode,
        constantPool: pool,
        icTable: [ICEntry(methodNameIndex: 5)], // no names in pool
      );
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('IC'));
    });

    test('valid IC table passes', () {
      final pool = ConstantPool.from(
        refs: [],
        ints: Int64List(0),
        doubles: Float64List(0),
        names: ['toString', 'hashCode'],
      );
      final bytecode = Uint32List.fromList([encodeAx(Op.halt, 0)]);
      final module = makeModule(
        bytecode: bytecode,
        constantPool: pool,
        icTable: [ICEntry(methodNameIndex: 0), ICEntry(methodNameIndex: 1)],
      );
      expect(verifier.verify(module), isTrue);
      expect(verifier.errors, isEmpty);
    });

    // ── 15. Multiple errors collected ──
    test('collects multiple errors in a single pass', () {
      final bytecode = Uint32List.fromList([
        0x000000AA, // invalid opcode
        encodeABx(Op.loadConst, 0, 99), // const pool out of range
        encodeAsBx(Op.jump, 0, 500), // jump out of range
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(
        bytecode: bytecode,
        entryFuncId: 99, // also out of range
      );
      expect(verifier.verify(module), isFalse);
      // Should have at least 3 errors: invalid opcode, const pool, jump target,
      // plus entry point
      expect(verifier.errors.length, greaterThanOrEqualTo(3));
    });

    // ── 16. CALL_HOST Bx out of range ──
    test('detects CALL_HOST Bx out of range', () {
      // bindingNames is empty, but callHost references index 3
      final bytecode = Uint32List.fromList([
        encodeABx(Op.callHost, 0, 3),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('CALL_HOST'));
    });

    test('valid CALL_HOST passes', () {
      final bytecode = Uint32List.fromList([
        encodeABx(Op.callHost, 0, 0),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(
        bytecode: bytecode,
        bindingNames: [BindingEntry(name: 'print', argCount: 1)],
      );
      expect(verifier.verify(module), isTrue);
      expect(verifier.errors, isEmpty);
    });

    // ── Additional edge cases ──

    test('CALL_VIRTUAL C >= icTable.length', () {
      final pool = ConstantPool.from(
        refs: [],
        ints: Int64List(0),
        doubles: Float64List(0),
        names: ['method'],
      );
      // callVirtual: A=ref, B=ref, C=IC index
      final bytecode = Uint32List.fromList([
        encodeABC(Op.callVirtual, 0, 0, 5), // icTable has 0 entries
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(
        bytecode: bytecode,
        constantPool: pool,
        refRegCount: 2,
      );
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('CALL_VIRTUAL'));
    });

    test('CALL_SUPER Bx out of range', () {
      final bytecode = Uint32List.fromList([
        encodeABx(Op.callSuper, 0, 99),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('CALL_SUPER'));
    });

    test('closure Bx out of range', () {
      final bytecode = Uint32List.fromList([
        encodeABx(Op.closure, 0, 99),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('closure'));
    });

    test('newInstance Bx out of range', () {
      final bytecode = Uint32List.fromList([
        encodeABx(Op.newInstance, 0, 99),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('NEW_INSTANCE'));
    });

    test('class method references valid function', () {
      final targetFunc = DarticFuncProto(
        funcId: 1,
        name: 'method',
        bytecode: Uint32List.fromList([encodeAx(Op.halt, 0)]),
        valueRegCount: 1,
        refRegCount: 1,
        paramCount: 0,
      );
      final classInfo = DarticClassInfo(
        classId: 0,
        name: 'TestClass',
        superClassId: -1,
        refFieldCount: 0,
        valueFieldCount: 0,
      );
      classInfo.methods[0] = targetFunc;

      final module = makeModule(
        classes: [classInfo],
        extraFunctions: [targetFunc],
      );
      expect(verifier.verify(module), isTrue);
    });

    test('class method references invalid function', () {
      // Create a function proto with funcId that is NOT in module.functions
      final invalidFunc = DarticFuncProto(
        funcId: 99, // not in module.functions
        name: 'ghost',
        bytecode: Uint32List.fromList([encodeAx(Op.halt, 0)]),
        valueRegCount: 1,
        refRegCount: 1,
        paramCount: 0,
      );
      final classInfo = DarticClassInfo(
        classId: 0,
        name: 'TestClass',
        superClassId: -1,
        refFieldCount: 0,
        valueFieldCount: 0,
      );
      classInfo.methods[0] = invalidFunc;

      final module = makeModule(classes: [classInfo]);
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('method'));
    });

    test('getFieldDyn C >= names.length', () {
      final pool = ConstantPool(); // no names
      final bytecode = Uint32List.fromList([
        encodeABC(Op.getFieldDyn, 0, 0, 5), // names pool index 5, but empty
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(
        bytecode: bytecode,
        constantPool: pool,
        refRegCount: 2,
      );
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
    });

    test('setFieldDyn C >= names.length', () {
      final pool = ConstantPool();
      final bytecode = Uint32List.fromList([
        encodeABC(Op.setFieldDyn, 0, 0, 5),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(
        bytecode: bytecode,
        constantPool: pool,
        refRegCount: 2,
      );
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
    });

    test('invokeDyn C >= names.length', () {
      final pool = ConstantPool();
      final bytecode = Uint32List.fromList([
        encodeABC(Op.invokeDyn, 0, 0, 5),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(
        bytecode: bytecode,
        constantPool: pool,
        refRegCount: 2,
      );
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
    });

    test('loadGlobal Bx >= globalCount', () {
      final bytecode = Uint32List.fromList([
        encodeABx(Op.loadGlobal, 0, 5),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(
        bytecode: bytecode,
        globalCount: 2,
      );
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('global'));
    });

    test('storeGlobal Bx >= globalCount', () {
      final bytecode = Uint32List.fromList([
        encodeABx(Op.storeGlobal, 0, 5),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(
        bytecode: bytecode,
        globalCount: 2,
      );
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
      expect(verifier.errors[0], contains('global'));
    });

    test('valid loadGlobal/storeGlobal passes', () {
      final bytecode = Uint32List.fromList([
        encodeABx(Op.loadGlobal, 0, 0),
        encodeABx(Op.storeGlobal, 0, 1),
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(
        bytecode: bytecode,
        globalCount: 3,
      );
      expect(verifier.verify(module), isTrue);
      expect(verifier.errors, isEmpty);
    });

    test('exception handler endPC > codeLength', () {
      final bytecode = Uint32List.fromList([
        encodeAx(Op.nop, 0),
        encodeAx(Op.halt, 0),
      ]);
      final handler = ExceptionHandler(
        startPC: 0,
        endPC: 100, // past code end
        handlerPC: 0,
        exceptionReg: 0,
        stackTraceReg: 0,
      );
      final module = makeModule(
        bytecode: bytecode,
        exceptionTable: [handler],
        refRegCount: 2,
      );
      expect(verifier.verify(module), isFalse);
      expect(verifier.errors, isNotEmpty);
    });

    test('verify clears errors between calls', () {
      final invalidModule = makeModule(entryFuncId: 99);
      verifier.verify(invalidModule);
      expect(verifier.errors, isNotEmpty);

      final validModule = makeModule();
      final result = verifier.verify(validModule);
      expect(result, isTrue);
      expect(verifier.errors, isEmpty);
    });

    // ── C1 fix: assert_ uses value stack ──

    test('assert_ register A is checked against valueRegCount', () {
      // ASSERT A=5, Bx=0 — A should be on value stack.
      // valueRegCount=2, so reg 5 is out of bounds.
      final bytecode = Uint32List.fromList([
        encodeAsBx(Op.assert_, 5, 0),
        encodeAx(Op.halt, 0),
      ]);
      final pool = ConstantPool()..addRef('assertion message');
      final module = makeModule(
        bytecode: bytecode,
        valueRegCount: 2,
        refRegCount: 8,
        constantPool: pool,
      );
      expect(verifier.verify(module), isFalse);
      expect(
        verifier.errors.any(
            (e) => e.contains('Value register') && e.contains('A=5')),
        isTrue,
        reason: 'Should report assert_ A register out of value stack bounds',
      );
    });

    test('assert_ valid when A within valueRegCount', () {
      final bytecode = Uint32List.fromList([
        encodeAsBx(Op.assert_, 0, 0),
        encodeAx(Op.halt, 0),
      ]);
      final pool = ConstantPool()..addRef('ok');
      final module = makeModule(
        bytecode: bytecode,
        valueRegCount: 2,
        refRegCount: 2,
        constantPool: pool,
      );
      expect(verifier.verify(module), isTrue);
    });

    // ── C2 fix: exception handler valStackDP/refStackDP ──

    test('exception handler valStackDP out of range', () {
      final bytecode = Uint32List.fromList([
        encodeAx(Op.nop, 0),
        encodeAx(Op.halt, 0),
      ]);
      final handler = ExceptionHandler(
        startPC: 0,
        endPC: 1,
        handlerPC: 0,
        valStackDP: 100, // way beyond valueRegCount
        refStackDP: 0,
        exceptionReg: 0,
        stackTraceReg: -1,
      );
      final module = makeModule(
        bytecode: bytecode,
        exceptionTable: [handler],
        valueRegCount: 4,
        refRegCount: 2,
      );
      expect(verifier.verify(module), isFalse);
      expect(
        verifier.errors.any((e) => e.contains('valStackDP')),
        isTrue,
      );
    });

    test('exception handler refStackDP out of range', () {
      final bytecode = Uint32List.fromList([
        encodeAx(Op.nop, 0),
        encodeAx(Op.halt, 0),
      ]);
      final handler = ExceptionHandler(
        startPC: 0,
        endPC: 1,
        handlerPC: 0,
        valStackDP: 0,
        refStackDP: 100, // way beyond refRegCount
        exceptionReg: 0,
        stackTraceReg: -1,
      );
      final module = makeModule(
        bytecode: bytecode,
        exceptionTable: [handler],
        valueRegCount: 4,
        refRegCount: 2,
      );
      expect(verifier.verify(module), isFalse);
      expect(
        verifier.errors.any((e) => e.contains('refStackDP')),
        isTrue,
      );
    });

    // ── I4 fix: stackTraceReg sentinel validation ──

    test('exception handler stackTraceReg -1 is valid (sentinel)', () {
      final bytecode = Uint32List.fromList([
        encodeAx(Op.nop, 0),
        encodeAx(Op.halt, 0),
      ]);
      final handler = ExceptionHandler(
        startPC: 0,
        endPC: 1,
        handlerPC: 0,
        exceptionReg: 0,
        stackTraceReg: -1,
      );
      final module = makeModule(
        bytecode: bytecode,
        exceptionTable: [handler],
        refRegCount: 2,
      );
      expect(verifier.verify(module), isTrue);
    });

    test('exception handler stackTraceReg -2 is invalid', () {
      final bytecode = Uint32List.fromList([
        encodeAx(Op.nop, 0),
        encodeAx(Op.halt, 0),
      ]);
      final handler = ExceptionHandler(
        startPC: 0,
        endPC: 1,
        handlerPC: 0,
        exceptionReg: 0,
        stackTraceReg: -2,
      );
      final module = makeModule(
        bytecode: bytecode,
        exceptionTable: [handler],
        refRegCount: 2,
      );
      expect(verifier.verify(module), isFalse);
      expect(
        verifier.errors.any((e) => e.contains('stackTraceReg')),
        isTrue,
      );
    });

    // ── I1 fix: WIDE nested detection ──

    test('nested WIDE is rejected', () {
      // WIDE + extension + WIDE is invalid.
      final bytecode = Uint32List.fromList([
        encodeABC(Op.wide, 0, 0, 0), // outer WIDE
        0, // extension word
        encodeABC(Op.wide, 0, 0, 0), // nested WIDE (invalid)
        0, // extension word
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(
        verifier.errors.any((e) => e.contains('nested WIDE')),
        isTrue,
      );
    });

    test('WIDE with invalid widened opcode is rejected', () {
      final bytecode = Uint32List.fromList([
        encodeABC(Op.wide, 0, 0, 0), // WIDE prefix
        0, // extension word
        encodeABC(0xB0, 0, 0, 0), // reserved opcode 0xB0
        encodeAx(Op.halt, 0),
      ]);
      final module = makeModule(bytecode: bytecode);
      expect(verifier.verify(module), isFalse);
      expect(
        verifier.errors.any((e) => e.contains('widened opcode')),
        isTrue,
      );
    });
  });
}
