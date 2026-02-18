import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/deserializer.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/format.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/bytecode/serializer.dart';
import 'package:test/test.dart';

import '../helpers/module_helper.dart';

void main() {
  group('empty module roundtrip', () {
    test('serialize and deserialize a module with zero functions', () {
      final module = buildModuleFrom();
      final result = roundtripModule(module);

      expect(result.functions, isEmpty);
      expect(result.entryFuncId, 0);
      expect(result.constantPool.refCount, 0);
      expect(result.constantPool.intCount, 0);
      expect(result.constantPool.doubleCount, 0);
      expect(result.constantPool.nameCount, 0);
    });
  });

  group('simple function roundtrip', () {
    test('module with one function preserves all fields', () {
      final bytecode = Uint32List.fromList([
        encodeABC(Op.addInt, 0, 1, 2),
        encodeAx(Op.halt, 0),
      ]);

      final proto = DarticFuncProto(
        funcId: 0,
        name: 'main',
        bytecode: bytecode,
        valueRegCount: 3,
        refRegCount: 1,
        paramCount: 2,
      );

      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      expect(result.functions.length, 1);
      final f = result.functions[0];
      expect(f.funcId, 0);
      expect(f.name, 'main');
      expect(f.bytecode, bytecode);
      expect(f.valueRegCount, 3);
      expect(f.refRegCount, 1);
      expect(f.paramCount, 2);
      expect(f.icTable, isEmpty);
      expect(f.exceptionTable, isEmpty);
      expect(f.upvalueDescriptors, isEmpty);
    });
  });

  group('multiple functions roundtrip', () {
    test('module with 2+ functions preserves all', () {
      final f0 = DarticFuncProto(
        funcId: 0,
        name: 'add',
        bytecode: Uint32List.fromList([
          encodeABC(Op.addInt, 0, 1, 2),
          encodeABC(Op.returnVal, 0, 0, 0),
        ]),
        valueRegCount: 3,
        refRegCount: 0,
        paramCount: 2,
      );

      final f1 = DarticFuncProto(
        funcId: 1,
        name: 'main',
        bytecode: Uint32List.fromList([
          encodeAx(Op.halt, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 2,
        paramCount: 0,
      );

      final module = buildModuleFrom(functions: [f0, f1], entryFuncId: 1);
      final result = roundtripModule(module);

      expect(result.functions.length, 2);
      expect(result.entryFuncId, 1);

      // Function 0
      expect(result.functions[0].funcId, 0);
      expect(result.functions[0].name, 'add');
      expect(result.functions[0].bytecode, f0.bytecode);
      expect(result.functions[0].valueRegCount, 3);
      expect(result.functions[0].refRegCount, 0);
      expect(result.functions[0].paramCount, 2);

      // Function 1
      expect(result.functions[1].funcId, 1);
      expect(result.functions[1].name, 'main');
      expect(result.functions[1].bytecode, f1.bytecode);
      expect(result.functions[1].valueRegCount, 1);
      expect(result.functions[1].refRegCount, 2);
      expect(result.functions[1].paramCount, 0);
    });
  });

  group('constant pool roundtrip', () {
    test('refs (strings), ints, doubles, names all preserved', () {
      final pool = ConstantPool();
      pool.addRef('hello');
      pool.addRef('world');
      pool.addRef(null);
      pool.addInt(42);
      pool.addInt(-1);
      pool.addInt(0x7FFFFFFFFFFFFFFF); // max int64
      pool.addDouble(3.14);
      pool.addDouble(-0.0);
      pool.addDouble(double.infinity);
      pool.addName('toString');
      pool.addName('hashCode');

      final module = buildModuleFrom(pool: pool);
      final result = roundtripModule(module);

      // refs
      expect(result.constantPool.refCount, 3);
      expect(result.constantPool.getRef(0), 'hello');
      expect(result.constantPool.getRef(1), 'world');
      expect(result.constantPool.getRef(2), isNull);

      // ints
      expect(result.constantPool.intCount, 3);
      expect(result.constantPool.getInt(0), 42);
      expect(result.constantPool.getInt(1), -1);
      expect(result.constantPool.getInt(2), 0x7FFFFFFFFFFFFFFF);

      // doubles
      expect(result.constantPool.doubleCount, 3);
      expect(result.constantPool.getDouble(0), 3.14);
      expect(result.constantPool.getDouble(1), isA<double>());
      expect(result.constantPool.getDouble(1).isNegative, isTrue);
      expect(result.constantPool.getDouble(2), double.infinity);

      // names
      expect(result.constantPool.nameCount, 2);
      expect(result.constantPool.getName(0), 'toString');
      expect(result.constantPool.getName(1), 'hashCode');
    });

    test('empty constant pool roundtrips correctly', () {
      final module = buildModuleFrom();
      final result = roundtripModule(module);

      expect(result.constantPool.refCount, 0);
      expect(result.constantPool.intCount, 0);
      expect(result.constantPool.doubleCount, 0);
      expect(result.constantPool.nameCount, 0);
    });

    test('unicode strings in refs and names are preserved', () {
      final pool = ConstantPool();
      pool.addRef('你好世界');
      pool.addRef('emoji: \u{1F600}');
      pool.addName('日本語メソッド');

      final module = buildModuleFrom(pool: pool);
      final result = roundtripModule(module);

      expect(result.constantPool.getRef(0), '你好世界');
      expect(result.constantPool.getRef(1), 'emoji: \u{1F600}');
      expect(result.constantPool.getName(0), '日本語メソッド');
    });
  });

  group('entry point preserved', () {
    test('entryFuncId survives roundtrip', () {
      final functions = List.generate(
        3,
        (i) => DarticFuncProto(
          funcId: i,
          name: 'f$i',
          bytecode: Uint32List.fromList([encodeAx(Op.halt, 0)]),
          valueRegCount: 0,
          refRegCount: 0,
          paramCount: 0,
        ),
      );

      final module = buildModuleFrom(functions: functions, entryFuncId: 2);
      final result = roundtripModule(module);

      expect(result.entryFuncId, 2);
    });
  });

  group('exception table roundtrip', () {
    test('ExceptionHandler entries preserve all 8 fields', () {
      final proto = DarticFuncProto(
        funcId: 0,
        name: 'tryFunc',
        bytecode: Uint32List.fromList([encodeAx(Op.halt, 0)]),
        valueRegCount: 4,
        refRegCount: 2,
        paramCount: 0,
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
          ExceptionHandler(
            startPC: 0,
            endPC: 100,
            handlerPC: 200,
            catchType: -1, // catch-all
            valStackDP: 0,
            refStackDP: 0,
            exceptionReg: 2,
            stackTraceReg: 3,
          ),
        ],
      );

      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      final handlers = result.functions[0].exceptionTable;
      expect(handlers.length, 2);

      expect(handlers[0].startPC, 10);
      expect(handlers[0].endPC, 20);
      expect(handlers[0].handlerPC, 30);
      expect(handlers[0].catchType, 5);
      expect(handlers[0].valStackDP, 3);
      expect(handlers[0].refStackDP, 1);
      expect(handlers[0].exceptionReg, 7);
      expect(handlers[0].stackTraceReg, 8);

      expect(handlers[1].startPC, 0);
      expect(handlers[1].endPC, 100);
      expect(handlers[1].handlerPC, 200);
      expect(handlers[1].catchType, -1);
      expect(handlers[1].valStackDP, 0);
      expect(handlers[1].refStackDP, 0);
      expect(handlers[1].exceptionReg, 2);
      expect(handlers[1].stackTraceReg, 3);
    });
  });

  group('IC table roundtrip', () {
    test('ICEntry methodNameIndex preserved, cachedClassId reset to -1', () {
      final proto = DarticFuncProto(
        funcId: 0,
        name: 'dispatch',
        bytecode: Uint32List.fromList([encodeAx(Op.halt, 0)]),
        valueRegCount: 0,
        refRegCount: 0,
        paramCount: 0,
        icTable: [
          ICEntry(methodNameIndex: 10),
          ICEntry(methodNameIndex: 42),
        ],
      );

      // Simulate runtime state that should NOT survive serialization.
      proto.icTable[0].cachedClassId = 99;
      proto.icTable[0].cachedMethodOffset = 200;

      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      final icTable = result.functions[0].icTable;
      expect(icTable.length, 2);

      expect(icTable[0].methodNameIndex, 10);
      expect(icTable[0].cachedClassId, -1); // reset
      expect(icTable[0].cachedMethodOffset, 0); // reset

      expect(icTable[1].methodNameIndex, 42);
      expect(icTable[1].cachedClassId, -1);
    });
  });

  group('upvalue descriptors roundtrip', () {
    test('isLocal and index preserved', () {
      final proto = DarticFuncProto(
        funcId: 0,
        name: 'closure',
        bytecode: Uint32List.fromList([encodeAx(Op.halt, 0)]),
        valueRegCount: 0,
        refRegCount: 1,
        paramCount: 0,
        upvalueDescriptors: [
          UpvalueDescriptor(isLocal: true, index: 3),
          UpvalueDescriptor(isLocal: false, index: 0),
          UpvalueDescriptor(isLocal: true, index: 7),
        ],
      );

      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      final upvals = result.functions[0].upvalueDescriptors;
      expect(upvals.length, 3);

      expect(upvals[0].isLocal, isTrue);
      expect(upvals[0].index, 3);
      expect(upvals[1].isLocal, isFalse);
      expect(upvals[1].index, 0);
      expect(upvals[2].isLocal, isTrue);
      expect(upvals[2].index, 7);
    });
  });

  group('checksum validation', () {
    test('corrupted data throws FormatException', () {
      final module = buildModuleFrom(
        functions: [
          DarticFuncProto(
            funcId: 0,
            name: 'f',
            bytecode: Uint32List.fromList([encodeAx(Op.halt, 0)]),
            valueRegCount: 1,
            refRegCount: 0,
            paramCount: 0,
          ),
        ],
      );

      final bytes = DarticSerializer().serialize(module);

      // Corrupt a byte in the payload (after 12-byte header).
      final corrupted = Uint8List.fromList(bytes);
      corrupted[14] ^= 0xFF;

      expect(
        () => DarticDeserializer().deserialize(corrupted),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('checksum'),
        )),
      );
    });
  });

  group('invalid magic detection', () {
    test('wrong magic throws FormatException', () {
      final module = buildModuleFrom();
      final bytes = DarticSerializer().serialize(module);

      // Overwrite magic with garbage.
      final bad = Uint8List.fromList(bytes);
      final bd = ByteData.sublistView(bad);
      bd.setUint32(0, 0xDEADBEEF, Endian.little);

      expect(
        () => DarticDeserializer().deserialize(bad),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('magic'),
        )),
      );
    });
  });

  group('version mismatch', () {
    test('wrong version throws FormatException', () {
      final module = buildModuleFrom();
      final bytes = DarticSerializer().serialize(module);

      // Overwrite version with a future version.
      final bad = Uint8List.fromList(bytes);
      final bd = ByteData.sublistView(bad);
      bd.setUint32(4, 999, Endian.little);

      expect(
        () => DarticDeserializer().deserialize(bad),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('version'),
        )),
      );
    });
  });

  group('serialized bytes structure', () {
    test('header contains magic, version, and valid checksum', () {
      final module = buildModuleFrom();
      final bytes = DarticSerializer().serialize(module);

      final bd = ByteData.sublistView(bytes);

      expect(bd.getUint32(0, Endian.little), DarbFormat.magic);
      expect(bd.getUint32(4, Endian.little), DarbFormat.version);

      // Checksum over payload.
      final payload = bytes.sublist(DarbFormat.headerSize);
      final expectedChecksum = crc32(payload);
      expect(bd.getUint32(8, Endian.little), expectedChecksum);
    });

    test('file too short throws FormatException', () {
      expect(
        () => DarticDeserializer().deserialize(Uint8List(8)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
