/// Subtype checking for the dartic generics system.
///
/// Implements the core `isSubtypeOf` rules and `extractType` for runtime
/// type operations (INSTANCEOF / CAST).
///
/// See: docs/design/06-generics.md "isSubtypeOf"
library;

import 'class_info.dart';
import 'dartic_type.dart';
import 'object.dart';
import 'type_resolver.dart';

/// Checks subtype relationships between [DarticType] instances.
///
/// Core rules implemented:
///   1. identical fast path
///   2. top type (dynamic / void / Object?)
///   3. bottom type (Never)
///   4. nullable rejection (sub nullable + sup nonNullable → false)
///   5. Null type handling
///   6. nullable supertype decomposition
///   7. FutureOr as supertype
///   8. FutureOr as subtype
///   9. function type dispatch
///  10. Record type dispatch (stub → false)
///  11. SuperTypeMap lookup
///  12. type argument recursive check
class SubtypeChecker {
  SubtypeChecker({
    required this.classes,
    required this.registry,
  });

  /// Class info table indexed by classId.
  final List<DarticClassInfo> classes;

  /// Type registry for resolving SuperTypeMap entries.
  final TypeRegistry registry;

  /// Returns true if [sub] is a subtype of [sup].
  bool isSubtypeOf(DarticType sub, DarticType sup) {
    // Rule 1: identical fast path (interned types use pointer equality).
    if (identical(sub, sup)) return true;

    // Rule 2: top type — dynamic, void, Object? are supertypes of everything.
    if (_isTopType(sup)) return true;

    // Rule 3: bottom type — Never is subtype of everything.
    if (sub is DarticInterfaceType &&
        sub.classId == SpecialClassId.never &&
        sub.nullability == Nullability.nonNullable) {
      return true;
    }

    // Rule 4: nullable rejection (sub is nullable, sup is non-nullable → false).
    // Safe to apply before FutureOr rules because FutureOr normalization
    // converts FutureOr<T?> to FutureOr<T>? (nullable outer), so a
    // non-nullable FutureOr sup genuinely rejects nullable sub.
    if (sub.nullability == Nullability.nullable &&
        sup.nullability == Nullability.nonNullable) {
      return false;
    }

    // Rule 5: Null type (sub is Null / Never?)
    // Null is subtype of any nullable type (interface or function).
    if (sub is DarticInterfaceType &&
        sub.classId == SpecialClassId.never &&
        sub.nullability == Nullability.nullable) {
      return sup.nullability == Nullability.nullable;
    }

    // Rule 6: nullable supertype decomposition.
    // When sup is nullable, strip nullability from both sides and recurse.
    if (sup.nullability == Nullability.nullable) {
      final supBase = _stripNullable(sup);
      final subBase = (sub.nullability == Nullability.nullable)
          ? _stripNullable(sub)
          : sub;
      return isSubtypeOf(subBase, supBase);
    }

    // Rule 7: FutureOr as supertype.
    // sup is FutureOr<T>: sub <: Future<T> || sub <: T
    // Also: if sub is FutureOr<S>, check S <: T (handles FutureOr<S> <: FutureOr<T>).
    if (sup is DarticInterfaceType &&
        sup.classId == registry.futureOrClassId) {
      final t = sup.typeArgs[0];
      // Direct type argument check when sub is also FutureOr.
      if (sub is DarticInterfaceType &&
          sub.classId == registry.futureOrClassId) {
        final s = sub.typeArgs[0];
        if (isSubtypeOf(s, t)) return true;
      }
      // Construct Future<T> and check sub <: Future<T>.
      final futureT = registry.intern(registry.futureClassId, [t]);
      if (isSubtypeOf(sub, futureT)) return true;
      // Check sub <: T.
      if (isSubtypeOf(sub, t)) return true;
      return false;
    }

    // Rule 8: FutureOr as subtype.
    // sub is FutureOr<T>: Future<T> <: sup && T <: sup
    if (sub is DarticInterfaceType &&
        sub.classId == registry.futureOrClassId) {
      final t = sub.typeArgs[0];
      final futureT = registry.intern(registry.futureClassId, [t]);
      return isSubtypeOf(futureT, sup) && isSubtypeOf(t, sup);
    }

    // Rule 9: function type dispatch.
    if (sub is DarticFunctionType || sup is DarticFunctionType) {
      return _checkFunctionTypeSubtype(sub, sup);
    }

    // Rule 10: Record type dispatch (stub — Phase 6).
    // No RecordType class exists yet. Fall through to interface checks.

    // Rules 11-12: interface type subtype checking via supertypeIds + type args.
    if (sub is DarticInterfaceType && sup is DarticInterfaceType) {
      return _checkInterfaceSubtype(sub, sup);
    }

    return false;
  }

