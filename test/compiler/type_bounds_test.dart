import 'package:dartic/src/compiler/type_converter.dart';
import 'package:dartic/src/compiler/type_template.dart';
import 'package:kernel/ast.dart' as ir;
import 'package:test/test.dart';

/// Convenience to avoid repeating the fileUri parameter for every Class.
final _testUri = Uri.parse('test:///test.dart');

ir.Class _makeClass(String name, {List<ir.TypeParameter>? typeParameters}) {
  return ir.Class(
      name: name, fileUri: _testUri, typeParameters: typeParameters);
}

void main() {
  // ── Type parameter bounds extraction ──

  group('extractTypeParamBounds', () {
    test('class with no type parameters has empty bounds list', () {
      final cls = _makeClass('Animal');
      final classIdLookup = <ir.Class, int>{cls: 0};
      final bounds = extractTypeParamBounds(cls, classIdLookup);
      expect(bounds, isEmpty);
    });

    test('class with single unbounded type parameter has DynamicTemplate bound',
        () {
      // class Box<T> { T value; }
      // Default bound in Kernel is DynamicType.
      final typeParam = ir.TypeParameter('T', const ir.DynamicType());
      final cls = _makeClass('Box', typeParameters: [typeParam]);
      final classIdLookup = <ir.Class, int>{cls: 0};
      final bounds = extractTypeParamBounds(cls, classIdLookup);

      expect(bounds.length, 1);
      expect(bounds[0].name, 'T');
      expect(bounds[0].bound, equals(const DynamicTemplate()));
    });

    test('class with bounded type parameter extracts bound correctly', () {
      // class NumBox<T extends num> { T value; }
      final numClass = _makeClass('num');
      final classIdLookup = <ir.Class, int>{numClass: 1};

      final numType =
          ir.InterfaceType(numClass, ir.Nullability.nonNullable);
      final typeParam = ir.TypeParameter('T', numType);
      final cls = _makeClass('NumBox', typeParameters: [typeParam]);
      classIdLookup[cls] = 2;

      final bounds = extractTypeParamBounds(cls, classIdLookup);

      expect(bounds.length, 1);
      expect(bounds[0].name, 'T');
      expect(
        bounds[0].bound,
        equals(InterfaceTypeTemplate(classId: 1, typeArgs: [])),
      );
    });

    test('class with multiple type parameters extracts all bounds', () {
      // class Pair<A, B> { A first; B second; }
      final typeParamA = ir.TypeParameter('A', const ir.DynamicType());
      final typeParamB = ir.TypeParameter('B', const ir.DynamicType());
      final cls = _makeClass('Pair', typeParameters: [typeParamA, typeParamB]);
      final classIdLookup = <ir.Class, int>{cls: 0};
      final bounds = extractTypeParamBounds(cls, classIdLookup);

      expect(bounds.length, 2);
      expect(bounds[0].name, 'A');
      expect(bounds[0].bound, equals(const DynamicTemplate()));
      expect(bounds[1].name, 'B');
      expect(bounds[1].bound, equals(const DynamicTemplate()));
    });

    test('self-referencing bound encodes correctly', () {
      // class Comparable<T extends Comparable<T>> {}
      // In Kernel, the bound references the class's own type parameter.
      final comparableClass = _makeClass('Comparable');
      final classIdLookup = <ir.Class, int>{comparableClass: 0};

      // Create type parameter T with bound Comparable<T>.
      // We need the TypeParameter to exist first, then set its bound.
      final typeParamT = ir.TypeParameter('T', const ir.DynamicType());
      // The bound is Comparable<T> where T references typeParamT.
      final boundType = ir.InterfaceType(
        comparableClass,
        ir.Nullability.nonNullable,
        [ir.TypeParameterType(typeParamT, ir.Nullability.nonNullable)],
      );
      typeParamT.bound = boundType;

      // Recreate the class with the proper type parameter.
      final cls = _makeClass('Comparable', typeParameters: [typeParamT]);
      classIdLookup[cls] = 0;

      final bounds = extractTypeParamBounds(cls, classIdLookup);

      expect(bounds.length, 1);
      expect(bounds[0].name, 'T');
      // Bound should be Comparable<TypeParameterTemplate(index:0, ITA)>
      expect(
        bounds[0].bound,
        equals(InterfaceTypeTemplate(
          classId: 0,
          typeArgs: [
            TypeParameterTemplate(index: 0, isFunctionTypeParam: false),
          ],
        )),
      );
    });

    test('unnamed type parameter gets generated name', () {
      // Kernel allows null name on TypeParameter (unusual but possible)
      final typeParam = ir.TypeParameter(null, const ir.DynamicType());
      final cls = _makeClass('Anon', typeParameters: [typeParam]);
      final classIdLookup = <ir.Class, int>{cls: 0};
      final bounds = extractTypeParamBounds(cls, classIdLookup);

      expect(bounds.length, 1);
      expect(bounds[0].name, 'T0'); // Fallback name
    });
  });

  // ── SuperTypeMap skeleton ──

  group('buildSuperTypeEntries', () {
    test('simple non-generic inheritance', () {
      // class Animal {}
      // class Dog extends Animal {}
      final animalClass = _makeClass('Animal');
      final dogClass = _makeClass('Dog');
      dogClass.supertype =
          ir.Supertype(animalClass, const []);

      final classIdLookup = <ir.Class, int>{
        animalClass: 0,
        dogClass: 1,
      };

      final entries = buildSuperTypeEntries(dogClass, classIdLookup);

      expect(entries.length, 1);
      expect(entries[0].subClassId, 1);
      expect(entries[0].superClassId, 0);
      expect(entries[0].typeArgMapping, isEmpty);
    });

    test('generic inheritance with concrete type args', () {
      // class Box<T> {}
      // class IntBox extends Box<int> {}
      final intClass = _makeClass('int');
      final typeParamT = ir.TypeParameter('T', const ir.DynamicType());
      final boxClass = _makeClass('Box', typeParameters: [typeParamT]);
      final intBoxClass = _makeClass('IntBox');

      // IntBox extends Box<int>
      intBoxClass.supertype = ir.Supertype(
        boxClass,
        [ir.InterfaceType(intClass, ir.Nullability.nonNullable)],
      );

      final classIdLookup = <ir.Class, int>{
        intClass: 0,
        boxClass: 1,
        intBoxClass: 2,
      };

      final entries = buildSuperTypeEntries(intBoxClass, classIdLookup);

      expect(entries.length, 1);
      expect(entries[0].subClassId, 2);
      expect(entries[0].superClassId, 1);
      expect(entries[0].typeArgMapping.length, 1);
      // T in Box maps to concrete int
      expect(
        entries[0].typeArgMapping[0],
        equals(InterfaceTypeTemplate(classId: 0, typeArgs: [])),
      );
    });

    test('parameterized subclass passes type parameter through', () {
      // class Base<E> {}
      // class MyList<E> extends Base<E> {}
      final typeParamEBase = ir.TypeParameter('E', const ir.DynamicType());
      final baseClass = _makeClass('Base', typeParameters: [typeParamEBase]);
      final typeParamESub = ir.TypeParameter('E', const ir.DynamicType());
      final myListClass = _makeClass('MyList', typeParameters: [typeParamESub]);

      // MyList<E> extends Base<E>
      myListClass.supertype = ir.Supertype(
        baseClass,
        [ir.TypeParameterType(typeParamESub, ir.Nullability.nonNullable)],
      );

      final classIdLookup = <ir.Class, int>{
        baseClass: 0,
        myListClass: 1,
      };

      final entries = buildSuperTypeEntries(myListClass, classIdLookup);

      expect(entries.length, 1);
      expect(entries[0].subClassId, 1);
      expect(entries[0].superClassId, 0);
      expect(entries[0].typeArgMapping.length, 1);
      // E in MyList identity-maps to E in Base via TypeParameterTemplate
      expect(
        entries[0].typeArgMapping[0],
        equals(TypeParameterTemplate(index: 0, isFunctionTypeParam: false)),
      );
    });

    test('class with implemented interface', () {
      // class Printable {}  (acts as interface)
      // class Dog implements Printable {}
      final printableClass = _makeClass('Printable');
      final dogClass = _makeClass('Dog');

      // Dog has no custom supertype (defaults to Object, which we ignore
      // since Object is a platform class with no classId).
      // Dog implements Printable
      dogClass.implementedTypes.add(
        ir.Supertype(printableClass, const []),
      );

      final classIdLookup = <ir.Class, int>{
        printableClass: 0,
        dogClass: 1,
      };

      final entries = buildSuperTypeEntries(dogClass, classIdLookup);

      // Should have entry for Printable interface (supertype ignored since
      // Object is not in classIdLookup).
      final printableEntries =
          entries.where((e) => e.superClassId == 0).toList();
      expect(printableEntries.length, 1);
      expect(printableEntries[0].subClassId, 1);
      expect(printableEntries[0].typeArgMapping, isEmpty);
    });

    test('generic interface implementation with concrete type args', () {
      // class Comparable<T> {}
      // class MyInt implements Comparable<MyInt> {}
      final typeParamT = ir.TypeParameter('T', const ir.DynamicType());
      final comparableClass =
          _makeClass('Comparable', typeParameters: [typeParamT]);
      final myIntClass = _makeClass('MyInt');

      myIntClass.implementedTypes.add(
        ir.Supertype(
          comparableClass,
          [ir.InterfaceType(myIntClass, ir.Nullability.nonNullable)],
        ),
      );

      final classIdLookup = <ir.Class, int>{
        comparableClass: 0,
        myIntClass: 1,
      };

      final entries = buildSuperTypeEntries(myIntClass, classIdLookup);

      final compEntries =
          entries.where((e) => e.superClassId == 0).toList();
      expect(compEntries.length, 1);
      expect(compEntries[0].subClassId, 1);
      expect(compEntries[0].typeArgMapping.length, 1);
      // T in Comparable maps to MyInt
      expect(
        compEntries[0].typeArgMapping[0],
        equals(InterfaceTypeTemplate(classId: 1, typeArgs: [])),
      );
    });

    test('multiple inheritance paths (extends + implements)', () {
      // class Animal {}
      // class Printable<T> {}
      // class Dog extends Animal implements Printable<Dog> {}
      final animalClass = _makeClass('Animal');
      final typeParamT = ir.TypeParameter('T', const ir.DynamicType());
      final printableClass =
          _makeClass('Printable', typeParameters: [typeParamT]);
      final dogClass = _makeClass('Dog');

      dogClass.supertype = ir.Supertype(animalClass, const []);
      dogClass.implementedTypes.add(
        ir.Supertype(
          printableClass,
          [ir.InterfaceType(dogClass, ir.Nullability.nonNullable)],
        ),
      );

      final classIdLookup = <ir.Class, int>{
        animalClass: 0,
        printableClass: 1,
        dogClass: 2,
      };

      final entries = buildSuperTypeEntries(dogClass, classIdLookup);

      // Should have entries for both Animal (super) and Printable (interface)
      expect(entries.length, 2);
      final animalEntry = entries.firstWhere((e) => e.superClassId == 0);
      final printableEntry = entries.firstWhere((e) => e.superClassId == 1);
      expect(animalEntry.typeArgMapping, isEmpty);
      expect(printableEntry.typeArgMapping.length, 1);
      expect(
        printableEntry.typeArgMapping[0],
        equals(InterfaceTypeTemplate(classId: 2, typeArgs: [])),
      );
    });

    test('class with no supertype (no known superclass) has empty entries', () {
      // A class whose supertype is Object (platform class, not in classIdLookup)
      final cls = _makeClass('Standalone');
      final classIdLookup = <ir.Class, int>{cls: 0};

      final entries = buildSuperTypeEntries(cls, classIdLookup);

      expect(entries, isEmpty);
    });
  });

  // ── SuperTypeEntry equality ──

  group('SuperTypeEntry equality and hashCode', () {
    test('equal entries', () {
      final a = SuperTypeEntry(
        subClassId: 1,
        superClassId: 0,
        typeArgMapping: [InterfaceTypeTemplate(classId: 2, typeArgs: [])],
      );
      final b = SuperTypeEntry(
        subClassId: 1,
        superClassId: 0,
        typeArgMapping: [InterfaceTypeTemplate(classId: 2, typeArgs: [])],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different subClassId', () {
      final a = SuperTypeEntry(
        subClassId: 1,
        superClassId: 0,
        typeArgMapping: [],
      );
      final b = SuperTypeEntry(
        subClassId: 2,
        superClassId: 0,
        typeArgMapping: [],
      );
      expect(a, isNot(equals(b)));
    });

    test('different superClassId', () {
      final a = SuperTypeEntry(
        subClassId: 1,
        superClassId: 0,
        typeArgMapping: [],
      );
      final b = SuperTypeEntry(
        subClassId: 1,
        superClassId: 3,
        typeArgMapping: [],
      );
      expect(a, isNot(equals(b)));
    });

    test('different typeArgMapping', () {
      final a = SuperTypeEntry(
        subClassId: 1,
        superClassId: 0,
        typeArgMapping: [InterfaceTypeTemplate(classId: 2, typeArgs: [])],
      );
      final b = SuperTypeEntry(
        subClassId: 1,
        superClassId: 0,
        typeArgMapping: [InterfaceTypeTemplate(classId: 3, typeArgs: [])],
      );
      expect(a, isNot(equals(b)));
    });

    test('empty vs non-empty typeArgMapping', () {
      final a = SuperTypeEntry(
        subClassId: 1,
        superClassId: 0,
        typeArgMapping: [],
      );
      final b = SuperTypeEntry(
        subClassId: 1,
        superClassId: 0,
        typeArgMapping: [const DynamicTemplate()],
      );
      expect(a, isNot(equals(b)));
    });
  });
}
