import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:test/test.dart';

void main() {
  group('ICEntry', () {
    test('initial cachedClassId is -1 (uncached)', () {
      final entry = ICEntry(methodNameIndex: 5);
      expect(entry.methodNameIndex, 5);
      expect(entry.cachedClassId, -1);
      expect(entry.cachedMethodOffset, 0);
    });

    test('can update cached values', () {
      final entry = ICEntry(methodNameIndex: 3);
      entry.cachedClassId = 42;
      entry.cachedMethodOffset = 100;
      expect(entry.cachedClassId, 42);
      expect(entry.cachedMethodOffset, 100);
    });
  });

  group('DarticFuncProto', () {
    test('holds bytecode and register counts', () {
      final bytecode = Uint32List.fromList([
        encodeABC(Opcode.addInt.code, 0, 1, 2),
        encodeAx(Opcode.halt.code, 0),
      ]);

      final proto = DarticFuncProto(
        funcId: 0,
        bytecode: bytecode,
        valueRegCount: 3,
        refRegCount: 1,
        paramCount: 2,
      );

      expect(proto.funcId, 0);
      expect(proto.bytecode.length, 2);
      expect(proto.valueRegCount, 3);
      expect(proto.refRegCount, 1);
      expect(proto.paramCount, 2);
    });

    test('holds IC table', () {
      final proto = DarticFuncProto(
        funcId: 1,
        bytecode: Uint32List(0),
        valueRegCount: 0,
        refRegCount: 0,
        paramCount: 0,
        icTable: [
          ICEntry(methodNameIndex: 10),
          ICEntry(methodNameIndex: 20),
        ],
      );

      expect(proto.icTable.length, 2);
      expect(proto.icTable[0].methodNameIndex, 10);
      expect(proto.icTable[1].methodNameIndex, 20);
    });

    test('IC table defaults to empty', () {
      final proto = DarticFuncProto(
        funcId: 0,
        bytecode: Uint32List(0),
        valueRegCount: 0,
        refRegCount: 0,
        paramCount: 0,
      );
      expect(proto.icTable, isEmpty);
    });

    test('exception table defaults to empty', () {
      final proto = DarticFuncProto(
        funcId: 0,
        bytecode: Uint32List(0),
        valueRegCount: 0,
        refRegCount: 0,
        paramCount: 0,
      );
      expect(proto.exceptionTable, isEmpty);
    });

    test('upvalue descriptors defaults to empty', () {
      final proto = DarticFuncProto(
        funcId: 0,
        bytecode: Uint32List(0),
        valueRegCount: 0,
        refRegCount: 0,
        paramCount: 0,
      );
      expect(proto.upvalueDescriptors, isEmpty);
    });
  });

  group('DarticModule', () {
    test('holds function table and constant pool', () {
      final pool = ConstantPool();
      pool.addInt(42);

      final proto = DarticFuncProto(
        funcId: 0,
        bytecode: Uint32List.fromList([
          encodeAx(Opcode.halt.code, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 0,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [proto],
        constantPool: pool,
        entryFuncId: 0,
      );

      expect(module.functions.length, 1);
      expect(module.constantPool.getInt(0), 42);
      expect(module.entryFuncId, 0);
    });

    test('can retrieve function by funcId index', () {
      final protos = [
        DarticFuncProto(
          funcId: 0,
          bytecode: Uint32List(1),
          valueRegCount: 2,
          refRegCount: 0,
          paramCount: 0,
        ),
        DarticFuncProto(
          funcId: 1,
          bytecode: Uint32List(3),
          valueRegCount: 5,
          refRegCount: 1,
          paramCount: 2,
        ),
      ];

      final module = DarticModule(
        functions: protos,
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

      expect(module.functions[0].funcId, 0);
      expect(module.functions[0].valueRegCount, 2);
      expect(module.functions[1].funcId, 1);
      expect(module.functions[1].paramCount, 2);
    });

    test('entry point references valid function', () {
      final module = DarticModule(
        functions: [
          DarticFuncProto(
            funcId: 0,
            bytecode: Uint32List(1),
            valueRegCount: 0,
            refRegCount: 0,
            paramCount: 0,
          ),
        ],
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

      final entryFunc = module.functions[module.entryFuncId];
      expect(entryFunc.funcId, 0);
    });
  });

  group('ExceptionHandler', () {
    test('holds PC range and handler info', () {
      final handler = ExceptionHandler(
        startPC: 10,
        endPC: 20,
        handlerPC: 30,
        exceptionReg: 5,
        stackTraceReg: 6,
      );

      expect(handler.startPC, 10);
      expect(handler.endPC, 20);
      expect(handler.handlerPC, 30);
      expect(handler.exceptionReg, 5);
      expect(handler.stackTraceReg, 6);
    });
  });

  group('UpvalueDescriptor', () {
    test('local upvalue descriptor', () {
      final desc = UpvalueDescriptor(isLocal: true, index: 3);
      expect(desc.isLocal, isTrue);
      expect(desc.index, 3);
    });

    test('non-local upvalue descriptor', () {
      final desc = UpvalueDescriptor(isLocal: false, index: 0);
      expect(desc.isLocal, isFalse);
      expect(desc.index, 0);
    });
  });
}
