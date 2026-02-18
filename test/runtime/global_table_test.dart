import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/error.dart';
import 'package:dartic/src/runtime/global_table.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('DarticGlobalTable', () {
    test('basic store + load: store 42, load returns 42', () {
      final table = DarticGlobalTable(1);
      table.store(0, 42);
      expect(table.load(0), 42);
    });

    test('store null: null is a valid initialized value', () {
      final table = DarticGlobalTable(1);
      table.store(0, null);
      expect(table.load(0), isNull);
    });

    test('load uninitialized throws DarticError', () {
      final table = DarticGlobalTable(1);
      expect(
        () => table.load(0),
        throwsA(isA<DarticError>().having(
          (e) => e.message,
          'message',
          contains('Uninitialized'),
        )),
      );
    });

    test('isInitialized: false before store, true after store', () {
      final table = DarticGlobalTable(1);
      expect(table.isInitialized(0), isFalse);
      table.store(0, 'hello');
      expect(table.isInitialized(0), isTrue);
    });

    test('markInitializing + load throws circular dependency', () {
      final table = DarticGlobalTable(1);
      table.markInitializing(0);
      expect(
        () => table.load(0),
        throwsA(isA<DarticError>().having(
          (e) => e.message,
          'message',
          contains('Circular dependency'),
        )),
      );
    });

    test('markInitializing causes isInitialized to be false', () {
      final table = DarticGlobalTable(1);
      table.markInitializing(0);
      expect(table.isInitialized(0), isFalse);
    });

    test('resetToUninitialized: store value, reset, load throws', () {
      final table = DarticGlobalTable(1);
      table.store(0, 99);
      expect(table.load(0), 99);
      table.resetToUninitialized(0);
      expect(
        () => table.load(0),
        throwsA(isA<DarticError>()),
      );
      expect(table.isInitialized(0), isFalse);
    });

    test('multiple slots: independent read/write on different indices', () {
      final table = DarticGlobalTable(3);
      table.store(0, 'a');
      table.store(1, 42);
      table.store(2, null);

      expect(table.load(0), 'a');
      expect(table.load(1), 42);
      expect(table.load(2), isNull);
    });

    test('store overwrites previous value', () {
      final table = DarticGlobalTable(1);
      table.store(0, 'old');
      expect(table.load(0), 'old');
      table.store(0, 'new');
      expect(table.load(0), 'new');
    });

    test('count returns the number of slots', () {
      final table = DarticGlobalTable(5);
      expect(table.count, 5);
    });
  });

  group('LOAD_GLOBAL / STORE_GLOBAL interpreter tests', () {
    test('STORE_GLOBAL then LOAD_GLOBAL reads back the value', () {
      // Program:
      //   LOAD_INT v0, 42       (value stack)
      //   BOX_INT r0, v0        (box to ref stack)
      //   STORE_GLOBAL r0, 0    (globals[0] = 42)
      //   LOAD_GLOBAL r1, 0     (r1 = globals[0])
      //   UNBOX_INT v1, r1      (v1 = unbox(r1))
      //   HALT
      final bytecode = Uint32List.fromList([
        encodeAsBx(Op.loadInt, 0, 42),
        encodeABC(Op.boxInt, 0, 0, 0),
        encodeABx(Op.storeGlobal, 0, 0),
        encodeABx(Op.loadGlobal, 1, 0),
        encodeABC(Op.unboxInt, 1, 1, 0),
        encodeAx(Op.halt, 0),
      ]);

      final func = DarticFuncProto(
        funcId: 0,
        bytecode: bytecode,
        valueRegCount: 2,
        refRegCount: 2,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [func],
        constantPool: ConstantPool(),
        entryFuncId: 0,
        globalCount: 1,
        globalInitializerIds: [-1],
      );

      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.valueStack.readInt(1), 42);
    });

    test('LOAD_GLOBAL to uninitialized slot throws DarticError', () {
      final bytecode = Uint32List.fromList([
        encodeABx(Op.loadGlobal, 0, 0),
        encodeAx(Op.halt, 0),
      ]);

      final func = DarticFuncProto(
        funcId: 0,
        bytecode: bytecode,
        valueRegCount: 0,
        refRegCount: 1,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [func],
        constantPool: ConstantPool(),
        entryFuncId: 0,
        globalCount: 1,
        globalInitializerIds: [-1],
      );

      final interp = DarticInterpreter();
      expect(
        () => interp.execute(module),
        throwsA(isA<DarticError>().having(
          (e) => e.message,
          'message',
          contains('Uninitialized'),
        )),
      );
    });

    test('multiple globals with different values', () {
      // Store different values in globals[0] and globals[1], then read both.
      final bytecode = Uint32List.fromList([
        // Store 10 into globals[0]
        encodeAsBx(Op.loadInt, 0, 10),
        encodeABC(Op.boxInt, 0, 0, 0),
        encodeABx(Op.storeGlobal, 0, 0),
        // Store 20 into globals[1]
        encodeAsBx(Op.loadInt, 0, 20),
        encodeABC(Op.boxInt, 0, 0, 0),
        encodeABx(Op.storeGlobal, 0, 1),
        // Read globals[0] into v0
        encodeABx(Op.loadGlobal, 0, 0),
        encodeABC(Op.unboxInt, 0, 0, 0),
        // Read globals[1] into v1
        encodeABx(Op.loadGlobal, 1, 1),
        encodeABC(Op.unboxInt, 1, 1, 0),
        encodeAx(Op.halt, 0),
      ]);

      final func = DarticFuncProto(
        funcId: 0,
        bytecode: bytecode,
        valueRegCount: 2,
        refRegCount: 2,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [func],
        constantPool: ConstantPool(),
        entryFuncId: 0,
        globalCount: 2,
        globalInitializerIds: [-1, -1],
      );

      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 10);
      expect(interp.valueStack.readInt(1), 20);
    });

    test('string global via STORE_GLOBAL / LOAD_GLOBAL', () {
      final cp = ConstantPool();
      final strIdx = cp.addRef('hello');

      final bytecode = Uint32List.fromList([
        encodeABx(Op.loadConst, 0, strIdx),
        encodeABx(Op.storeGlobal, 0, 0),
        encodeABx(Op.loadGlobal, 1, 0),
        encodeAx(Op.halt, 0),
      ]);

      final func = DarticFuncProto(
        funcId: 0,
        bytecode: bytecode,
        valueRegCount: 0,
        refRegCount: 2,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [func],
        constantPool: cp,
        entryFuncId: 0,
        globalCount: 1,
        globalInitializerIds: [-1],
      );

      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.refStack.read(1), 'hello');
    });

    test('global initializer function runs before main', () {
      // Initializer function (funcId 0): stores 42 into globals[0], then HALT.
      final initBytecode = Uint32List.fromList([
        encodeAsBx(Op.loadInt, 0, 42),
        encodeABC(Op.boxInt, 0, 0, 0),
        encodeABx(Op.storeGlobal, 0, 0),
        encodeAx(Op.halt, 0),
      ]);
      final initFunc = DarticFuncProto(
        funcId: 0,
        bytecode: initBytecode,
        valueRegCount: 1,
        refRegCount: 1,
        paramCount: 0,
      );

      // Main function (funcId 1): loads globals[0], unboxes, HALT.
      final mainBytecode = Uint32List.fromList([
        encodeABx(Op.loadGlobal, 0, 0),
        encodeABC(Op.unboxInt, 0, 0, 0),
        encodeAx(Op.halt, 0),
      ]);
      final mainFunc = DarticFuncProto(
        funcId: 1,
        bytecode: mainBytecode,
        valueRegCount: 1,
        refRegCount: 1,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [initFunc, mainFunc],
        constantPool: ConstantPool(),
        entryFuncId: 1,
        globalCount: 1,
        globalInitializerIds: [0], // globals[0] initialized by func 0
      );

      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 42);
    });
  });
}
