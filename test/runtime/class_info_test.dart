import 'dart:typed_data';

import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/runtime/class_info.dart';
import 'package:test/test.dart';

void main() {
  group('DarticClassInfo', () {
    test('holds basic metadata', () {
      final info = DarticClassInfo(
        classId: 1,
        name: 'MyClass',
        superClassId: 0,
        refFieldCount: 2,
        valueFieldCount: 3,
      );

      expect(info.classId, 1);
      expect(info.name, 'MyClass');
      expect(info.superClassId, 0);
      expect(info.refFieldCount, 2);
      expect(info.valueFieldCount, 3);
    });

    test('typeParamCount defaults to 0', () {
      final info = DarticClassInfo(
        classId: 1,
        name: 'Simple',
        superClassId: 0,
        refFieldCount: 0,
        valueFieldCount: 0,
      );
      expect(info.typeParamCount, 0);
    });

    test('typeParamCount can be set', () {
      final info = DarticClassInfo(
        classId: 1,
        name: 'List',
        superClassId: 0,
        refFieldCount: 1,
        valueFieldCount: 0,
        typeParamCount: 1,
      );
      expect(info.typeParamCount, 1);
    });
  });

  group('MethodTable', () {
    test('can add and lookup methods', () {
      final info = DarticClassInfo(
        classId: 1,
        name: 'Foo',
        superClassId: 0,
        refFieldCount: 0,
        valueFieldCount: 0,
      );

      final proto = DarticFuncProto(
        funcId: 10,
        bytecode: Uint32List(1),
        valueRegCount: 0,
        refRegCount: 0,
        paramCount: 0,
      );

      info.methods[5] = proto; // method name index 5
      expect(info.methods[5]?.funcId, 10);
    });

    test('missing method returns null', () {
      final info = DarticClassInfo(
        classId: 1,
        name: 'Foo',
        superClassId: 0,
        refFieldCount: 0,
        valueFieldCount: 0,
      );

      expect(info.methods[99], isNull);
    });
  });

  group('FieldLayout', () {
    test('holds offset and kind', () {
      final layout = FieldLayout(offset: 2, kind: StackKind.ref);
      expect(layout.offset, 2);
      expect(layout.kind, StackKind.ref);
    });

    test('intVal kind', () {
      final layout = FieldLayout(offset: 0, kind: StackKind.intVal);
      expect(layout.kind, StackKind.intVal);
    });

    test('doubleVal kind', () {
      final layout = FieldLayout(offset: 1, kind: StackKind.doubleVal);
      expect(layout.kind, StackKind.doubleVal);
    });
  });

  group('StackKind', () {
    test('four values: ref, boolVal, intVal, doubleVal', () {
      expect(StackKind.values.length, 4);
      expect(StackKind.values, contains(StackKind.ref));
      expect(StackKind.values, contains(StackKind.boolVal));
      expect(StackKind.values, contains(StackKind.intVal));
      expect(StackKind.values, contains(StackKind.doubleVal));
    });

    test('enum indices: ref=0, boolVal=1, intVal=2, doubleVal=3', () {
      expect(StackKind.ref.index, 0);
      expect(StackKind.boolVal.index, 1);
      expect(StackKind.intVal.index, 2);
      expect(StackKind.doubleVal.index, 3);
    });

    test('boolVal.isValue returns true', () {
      expect(StackKind.boolVal.isValue, isTrue);
    });
  });

  group('supertypeIds', () {
    test('defaults to empty set', () {
      final info = DarticClassInfo(
        classId: 1,
        name: 'Base',
        superClassId: 0,
        refFieldCount: 0,
        valueFieldCount: 0,
      );
      expect(info.supertypeIds, isEmpty);
    });

    test('can be populated with self and ancestors', () {
      final info = DarticClassInfo(
        classId: 3,
        name: 'Child',
        superClassId: 2,
        refFieldCount: 0,
        valueFieldCount: 0,
      );
      // Transitive closure populated by module loader
      info.supertypeIds.addAll({3, 2, 1, 0});
      expect(info.supertypeIds.contains(3), isTrue); // self
      expect(info.supertypeIds.contains(2), isTrue); // parent
      expect(info.supertypeIds.contains(0), isTrue); // root
    });

    test('INSTANCEOF check via supertypeIds', () {
      final info = DarticClassInfo(
        classId: 3,
        name: 'Child',
        superClassId: 2,
        refFieldCount: 0,
        valueFieldCount: 0,
      );
      info.supertypeIds.addAll({3, 2, 1});

      expect(info.supertypeIds.contains(2), isTrue); // is parent
      expect(info.supertypeIds.contains(99), isFalse); // not related
    });
  });

  group('fields (FieldLayout map)', () {
    test('can register and retrieve field layout', () {
      final info = DarticClassInfo(
        classId: 1,
        name: 'Point',
        superClassId: 0,
        refFieldCount: 0,
        valueFieldCount: 2,
      );

      info.fields[10] = FieldLayout(offset: 0, kind: StackKind.intVal); // "x"
      info.fields[11] = FieldLayout(offset: 1, kind: StackKind.intVal); // "y"

      expect(info.fields[10]?.offset, 0);
      expect(info.fields[11]?.kind, StackKind.intVal);
    });
  });
}