  /// Checks if [sup] is a top type (dynamic, void, or Object?).
  bool _isTopType(DarticType sup) {
    if (sup is! DarticInterfaceType) return false;
    if (sup.classId == SpecialClassId.dynamic_) return true;
    if (sup.classId == SpecialClassId.void_) return true;
    if (sup.classId == registry.objectType.classId &&
        sup.nullability == Nullability.nullable) {
      return true;
    }
    return false;
  }

  /// Strips nullability from a type, returning the non-nullable equivalent.
  DarticType _stripNullable(DarticType type) {
    if (type.nullability == Nullability.nonNullable) return type;
    return switch (type) {
      DarticInterfaceType() => registry.intern(type.classId, type.typeArgs),
      DarticFunctionType() => registry.internFunction(
          typeParamBounds: type.typeParamBounds,
          requiredParamCount: type.requiredParamCount,
          positionalParams: type.positionalParams,
          namedParams: type.namedParams,
          returnType: type.returnType,
        ),
    };
  }

  /// Rule 9: function type dispatch.
  bool _checkFunctionTypeSubtype(DarticType sub, DarticType sup) {
    if (sub is DarticFunctionType && sup is DarticFunctionType) {
      // Both are function types → detailed structural check.
      return _isFunctionSubtype(sub, sup);
    }
    if (sub is DarticFunctionType && sup is DarticInterfaceType) {
      // FunctionType <: Function class or Object → true.
      if (sup.classId == registry.functionClassId) return true;
      if (sup.classId == registry.objectType.classId) return true;
      // FunctionType <: other InterfaceType → false.
      return false;
    }
    if (sub is DarticInterfaceType && sup is DarticFunctionType) {
      // Non-FunctionType <: FunctionType → false.
      return false;
    }
    return false;
  }

  /// Structural function subtype check (9 rules).
  ///
  /// See: docs/design/06-generics.md "isFunctionSubtype"
  bool _isFunctionSubtype(DarticFunctionType sub, DarticFunctionType sup) {
    // Check 1: type parameter count must match.
    if (sub.typeParamBounds.length != sup.typeParamBounds.length) {
      return false;
    }

    // Check 2: type parameter bounds must be equivalent (mutual subtype).
    for (var i = 0; i < sub.typeParamBounds.length; i++) {
      if (!isSubtypeOf(sub.typeParamBounds[i], sup.typeParamBounds[i])) {
        return false;
      }
      if (!isSubtypeOf(sup.typeParamBounds[i], sub.typeParamBounds[i])) {
        return false;
      }
    }

    // Check 3: return type covariance.
    if (!isSubtypeOf(sub.returnType, sup.returnType)) return false;

    // Check 4: required positional param count.
    // sub.requiredParamCount <= sup.requiredParamCount
    // (sub can require fewer params than sup).
    if (sub.requiredParamCount > sup.requiredParamCount) return false;

    // Check 5: positional param total count.
    // sub must accept at least as many positional params as sup.
    if (sub.positionalParams.length < sup.positionalParams.length) return false;

    // Check 6: positional param types (contravariant).
    for (var i = 0; i < sup.positionalParams.length; i++) {
      if (!isSubtypeOf(sup.positionalParams[i], sub.positionalParams[i])) {
        return false;
      }
    }

    // Check 7-8-9: named parameter coverage, type contravariance, required flag.
    // sup's every named param must exist in sub.
    for (final supNamed in sup.namedParams) {
      // Find matching named param in sub (namedParams are sorted by name).
      final subNamed = _findNamedParam(sub.namedParams, supNamed.name);
      if (subNamed == null) {
        // Check 7: sup has a named param not in sub → false.
        return false;
      }
      // Check 8: named param type contravariance.
      if (!isSubtypeOf(supNamed.type, subNamed.type)) return false;
      // Check 9: required flag — if sub is required, sup must also be required.
      if (subNamed.isRequired && !supNamed.isRequired) return false;
    }

    return true;
  }

