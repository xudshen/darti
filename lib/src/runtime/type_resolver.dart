/// Resolves compile-time [TypeTemplate] to runtime [DarticType].
///
/// The four-branch algorithm substitutes [TypeParameterTemplate] references
/// using ITA/FTA from the current stack frame, then interns the result via
/// [TypeRegistry].
///
/// See: docs/design/06-generics.md "resolveType 四分支"
library;

import '../compiler/type_template.dart';
import 'dartic_type.dart';

/// Resolves a [TypeTemplate] to a concrete [DarticType].
///
/// [ita] — Instance Type Arguments (class type params, from receiver).
/// [fta] — Function Type Arguments (method type params, from caller).
/// [registry] — TypeRegistry for interning the result.
///
/// Four branches:
/// 1. VoidTemplate / DynamicTemplate / NeverTemplate → pre-registered type
/// 2. InterfaceTypeTemplate with no type args → concrete type
/// 3. InterfaceTypeTemplate with type args → recurse then intern
/// 4. TypeParameterTemplate → look up in ITA or FTA by index
/// 5. NullableTemplate → resolve inner then intern with nullable
/// 6. FunctionTypeTemplate → resolve all nested types then intern
DarticType resolveType(
  TypeTemplate template,
  List<DarticType>? ita,
  List<DarticType>? fta,
  TypeRegistry registry,
) {
  return switch (template) {
    VoidTemplate() => registry.voidType,
    DynamicTemplate() => registry.dynamicType,
    NeverTemplate() => registry.neverType,
    TypeParameterTemplate() => _resolveTypeParam(template, ita, fta),
    NullableTemplate() => _resolveNullable(template, ita, fta, registry),
    InterfaceTypeTemplate() =>
      _resolveInterface(template, ita, fta, registry),
    FunctionTypeTemplate() =>
      _resolveFunction(template, ita, fta, registry),
  };
}

/// Resolves a type parameter reference from ITA or FTA.
DarticType _resolveTypeParam(
  TypeParameterTemplate template,
  List<DarticType>? ita,
  List<DarticType>? fta,
) {
  if (template.isFunctionTypeParam) {
    return fta![template.index];
  } else {
    return ita![template.index];
  }
}

/// Resolves a nullable type: resolve inner, then intern with nullable.
DarticType _resolveNullable(
  NullableTemplate template,
  List<DarticType>? ita,
  List<DarticType>? fta,
  TypeRegistry registry,
) {
  final inner = resolveType(template.inner, ita, fta, registry);
  return switch (inner) {
    DarticInterfaceType() => registry.intern(
        inner.classId,
        inner.typeArgs,
        nullability: Nullability.nullable,
      ),
    DarticFunctionType() => registry.internFunction(
        typeParamBounds: inner.typeParamBounds,
        requiredParamCount: inner.requiredParamCount,
        positionalParams: inner.positionalParams,
        namedParams: inner.namedParams,
        returnType: inner.returnType,
        nullability: Nullability.nullable,
      ),
  };
}

/// Resolves an interface type template.
///
/// If no type args, returns a simple interned type.
/// If type args present, recursively resolves each then interns.
DarticInterfaceType _resolveInterface(
  InterfaceTypeTemplate template,
  List<DarticType>? ita,
  List<DarticType>? fta,
  TypeRegistry registry,
) {
  if (template.typeArgs.isEmpty) {
    // Concrete type — O(1) intern lookup.
    return registry.intern(template.classId, const []);
  }
  // Generic type — resolve each type argument recursively.
  final resolvedArgs = <DarticType>[
    for (final argTemplate in template.typeArgs)
      resolveType(argTemplate, ita, fta, registry),
  ];
  return registry.intern(template.classId, resolvedArgs);
}

/// Resolves a function type template by resolving all nested types.
DarticFunctionType _resolveFunction(
  FunctionTypeTemplate template,
  List<DarticType>? ita,
  List<DarticType>? fta,
  TypeRegistry registry,
) {
  final resolvedBounds = <DarticType>[
    for (final b in template.typeParamBounds)
      resolveType(b, ita, fta, registry),
  ];
  final resolvedPos = <DarticType>[
    for (final p in template.positionalParams)
      resolveType(p, ita, fta, registry),
  ];
  final resolvedNamed = <({String name, DarticType type, bool isRequired})>[
    for (final n in template.namedParams)
      (
        name: n.name,
        type: resolveType(n.type, ita, fta, registry),
        isRequired: n.isRequired,
      ),
  ];
  final resolvedReturn = resolveType(template.returnType, ita, fta, registry);

  return registry.internFunction(
    typeParamBounds: resolvedBounds,
    requiredParamCount: template.requiredParamCount,
    positionalParams: resolvedPos,
    namedParams: resolvedNamed,
    returnType: resolvedReturn,
  );
}
