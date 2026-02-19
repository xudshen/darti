import 'package:dartic/src/compiler/type_converter.dart';
import 'package:dartic/src/compiler/type_template.dart';
import 'package:kernel/ast.dart' as ir;
import 'package:test/test.dart';

/// Convenience to avoid repeating the fileUri parameter for every Class.
final _testUri = Uri.parse('test:///test.dart');

ir.Class _makeClass(String name, {List<ir.TypeParameter>? typeParameters}) {
  return ir.Class(name: name, fileUri: _testUri, typeParameters: typeParameters);
}

void main() {
  group('dartTypeToTemplate — primitive types', () {
    test('VoidType → VoidTemplate', () {
      final result = dartTypeToTemplate(const ir.VoidType(), {});
      expect(result, equals(const VoidTemplate()));
    });

    test('DynamicType → DynamicTemplate', () {
      final result = dartTypeToTemplate(const ir.DynamicType(), {});
      expect(result, equals(const DynamicTemplate()));
    });

    test('NeverType (nonNullable) → NeverTemplate', () {
      final result = dartTypeToTemplate(
        const ir.NeverType.nonNullable(),
        {},
      );
      expect(result, equals(const NeverTemplate()));
    });

    test('NullType → NullableTemplate(NeverTemplate)', () {
      final result = dartTypeToTemplate(const ir.NullType(), {});
      expect(
        result,
        equals(NullableTemplate(inner: const NeverTemplate())),
      );
    });
  });

  group('dartTypeToTemplate — InterfaceType', () {
    late ir.Class intClass;
    late ir.Class stringClass;
    late ir.Class listClass;
    late ir.Class mapClass;
    late Map<ir.Class, int> classIdLookup;

    setUp(() {
      intClass = _makeClass('int');
      stringClass = _makeClass('String');
      listClass = _makeClass('List', typeParameters: [
        ir.TypeParameter('E', const ir.DynamicType()),
      ]);
      mapClass = _makeClass('Map', typeParameters: [
        ir.TypeParameter('K', const ir.DynamicType()),
        ir.TypeParameter('V', const ir.DynamicType()),
      ]);
      classIdLookup = {
        intClass: 0,
        stringClass: 1,
        listClass: 2,
        mapClass: 3,
      };
    });

    test('simple non-generic type (int)', () {
      final intType = ir.InterfaceType(
        intClass,
        ir.Nullability.nonNullable,
      );
      final result = dartTypeToTemplate(intType, classIdLookup);
      expect(
        result,
        equals(InterfaceTypeTemplate(classId: 0, typeArgs: [])),
      );
    });

    test('parameterized type (List<int>)', () {
      final intType = ir.InterfaceType(
        intClass,
        ir.Nullability.nonNullable,
      );
      final listOfInt = ir.InterfaceType(
        listClass,
        ir.Nullability.nonNullable,
        [intType],
      );
      final result = dartTypeToTemplate(listOfInt, classIdLookup);
      expect(
        result,
        equals(InterfaceTypeTemplate(
          classId: 2,
          typeArgs: [InterfaceTypeTemplate(classId: 0, typeArgs: [])],
        )),
      );
    });

    test('nested type (Map<String, List<int>>)', () {
      final intType = ir.InterfaceType(
        intClass,
        ir.Nullability.nonNullable,
      );
      final listOfInt = ir.InterfaceType(
        listClass,
        ir.Nullability.nonNullable,
        [intType],
      );
      final mapType = ir.InterfaceType(
        mapClass,
        ir.Nullability.nonNullable,
        [
          ir.InterfaceType(stringClass, ir.Nullability.nonNullable),
          listOfInt,
        ],
      );
      final result = dartTypeToTemplate(mapType, classIdLookup);
      expect(
        result,
        equals(InterfaceTypeTemplate(
          classId: 3,
          typeArgs: [
            InterfaceTypeTemplate(classId: 1, typeArgs: []),
            InterfaceTypeTemplate(
              classId: 2,
              typeArgs: [InterfaceTypeTemplate(classId: 0, typeArgs: [])],
            ),
          ],
        )),
      );
    });

    test('unknown class falls back to classId -1', () {
      final unknownClass = _makeClass('Unknown');
      final unknownType = ir.InterfaceType(
        unknownClass,
        ir.Nullability.nonNullable,
      );
      final result = dartTypeToTemplate(unknownType, classIdLookup);
      expect(
        result,
        equals(InterfaceTypeTemplate(classId: -1, typeArgs: [])),
      );
    });
  });

  group('dartTypeToTemplate — nullable types', () {
    late ir.Class intClass;
    late ir.Class listClass;
    late Map<ir.Class, int> classIdLookup;

    setUp(() {
      intClass = _makeClass('int');
      listClass = _makeClass('List', typeParameters: [
        ir.TypeParameter('E', const ir.DynamicType()),
      ]);
      classIdLookup = {intClass: 0, listClass: 1};
    });

    test('nullable InterfaceType (int?) → NullableTemplate(InterfaceType)',
        () {
      final nullableInt = ir.InterfaceType(
        intClass,
        ir.Nullability.nullable,
      );
      final result = dartTypeToTemplate(nullableInt, classIdLookup);
      expect(
        result,
        equals(NullableTemplate(
          inner: InterfaceTypeTemplate(classId: 0, typeArgs: []),
        )),
      );
    });

    test('nullable parameterized type (List<int>?)', () {
      final intType = ir.InterfaceType(
        intClass,
        ir.Nullability.nonNullable,
      );
      final nullableListOfInt = ir.InterfaceType(
        listClass,
        ir.Nullability.nullable,
        [intType],
      );
      final result = dartTypeToTemplate(nullableListOfInt, classIdLookup);
      expect(
        result,
        equals(NullableTemplate(
          inner: InterfaceTypeTemplate(
            classId: 1,
            typeArgs: [InterfaceTypeTemplate(classId: 0, typeArgs: [])],
          ),
        )),
      );
    });

    test('NeverType nullable → NullableTemplate(NeverTemplate)', () {
      const nullableNever = ir.NeverType.nullable();
      final result = dartTypeToTemplate(nullableNever, {});
      expect(
        result,
        equals(NullableTemplate(inner: const NeverTemplate())),
      );
    });
  });

  group('dartTypeToTemplate — FunctionType', () {
    late ir.Class intClass;
    late ir.Class stringClass;
    late Map<ir.Class, int> classIdLookup;

    setUp(() {
      intClass = _makeClass('int');
      stringClass = _makeClass('String');
      classIdLookup = {intClass: 0, stringClass: 1};
    });

    test('simple function type: int Function(String)', () {
      final fnType = ir.FunctionType(
        [ir.InterfaceType(stringClass, ir.Nullability.nonNullable)],
        ir.InterfaceType(intClass, ir.Nullability.nonNullable),
        ir.Nullability.nonNullable,
      );
      final result = dartTypeToTemplate(fnType, classIdLookup);
      expect(
        result,
        equals(FunctionTypeTemplate(
          returnType: InterfaceTypeTemplate(classId: 0, typeArgs: []),
          positionalParams: [
            InterfaceTypeTemplate(classId: 1, typeArgs: []),
          ],
          namedParams: [],
        )),
      );
    });

    test('function with named params: void Function(int, {String label})', () {
      final fnType = ir.FunctionType(
        [ir.InterfaceType(intClass, ir.Nullability.nonNullable)],
        const ir.VoidType(),
        ir.Nullability.nonNullable,
        namedParameters: [
          ir.NamedType(
            'label',
            ir.InterfaceType(stringClass, ir.Nullability.nonNullable),
          ),
        ],
      );
      final result = dartTypeToTemplate(fnType, classIdLookup);
      expect(result, isA<FunctionTypeTemplate>());
      final ft = result as FunctionTypeTemplate;
      expect(ft.returnType, equals(const VoidTemplate()));
      expect(ft.positionalParams.length, 1);
      expect(ft.namedParams.length, 1);
      expect(ft.namedParams[0].name, 'label');
      expect(
        ft.namedParams[0].type,
        equals(InterfaceTypeTemplate(classId: 1, typeArgs: [])),
      );
    });

    test('nullable function type → NullableTemplate(FunctionTypeTemplate)',
        () {
      final fnType = ir.FunctionType(
        [],
        const ir.VoidType(),
        ir.Nullability.nullable,
      );
      final result = dartTypeToTemplate(fnType, classIdLookup);
      expect(
        result,
        equals(NullableTemplate(
          inner: FunctionTypeTemplate(
            returnType: const VoidTemplate(),
            positionalParams: [],
            namedParams: [],
          ),
        )),
      );
    });

    test('function returning void with no params: void Function()', () {
      final fnType = ir.FunctionType(
        [],
        const ir.VoidType(),
        ir.Nullability.nonNullable,
      );
      final result = dartTypeToTemplate(fnType, classIdLookup);
      expect(
        result,
        equals(FunctionTypeTemplate(
          returnType: const VoidTemplate(),
          positionalParams: [],
          namedParams: [],
        )),
      );
    });
  });

  group('dartTypeToTemplate — TypeParameterType', () {
    test('class type parameter → TypeParameterTemplate(ITA)', () {
      final typeParam = ir.TypeParameter('T', const ir.DynamicType());
      final tpType = ir.TypeParameterType(
        typeParam,
        ir.Nullability.nonNullable,
      );
      final result = dartTypeToTemplate(
        tpType,
        {},
        enclosingClassTypeParams: [typeParam],
      );
      expect(
        result,
        equals(TypeParameterTemplate(index: 0, isFunctionTypeParam: false)),
      );
    });

    test('function type parameter → TypeParameterTemplate(FTA)', () {
      final typeParam = ir.TypeParameter('T', const ir.DynamicType());
      final tpType = ir.TypeParameterType(
        typeParam,
        ir.Nullability.nonNullable,
      );
      final result = dartTypeToTemplate(
        tpType,
        {},
        enclosingFunctionTypeParams: [typeParam],
      );
      expect(
        result,
        equals(TypeParameterTemplate(index: 0, isFunctionTypeParam: true)),
      );
    });

    test('second class type parameter → index 1', () {
      final t = ir.TypeParameter('T', const ir.DynamicType());
      final u = ir.TypeParameter('U', const ir.DynamicType());
      final uType = ir.TypeParameterType(u, ir.Nullability.nonNullable);
      final result = dartTypeToTemplate(
        uType,
        {},
        enclosingClassTypeParams: [t, u],
      );
      expect(
        result,
        equals(TypeParameterTemplate(index: 1, isFunctionTypeParam: false)),
      );
    });

    test('function type param takes precedence over class type param', () {
      // When the same TypeParameter is in both lists (shouldn't normally
      // happen), function scope (inner) takes precedence.
      final typeParam = ir.TypeParameter('T', const ir.DynamicType());
      final tpType = ir.TypeParameterType(
        typeParam,
        ir.Nullability.nonNullable,
      );
      final result = dartTypeToTemplate(
        tpType,
        {},
        enclosingClassTypeParams: [typeParam],
        enclosingFunctionTypeParams: [typeParam],
      );
      expect(
        result,
        equals(TypeParameterTemplate(index: 0, isFunctionTypeParam: true)),
      );
    });

    test('nullable type parameter → NullableTemplate(TypeParameterTemplate)',
        () {
      final typeParam = ir.TypeParameter('T', const ir.DynamicType());
      final tpType = ir.TypeParameterType(
        typeParam,
        ir.Nullability.nullable,
      );
      final result = dartTypeToTemplate(
        tpType,
        {},
        enclosingClassTypeParams: [typeParam],
      );
      expect(
        result,
        equals(NullableTemplate(
          inner: TypeParameterTemplate(index: 0, isFunctionTypeParam: false),
        )),
      );
    });

    test('unresolved type parameter falls back to DynamicTemplate', () {
      final typeParam = ir.TypeParameter('T', const ir.DynamicType());
      final tpType = ir.TypeParameterType(
        typeParam,
        ir.Nullability.nonNullable,
      );
      // Neither class nor function type params provided.
      final result = dartTypeToTemplate(tpType, {});
      expect(result, equals(const DynamicTemplate()));
    });
  });

  group('dartTypeToTemplate — IntersectionType', () {
    test('IntersectionType takes right (promoted type)', () {
      final intClass = _makeClass('int');
      final classIdLookup = {intClass: 0};
      final typeParam = ir.TypeParameter('T', const ir.DynamicType());
      final tpType = ir.TypeParameterType(
        typeParam,
        ir.Nullability.nonNullable,
      );
      final intType = ir.InterfaceType(
        intClass,
        ir.Nullability.nonNullable,
      );
      final intersection = ir.IntersectionType(tpType, intType);
      final result = dartTypeToTemplate(
        intersection,
        classIdLookup,
        enclosingClassTypeParams: [typeParam],
      );
      // Should use the right (promoted) type, which is `int`.
      expect(
        result,
        equals(InterfaceTypeTemplate(classId: 0, typeArgs: [])),
      );
    });
  });

  group('dartTypeToTemplate — StructuralParameterType', () {
    test('FunctionType structural parameter → TypeParameterTemplate', () {
      // Create a FunctionType with a type parameter, then reference it.
      final structParam = ir.StructuralParameter(
        'T',
        const ir.DynamicType(),
      );
      final spType = ir.StructuralParameterType(
        structParam,
        ir.Nullability.nonNullable,
      );

      // Build a FunctionType that uses this structural parameter in its
      // return type and parameter list.
      final fnType = ir.FunctionType(
        [spType],
        spType,
        ir.Nullability.nonNullable,
        typeParameters: [structParam],
      );

      final result = dartTypeToTemplate(fnType, {});
      expect(result, isA<FunctionTypeTemplate>());
      final ft = result as FunctionTypeTemplate;
      // The return type should reference the structural parameter at index 0
      // as a function type param (since it's a FunctionType's own param).
      expect(ft.returnType, isA<TypeParameterTemplate>());
      final retTp = ft.returnType as TypeParameterTemplate;
      expect(retTp.index, 0);
      expect(retTp.isFunctionTypeParam, true);
    });
  });

  group('dartTypeToTemplate — fallback', () {
    test('unsupported type falls back to DynamicTemplate', () {
      // InvalidType is a convenient way to test the fallback.
      final result = dartTypeToTemplate(const ir.InvalidType(), {});
      expect(result, equals(const DynamicTemplate()));
    });
  });

  group('dartTypeToTemplate — complex compositions', () {
    test('List<T> where T is class type param', () {
      final typeParam = ir.TypeParameter('T', const ir.DynamicType());
      final listClass = _makeClass('List', typeParameters: [
        ir.TypeParameter('E', const ir.DynamicType()),
      ]);
      final classIdLookup = {listClass: 5};

      final listOfT = ir.InterfaceType(
        listClass,
        ir.Nullability.nonNullable,
        [ir.TypeParameterType(typeParam, ir.Nullability.nonNullable)],
      );
      final result = dartTypeToTemplate(
        listOfT,
        classIdLookup,
        enclosingClassTypeParams: [typeParam],
      );
      expect(
        result,
        equals(InterfaceTypeTemplate(
          classId: 5,
          typeArgs: [
            TypeParameterTemplate(index: 0, isFunctionTypeParam: false),
          ],
        )),
      );
    });

    test('Map<String, List<T>>? with class type param T', () {
      final typeParam = ir.TypeParameter('T', const ir.DynamicType());
      final stringClass = _makeClass('String');
      final listClass = _makeClass('List', typeParameters: [
        ir.TypeParameter('E', const ir.DynamicType()),
      ]);
      final mapClass = _makeClass('Map', typeParameters: [
        ir.TypeParameter('K', const ir.DynamicType()),
        ir.TypeParameter('V', const ir.DynamicType()),
      ]);
      final classIdLookup = {stringClass: 1, listClass: 2, mapClass: 3};

      final listOfT = ir.InterfaceType(
        listClass,
        ir.Nullability.nonNullable,
        [ir.TypeParameterType(typeParam, ir.Nullability.nonNullable)],
      );
      final mapType = ir.InterfaceType(
        mapClass,
        ir.Nullability.nullable,
        [
          ir.InterfaceType(stringClass, ir.Nullability.nonNullable),
          listOfT,
        ],
      );
      final result = dartTypeToTemplate(
        mapType,
        classIdLookup,
        enclosingClassTypeParams: [typeParam],
      );
      expect(
        result,
        equals(NullableTemplate(
          inner: InterfaceTypeTemplate(
            classId: 3,
            typeArgs: [
              InterfaceTypeTemplate(classId: 1, typeArgs: []),
              InterfaceTypeTemplate(
                classId: 2,
                typeArgs: [
                  TypeParameterTemplate(index: 0, isFunctionTypeParam: false),
                ],
              ),
            ],
          ),
        )),
      );
    });
  });
}
