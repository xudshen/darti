import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:test/test.dart';

import '../helpers/module_helper.dart';

void main() {
  group('ExceptionHandler data structure', () {
    test('holds all 8 fields correctly', () {
      final handler = ExceptionHandler(
        startPC: 5,
        endPC: 25,
        handlerPC: 30,
        catchType: 7,
        valStackDP: 4,
        refStackDP: 2,
        exceptionReg: 10,
        stackTraceReg: 11,
      );

      expect(handler.startPC, 5);
      expect(handler.endPC, 25);
      expect(handler.handlerPC, 30);
      expect(handler.catchType, 7);
      expect(handler.valStackDP, 4);
      expect(handler.refStackDP, 2);
      expect(handler.exceptionReg, 10);
      expect(handler.stackTraceReg, 11);
    });

    test('default catchType = -1 means catch-all/finally', () {
      final handler = ExceptionHandler(
        startPC: 0,
        endPC: 10,
        handlerPC: 15,
        exceptionReg: 0,
        stackTraceReg: 1,
      );

      expect(handler.catchType, -1);
    });

    test('default valStackDP and refStackDP are 0', () {
      final handler = ExceptionHandler(
        startPC: 0,
        endPC: 10,
        handlerPC: 15,
        exceptionReg: 0,
        stackTraceReg: 1,
      );

      expect(handler.valStackDP, 0);
      expect(handler.refStackDP, 0);
    });

    test('toString includes PC range and catch type info', () {
      final catchAll = ExceptionHandler(
        startPC: 10,
        endPC: 20,
        handlerPC: 30,
        exceptionReg: 0,
        stackTraceReg: 1,
      );
      expect(catchAll.toString(), contains('pc=[10,20)'));
      expect(catchAll.toString(), contains('all'));

      final typed = ExceptionHandler(
        startPC: 10,
        endPC: 20,
        handlerPC: 30,
        catchType: 5,
        exceptionReg: 0,
        stackTraceReg: 1,
      );
      expect(typed.toString(), contains('type5'));
    });
  });

  group('handler table sorting', () {
    test('can be sorted by (startPC, endPC) range', () {
      final handlers = [
        ExceptionHandler(
          startPC: 20,
          endPC: 30,
          handlerPC: 40,
          exceptionReg: 0,
          stackTraceReg: 1,
        ),
        ExceptionHandler(
          startPC: 5,
          endPC: 15,
          handlerPC: 25,
          exceptionReg: 2,
          stackTraceReg: 3,
        ),
        ExceptionHandler(
          startPC: 5,
          endPC: 10,
          handlerPC: 20,
          exceptionReg: 4,
          stackTraceReg: 5,
        ),
      ];

      handlers.sort((a, b) {
        final cmp = a.startPC.compareTo(b.startPC);
        if (cmp != 0) return cmp;
        return a.endPC.compareTo(b.endPC);
      });

      // After sorting: (5,10), (5,15), (20,30)
      expect(handlers[0].startPC, 5);
      expect(handlers[0].endPC, 10);
      expect(handlers[1].startPC, 5);
      expect(handlers[1].endPC, 15);
      expect(handlers[2].startPC, 20);
      expect(handlers[2].endPC, 30);
    });
  });

  group('serialization roundtrip', () {
    test('single handler preserves all 8 fields', () {
      final proto = buildFuncProto(
        exceptionTable: [
          ExceptionHandler(
            startPC: 10,
            endPC: 20,
            handlerPC: 30,
            catchType: 5,
            valStackDP: 3,
            refStackDP: 1,
            exceptionReg: 7,
            stackTraceReg: 8,
          ),
        ],
      );

      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      final handlers = result.functions[0].exceptionTable;
      expect(handlers.length, 1);

      final h = handlers[0];
      expect(h.startPC, 10);
      expect(h.endPC, 20);
      expect(h.handlerPC, 30);
      expect(h.catchType, 5);
      expect(h.valStackDP, 3);
      expect(h.refStackDP, 1);
      expect(h.exceptionReg, 7);
      expect(h.stackTraceReg, 8);
    });

    test('catch-all handler (catchType = -1) survives roundtrip', () {
      final proto = buildFuncProto(
        exceptionTable: [
          ExceptionHandler(
            startPC: 0,
            endPC: 100,
            handlerPC: 200,
            catchType: -1,
            valStackDP: 0,
            refStackDP: 0,
            exceptionReg: 2,
            stackTraceReg: 3,
          ),
        ],
      );

      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      final h = result.functions[0].exceptionTable[0];
      expect(h.catchType, -1);
    });

    test('multiple handlers in a single function survive roundtrip', () {
      final proto = buildFuncProto(
        exceptionTable: [
          // Inner try — typed catch
          ExceptionHandler(
            startPC: 10,
            endPC: 20,
            handlerPC: 30,
            catchType: 5,
            valStackDP: 3,
            refStackDP: 1,
            exceptionReg: 7,
            stackTraceReg: 8,
          ),
          // Outer try — catch-all
          ExceptionHandler(
            startPC: 0,
            endPC: 50,
            handlerPC: 60,
            catchType: -1,
            valStackDP: 0,
            refStackDP: 0,
            exceptionReg: 2,
            stackTraceReg: 3,
          ),
          // Separate region
          ExceptionHandler(
            startPC: 100,
            endPC: 200,
            handlerPC: 210,
            catchType: 42,
            valStackDP: 5,
            refStackDP: 2,
            exceptionReg: 0,
            stackTraceReg: 1,
          ),
        ],
      );

      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      final handlers = result.functions[0].exceptionTable;
      expect(handlers.length, 3);

      // First handler
      expect(handlers[0].startPC, 10);
      expect(handlers[0].endPC, 20);
      expect(handlers[0].handlerPC, 30);
      expect(handlers[0].catchType, 5);
      expect(handlers[0].valStackDP, 3);
      expect(handlers[0].refStackDP, 1);
      expect(handlers[0].exceptionReg, 7);
      expect(handlers[0].stackTraceReg, 8);

      // Second handler
      expect(handlers[1].startPC, 0);
      expect(handlers[1].endPC, 50);
      expect(handlers[1].handlerPC, 60);
      expect(handlers[1].catchType, -1);
      expect(handlers[1].valStackDP, 0);
      expect(handlers[1].refStackDP, 0);
      expect(handlers[1].exceptionReg, 2);
      expect(handlers[1].stackTraceReg, 3);

      // Third handler
      expect(handlers[2].startPC, 100);
      expect(handlers[2].endPC, 200);
      expect(handlers[2].handlerPC, 210);
      expect(handlers[2].catchType, 42);
      expect(handlers[2].valStackDP, 5);
      expect(handlers[2].refStackDP, 2);
      expect(handlers[2].exceptionReg, 0);
      expect(handlers[2].stackTraceReg, 1);
    });

    test('empty exception table roundtrip works', () {
      final proto = buildFuncProto(exceptionTable: []);

      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      expect(result.functions[0].exceptionTable, isEmpty);
    });

    test('function with exception handlers + bytecode + IC entries all survive',
        () {
      final pool = ConstantPool();
      pool.addName('toString');
      pool.addName('hashCode');

      final bytecode = Uint32List.fromList([
        encodeABC(Op.addInt, 0, 1, 2),
        encodeABC(Op.subInt, 3, 4, 5),
        encodeABC(Op.returnVal, 0, 0, 0),
        encodeAx(Op.halt, 0),
      ]);

      final proto = DarticFuncProto(
        funcId: 0,
        name: 'complexFunc',
        bytecode: bytecode,
        valueRegCount: 6,
        refRegCount: 3,
        paramCount: 2,
        exceptionTable: [
          ExceptionHandler(
            startPC: 0,
            endPC: 3,
            handlerPC: 3,
            catchType: -1,
            valStackDP: 2,
            refStackDP: 1,
            exceptionReg: 4,
            stackTraceReg: 5,
          ),
        ],
        icTable: [
          ICEntry(methodNameIndex: 0),
          ICEntry(methodNameIndex: 1),
        ],
      );

      final module = buildModuleFrom(functions: [proto], pool: pool);
      final result = roundtripModule(module);

      final f = result.functions[0];

      // Bytecode preserved
      expect(f.bytecode.length, 4);
      expect(f.bytecode, bytecode);
      expect(f.name, 'complexFunc');
      expect(f.valueRegCount, 6);
      expect(f.refRegCount, 3);
      expect(f.paramCount, 2);

      // Exception handler preserved
      expect(f.exceptionTable.length, 1);
      final h = f.exceptionTable[0];
      expect(h.startPC, 0);
      expect(h.endPC, 3);
      expect(h.handlerPC, 3);
      expect(h.catchType, -1);
      expect(h.valStackDP, 2);
      expect(h.refStackDP, 1);
      expect(h.exceptionReg, 4);
      expect(h.stackTraceReg, 5);

      // IC entries preserved
      expect(f.icTable.length, 2);
      expect(f.icTable[0].methodNameIndex, 0);
      expect(f.icTable[1].methodNameIndex, 1);
      // IC runtime state resets
      expect(f.icTable[0].cachedClassId, -1);
      expect(f.icTable[1].cachedClassId, -1);

      // Constant pool preserved
      expect(result.constantPool.nameCount, 2);
      expect(result.constantPool.getName(0), 'toString');
      expect(result.constantPool.getName(1), 'hashCode');
    });

    test('handler order is preserved across roundtrip', () {
      // Intentionally unsorted order to verify order preservation
      final proto = buildFuncProto(
        exceptionTable: [
          ExceptionHandler(
            startPC: 50,
            endPC: 60,
            handlerPC: 70,
            exceptionReg: 0,
            stackTraceReg: 1,
          ),
          ExceptionHandler(
            startPC: 10,
            endPC: 20,
            handlerPC: 30,
            exceptionReg: 2,
            stackTraceReg: 3,
          ),
        ],
      );

      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      final handlers = result.functions[0].exceptionTable;
      // Order must match input order, not sorted order
      expect(handlers[0].startPC, 50);
      expect(handlers[1].startPC, 10);
    });

    test('multiple functions each with handlers survive roundtrip', () {
      final f0 = buildFuncProto(
        funcId: 0,
        name: 'funcA',
        exceptionTable: [
          ExceptionHandler(
            startPC: 0,
            endPC: 10,
            handlerPC: 15,
            catchType: 3,
            valStackDP: 1,
            refStackDP: 0,
            exceptionReg: 0,
            stackTraceReg: 1,
          ),
        ],
      );

      final f1 = buildFuncProto(
        funcId: 1,
        name: 'funcB',
        exceptionTable: [
          ExceptionHandler(
            startPC: 5,
            endPC: 50,
            handlerPC: 55,
            catchType: -1,
            valStackDP: 2,
            refStackDP: 1,
            exceptionReg: 3,
            stackTraceReg: 4,
          ),
          ExceptionHandler(
            startPC: 60,
            endPC: 70,
            handlerPC: 75,
            catchType: 8,
            valStackDP: 0,
            refStackDP: 0,
            exceptionReg: 5,
            stackTraceReg: 6,
          ),
        ],
      );

      final module = buildModuleFrom(functions: [f0, f1], entryFuncId: 1);
      final result = roundtripModule(module);

      expect(result.functions.length, 2);

      // Function 0: 1 handler
      final h0 = result.functions[0].exceptionTable;
      expect(h0.length, 1);
      expect(h0[0].startPC, 0);
      expect(h0[0].catchType, 3);

      // Function 1: 2 handlers
      final h1 = result.functions[1].exceptionTable;
      expect(h1.length, 2);
      expect(h1[0].startPC, 5);
      expect(h1[0].catchType, -1);
      expect(h1[1].startPC, 60);
      expect(h1[1].catchType, 8);
    });
  });
}