  /// Finds a named parameter by name in a sorted list of named params.
  ({String name, DarticType type, bool isRequired})? _findNamedParam(
    List<({String name, DarticType type, bool isRequired})> params,
    String name,
  ) {
    // Named params are sorted by name — could use binary search,
    // but linear scan is fine for typical param counts.
    for (final p in params) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// Checks interface type subtype using supertypeIds and type arg mapping.
  bool _checkInterfaceSubtype(
    DarticInterfaceType sub,
    DarticInterfaceType sup,
  ) {
    // Same classId → check type arguments directly.
    if (sub.classId == sup.classId) {
      return _typeArgsMatch(sub.typeArgs, sup.typeArgs);
    }

    // Check if sup's classId is in sub's supertype closure.
    final subClassId = sub.classId;
    if (subClassId < 0 || subClassId >= classes.length) return false;
    final classInfo = classes[subClassId];
    if (!classInfo.supertypeIds.contains(sup.classId)) return false;

    // Non-generic supertype check (sup has no type args).
    if (sup.typeArgs.isEmpty) return true;

    // Generic supertype check: resolve type arg mapping via SuperTypeMap.
    final mapping = classInfo.superTypeArgs[sup.classId];
    if (mapping == null) {
      // No mapping available — fall back to supertypeIds only.
      return sup.typeArgs.isEmpty;
    }

    // Arity mismatch: mapping should have same length as supertype's type args.
    if (mapping.length != sup.typeArgs.length) return false;

    // Resolve each mapping template using sub's typeArgs as ITA.
    for (var i = 0; i < mapping.length; i++) {
      final resolved = resolveType(mapping[i], sub.typeArgs, null, registry);
      if (!isSubtypeOf(resolved, sup.typeArgs[i])) return false;
    }
    return true;
  }

  /// Checks that type argument lists match (all pairs are subtypes).
  bool _typeArgsMatch(List<DarticType> subArgs, List<DarticType> supArgs) {
    if (subArgs.length != supArgs.length) return false;
    for (var i = 0; i < subArgs.length; i++) {
      if (!isSubtypeOf(subArgs[i], supArgs[i])) return false;
    }
    return true;
  }
}

/// Extracts a [DarticType] from a runtime value.
///
/// Used by INSTANCEOF/CAST to determine the runtime type of an object.
DarticType extractType(
  Object? value,
  TypeRegistry registry,
  List<DarticClassInfo> classes,
) {
  if (value == null) return registry.nullType;
  if (value is int) return registry.intType;
  if (value is double) return registry.doubleType;
  if (value is bool) return registry.boolType;
  if (value is String) return registry.stringType;
  if (value is DarticObject) {
    // If the object has a runtime type (set by ALLOC_GENERIC), use it.
    final rt = value.runtimeType_;
    if (rt != null) return rt;
    // Non-generic object: create a simple type from classId.
    return registry.intern(value.classId, const []);
  }
  return registry.dynamicType;
}
