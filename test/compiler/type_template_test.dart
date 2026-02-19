import 'package:dartic/src/compiler/type_template.dart';
import 'package:test/test.dart';

void main() {
  group('Primitive TypeTemplates', () {
    test('VoidTemplate creation and equality', () {
      final v1 = VoidTemplate();
      final v2 = VoidTemplate();
      expect(v1, equals(v2));
      expect(v1.hashCode, equals(v2.hashCode));
    });

    test('DynamicTemplate creation and equality', () {
      final d1 = DynamicTemplate();
      final d2 = DynamicTemplate();
      expect(d1, equals(d2));
      expect(d1.hashCode, equals(d2.hashCode));
    });

    test('NeverTemplate creation and equality', () {
      final n1 = NeverTemplate();
      final n2 = NeverTemplate();
      expect(n1, equals(n2));
      expect(n1.hashCode, equals(n2.hashCode));
    });

    test('distinct primitive types are not equal', () {
      expect(VoidTemplate(), isNot(equals(DynamicTemplate())));
      expect(DynamicTemplate(), isNot(equals(NeverTemplate())));
      expect(NeverTemplate(), isNot(equals(VoidTemplate())));
    });
  });

  group('InterfaceTypeTemplate', () {
    test('simple non-generic type (like int)', () {
      final t = InterfaceTypeTemplate(classId: 0, typeArgs: []);
      expect(t.classId, 0);
      expect(t.typeArgs, isEmpty);
    });

    test('single type argument (like List<int>)', () {
      final intType = InterfaceTypeTemplate(classId: 0, typeArgs: []);
      final listOfInt = InterfaceTypeTemplate(
        classId: 1,
        typeArgs: [intType],
      );
      expect(listOfInt.classId, 1);
      expect(listOfInt.typeArgs.length, 1);
      expect(listOfInt.typeArgs[0], equals(intType));
    });

    test('nested type arguments (like Map<String, List<int>>)', () {
      final intType = InterfaceTypeTemplate(classId: 0, typeArgs: []);
      final stringType = InterfaceTypeTemplate(classId: 2, typeArgs: []);
      final listOfInt = InterfaceTypeTemplate(
        classId: 1,
        typeArgs: [intType],
      );
      final mapType = InterfaceTypeTemplate(
        classId: 3,
        typeArgs: [stringType, listOfInt],
      );
      expect(mapType.classId, 3);
      expect(mapType.typeArgs.length, 2);
      expect(mapType.typeArgs[0], equals(stringType));
      expect(mapType.typeArgs[1], equals(listOfInt));
    });

    test('equality by classId and typeArgs', () {
      final a = InterfaceTypeTemplate(classId: 5, typeArgs: [
        InterfaceTypeTemplate(classId: 0, typeArgs: []),
      ]);
      final b = InterfaceTypeTemplate(classId: 5, typeArgs: [
        InterfaceTypeTemplate(classId: 0, typeArgs: []),
      ]);
      final c = InterfaceTypeTemplate(classId: 5, typeArgs: [
        InterfaceTypeTemplate(classId: 1, typeArgs: []),
      ]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('FunctionTypeTemplate', () {
    test('simple function type: void Function(int)', () {
      final intType = InterfaceTypeTemplate(classId: 0, typeArgs: []);
      final fnType = FunctionTypeTemplate(
        returnType: VoidTemplate(),
        positionalParams: [intType],
        namedParams: [],
      );
      expect(fnType.returnType, equals(VoidTemplate()));
      expect(fnType.positionalParams.length, 1);
      expect(fnType.positionalParams[0], equals(intType));
      expect(fnType.namedParams, isEmpty);
    });

    test('function with multiple params: int Function(String, double)', () {
      final intType = InterfaceTypeTemplate(classId: 0, typeArgs: []);
      final stringType = InterfaceTypeTemplate(classId: 1, typeArgs: []);
      final doubleType = InterfaceTypeTemplate(classId: 2, typeArgs: []);
      final fnType = FunctionTypeTemplate(
        returnType: intType,
        positionalParams: [stringType, doubleType],
        namedParams: [],
      );
      expect(fnType.returnType, equals(intType));
      expect(fnType.positionalParams.length, 2);
    });

    test('function with named params', () {
      final intType = InterfaceTypeTemplate(classId: 0, typeArgs: []);
      final stringType = InterfaceTypeTemplate(classId: 1, typeArgs: []);
      final fnType = FunctionTypeTemplate(
        returnType: VoidTemplate(),
        positionalParams: [intType],
        namedParams: [
          (name: 'label', type: stringType),
        ],
      );
      expect(fnType.namedParams.length, 1);
      expect(fnType.namedParams[0].name, 'label');
      expect(fnType.namedParams[0].type, equals(stringType));
    });

    test('equality', () {
      final a = FunctionTypeTemplate(
        returnType: VoidTemplate(),
        positionalParams: [InterfaceTypeTemplate(classId: 0, typeArgs: [])],
        namedParams: [],
      );
      final b = FunctionTypeTemplate(
        returnType: VoidTemplate(),
        positionalParams: [InterfaceTypeTemplate(classId: 0, typeArgs: [])],
        namedParams: [],
      );
      final c = FunctionTypeTemplate(
        returnType: DynamicTemplate(),
        positionalParams: [InterfaceTypeTemplate(classId: 0, typeArgs: [])],
        namedParams: [],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('TypeParameterTemplate', () {
    test('create with index for ITA (class type param)', () {
      final tp = TypeParameterTemplate(index: 0, isFunctionTypeParam: false);
      expect(tp.index, 0);
      expect(tp.isFunctionTypeParam, false);
    });

    test('create with index for FTA (function type param)', () {
      final tp = TypeParameterTemplate(index: 1, isFunctionTypeParam: true);
      expect(tp.index, 1);
      expect(tp.isFunctionTypeParam, true);
    });

    test('equality', () {
      final a = TypeParameterTemplate(index: 0, isFunctionTypeParam: false);
      final b = TypeParameterTemplate(index: 0, isFunctionTypeParam: false);
      final c = TypeParameterTemplate(index: 0, isFunctionTypeParam: true);
      final d = TypeParameterTemplate(index: 1, isFunctionTypeParam: false);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });
  });

  group('NullableTemplate', () {
    test('wraps inner template (like int?)', () {
      final intType = InterfaceTypeTemplate(classId: 0, typeArgs: []);
      final nullable = NullableTemplate(inner: intType);
      expect(nullable.inner, equals(intType));
    });

    test('wraps complex inner template (like List<int>?)', () {
      final listOfInt = InterfaceTypeTemplate(
        classId: 1,
        typeArgs: [InterfaceTypeTemplate(classId: 0, typeArgs: [])],
      );
      final nullable = NullableTemplate(inner: listOfInt);
      expect(nullable.inner, equals(listOfInt));
    });

    test('equality', () {
      final a = NullableTemplate(
        inner: InterfaceTypeTemplate(classId: 0, typeArgs: []),
      );
      final b = NullableTemplate(
        inner: InterfaceTypeTemplate(classId: 0, typeArgs: []),
      );
      final c = NullableTemplate(
        inner: InterfaceTypeTemplate(classId: 1, typeArgs: []),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('NullableTemplate is not equal to inner template', () {
      final intType = InterfaceTypeTemplate(classId: 0, typeArgs: []);
      final nullable = NullableTemplate(inner: intType);
      expect(nullable, isNot(equals(intType)));
    });
  });

  group('Serialization roundtrip', () {
    test('VoidTemplate roundtrip', () {
      final original = VoidTemplate();
      final bytes = original.serialize();
      final (deserialized, offset) = TypeTemplate.deserialize(bytes, 0);
      expect(deserialized, equals(original));
      expect(offset, bytes.length);
    });

    test('DynamicTemplate roundtrip', () {
      final original = DynamicTemplate();
      final bytes = original.serialize();
      final (deserialized, offset) = TypeTemplate.deserialize(bytes, 0);
      expect(deserialized, equals(original));
      expect(offset, bytes.length);
    });

    test('NeverTemplate roundtrip', () {
      final original = NeverTemplate();
      final bytes = original.serialize();
      final (deserialized, offset) = TypeTemplate.deserialize(bytes, 0);
      expect(deserialized, equals(original));
      expect(offset, bytes.length);
    });

    test('simple InterfaceTypeTemplate roundtrip', () {
      final original = InterfaceTypeTemplate(classId: 42, typeArgs: []);
      final bytes = original.serialize();
      final (deserialized, offset) = TypeTemplate.deserialize(bytes, 0);
      expect(deserialized, equals(original));
      expect(offset, bytes.length);
    });

    test('InterfaceTypeTemplate with type args roundtrip', () {
      final original = InterfaceTypeTemplate(
        classId: 5,
        typeArgs: [
          InterfaceTypeTemplate(classId: 0, typeArgs: []),
          InterfaceTypeTemplate(classId: 1, typeArgs: []),
        ],
      );
      final bytes = original.serialize();
      final (deserialized, offset) = TypeTemplate.deserialize(bytes, 0);
      expect(deserialized, equals(original));
      expect(offset, bytes.length);
    });

    test('nested InterfaceTypeTemplate roundtrip (Map<String, List<int>>)',
        () {
      final original = InterfaceTypeTemplate(
        classId: 3,
        typeArgs: [
          InterfaceTypeTemplate(classId: 2, typeArgs: []), // String
          InterfaceTypeTemplate(
            classId: 1,
            typeArgs: [
              InterfaceTypeTemplate(classId: 0, typeArgs: []), // int
            ],
          ), // List<int>
        ],
      );
      final bytes = original.serialize();
      final (deserialized, offset) = TypeTemplate.deserialize(bytes, 0);
      expect(deserialized, equals(original));
      expect(offset, bytes.length);
    });

    test('FunctionTypeTemplate roundtrip', () {
      final original = FunctionTypeTemplate(
        returnType: VoidTemplate(),
        positionalParams: [
          InterfaceTypeTemplate(classId: 0, typeArgs: []),
        ],
        namedParams: [
          (name: 'label', type: InterfaceTypeTemplate(classId: 1, typeArgs: [])),
        ],
      );
      final bytes = original.serialize();
      final (deserialized, offset) = TypeTemplate.deserialize(bytes, 0);
      expect(deserialized, equals(original));
      expect(offset, bytes.length);
    });

    test('TypeParameterTemplate roundtrip (ITA)', () {
      final original =
          TypeParameterTemplate(index: 2, isFunctionTypeParam: false);
      final bytes = original.serialize();
      final (deserialized, offset) = TypeTemplate.deserialize(bytes, 0);
      expect(deserialized, equals(original));
      expect(offset, bytes.length);
    });

    test('TypeParameterTemplate roundtrip (FTA)', () {
      final original =
          TypeParameterTemplate(index: 0, isFunctionTypeParam: true);
      final bytes = original.serialize();
      final (deserialized, offset) = TypeTemplate.deserialize(bytes, 0);
      expect(deserialized, equals(original));
      expect(offset, bytes.length);
    });

    test('NullableTemplate roundtrip', () {
      final original = NullableTemplate(
        inner: InterfaceTypeTemplate(classId: 7, typeArgs: []),
      );
      final bytes = original.serialize();
      final (deserialized, offset) = TypeTemplate.deserialize(bytes, 0);
      expect(deserialized, equals(original));
      expect(offset, bytes.length);
    });

    test('complex nested structure roundtrip', () {
      // Simulates: Map<String, List<T>>? where T is a type parameter
      final original = NullableTemplate(
        inner: InterfaceTypeTemplate(
          classId: 3, // Map
          typeArgs: [
            InterfaceTypeTemplate(classId: 2, typeArgs: []), // String
            InterfaceTypeTemplate(
              classId: 1, // List
              typeArgs: [
                TypeParameterTemplate(index: 0, isFunctionTypeParam: false),
              ],
            ),
          ],
        ),
      );
      final bytes = original.serialize();
      final (deserialized, offset) = TypeTemplate.deserialize(bytes, 0);
      expect(deserialized, equals(original));
      expect(offset, bytes.length);
    });

    test('deserialization at non-zero offset', () {
      final template1 = VoidTemplate();
      final template2 = InterfaceTypeTemplate(classId: 10, typeArgs: [
        InterfaceTypeTemplate(classId: 0, typeArgs: []),
      ]);
      final bytes1 = template1.serialize();
      final bytes2 = template2.serialize();
      final combined = [...bytes1, ...bytes2];

      final (d1, offset1) = TypeTemplate.deserialize(combined, 0);
      expect(d1, equals(template1));
      expect(offset1, bytes1.length);

      final (d2, offset2) = TypeTemplate.deserialize(combined, offset1);
      expect(d2, equals(template2));
      expect(offset2, combined.length);
    });
  });
}
