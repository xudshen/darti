import 'package:dartic/src/bytecode/module.dart';
import 'package:test/test.dart';

import '../helpers/module_helper.dart';

void main() {
  group('ICEntry constructor defaults', () {
    test('cachedClassId defaults to -1 (uncached)', () {
      final entry = ICEntry(methodNameIndex: 0);
      expect(entry.cachedClassId, -1);
    });

    test('cachedMethodOffset defaults to 0', () {
      final entry = ICEntry(methodNameIndex: 0);
      expect(entry.cachedMethodOffset, 0);
    });

    test('correctly stores methodNameIndex', () {
      final entry0 = ICEntry(methodNameIndex: 0);
      final entry42 = ICEntry(methodNameIndex: 42);
      final entry999 = ICEntry(methodNameIndex: 999);

      expect(entry0.methodNameIndex, 0);
      expect(entry42.methodNameIndex, 42);
      expect(entry999.methodNameIndex, 999);
    });
  });

  group('ICEntry serialization roundtrip', () {
    test('cachedClassId is -1 for all IC entries after roundtrip', () {
      final proto = buildFuncProto(
        icTable: [
          ICEntry(methodNameIndex: 5),
          ICEntry(methodNameIndex: 10),
          ICEntry(methodNameIndex: 15),
        ],
      );

      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      final icTable = result.functions[0].icTable;
      expect(icTable.length, 3);
      for (final entry in icTable) {
        expect(entry.cachedClassId, -1,
            reason: 'cachedClassId must be -1 (uncached) after deserialization');
      }
    });

    test('cachedMethodOffset is 0 after roundtrip', () {
      final proto = buildFuncProto(
        icTable: [
          ICEntry(methodNameIndex: 7),
          ICEntry(methodNameIndex: 21),
        ],
      );

      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      final icTable = result.functions[0].icTable;
      expect(icTable.length, 2);
      for (final entry in icTable) {
        expect(entry.cachedMethodOffset, 0,
            reason: 'cachedMethodOffset must be 0 after deserialization');
      }
    });

    test('multiple IC entries preserve methodNameIndex after roundtrip', () {
      final proto = buildFuncProto(
        icTable: [
          ICEntry(methodNameIndex: 0),
          ICEntry(methodNameIndex: 100),
          ICEntry(methodNameIndex: 255),
          ICEntry(methodNameIndex: 65535),
        ],
      );

      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      final icTable = result.functions[0].icTable;
      expect(icTable.length, 4);
      expect(icTable[0].methodNameIndex, 0);
      expect(icTable[1].methodNameIndex, 100);
      expect(icTable[2].methodNameIndex, 255);
      expect(icTable[3].methodNameIndex, 65535);
    });

    test(
        'dirty runtime cache (cachedClassId != -1) is reset to -1 after roundtrip',
        () {
      final icEntries = [
        ICEntry(methodNameIndex: 3),
        ICEntry(methodNameIndex: 8),
        ICEntry(methodNameIndex: 12),
      ];

      // Simulate runtime cache hits — these should NOT survive serialization.
      icEntries[0].cachedClassId = 42;
      icEntries[0].cachedMethodOffset = 200;
      icEntries[1].cachedClassId = 7;
      icEntries[1].cachedMethodOffset = 500;
      // icEntries[2] left at defaults to verify mixed state.

      final proto = buildFuncProto(icTable: icEntries);
      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      final icTable = result.functions[0].icTable;
      expect(icTable.length, 3);

      // All entries must have clean cache state after roundtrip.
      for (var i = 0; i < icTable.length; i++) {
        expect(icTable[i].cachedClassId, -1,
            reason: 'IC entry $i: cachedClassId must reset to -1');
        expect(icTable[i].cachedMethodOffset, 0,
            reason: 'IC entry $i: cachedMethodOffset must reset to 0');
      }

      // methodNameIndex must be preserved.
      expect(icTable[0].methodNameIndex, 3);
      expect(icTable[1].methodNameIndex, 8);
      expect(icTable[2].methodNameIndex, 12);
    });
  });

  group('DarticFuncProto with icTable and exceptionTable roundtrip', () {
    test('both icTable and exceptionTable survive roundtrip correctly', () {
      final proto = buildFuncProto(
        funcId: 0,
        name: 'complexFunc',
        icTable: [
          ICEntry(methodNameIndex: 1),
          ICEntry(methodNameIndex: 2),
        ],
        exceptionTable: [
          ExceptionHandler(
            startPC: 0,
            endPC: 50,
            handlerPC: 60,
            catchType: -1,
            valStackDP: 2,
            refStackDP: 1,
            exceptionReg: 3,
            stackTraceReg: 4,
          ),
          ExceptionHandler(
            startPC: 10,
            endPC: 30,
            handlerPC: 35,
            catchType: 5,
            valStackDP: 0,
            refStackDP: 0,
            exceptionReg: 6,
            stackTraceReg: 7,
          ),
        ],
      );

      final module = buildModuleFrom(functions: [proto]);
      final result = roundtripModule(module);

      final f = result.functions[0];

      // IC table checks.
      expect(f.icTable.length, 2);
      expect(f.icTable[0].methodNameIndex, 1);
      expect(f.icTable[0].cachedClassId, -1);
      expect(f.icTable[0].cachedMethodOffset, 0);
      expect(f.icTable[1].methodNameIndex, 2);
      expect(f.icTable[1].cachedClassId, -1);
      expect(f.icTable[1].cachedMethodOffset, 0);

      // Exception table checks.
      expect(f.exceptionTable.length, 2);
      expect(f.exceptionTable[0].startPC, 0);
      expect(f.exceptionTable[0].endPC, 50);
      expect(f.exceptionTable[0].handlerPC, 60);
      expect(f.exceptionTable[0].catchType, -1);
      expect(f.exceptionTable[0].valStackDP, 2);
      expect(f.exceptionTable[0].refStackDP, 1);
      expect(f.exceptionTable[0].exceptionReg, 3);
      expect(f.exceptionTable[0].stackTraceReg, 4);

      expect(f.exceptionTable[1].startPC, 10);
      expect(f.exceptionTable[1].endPC, 30);
      expect(f.exceptionTable[1].handlerPC, 35);
      expect(f.exceptionTable[1].catchType, 5);
      expect(f.exceptionTable[1].exceptionReg, 6);
      expect(f.exceptionTable[1].stackTraceReg, 7);
    });
  });
}
