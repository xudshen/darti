/// Concrete [Invocation] for noSuchMethod dispatch in the dartic runtime.
///
/// Provides three named constructors for the three invocation kinds:
/// - [DarticInvocation.method] — method call
/// - [DarticInvocation.getter] — getter access
/// - [DarticInvocation.setter] — setter assignment
library;

class DarticInvocation implements Invocation {
  DarticInvocation.method(
    this.memberName,
    List<Object?> positionalArgs, [
    Map<Symbol, Object?>? namedArgs,
    List<Type>? typeArgs,
  ])  : positionalArguments = List.unmodifiable(positionalArgs),
        namedArguments = Map.unmodifiable(namedArgs ?? const {}),
        typeArguments = List.unmodifiable(typeArgs ?? const []),
        isMethod = true,
        isGetter = false,
        isSetter = false;

  DarticInvocation.getter(this.memberName)
      : positionalArguments = const [],
        namedArguments = const {},
        typeArguments = const [],
        isMethod = false,
        isGetter = true,
        isSetter = false;

  DarticInvocation.setter(this.memberName, Object? value)
      : positionalArguments = List.unmodifiable([value]),
        namedArguments = const {},
        typeArguments = const [],
        isMethod = false,
        isGetter = false,
        isSetter = true;

  @override
  final Symbol memberName;

  @override
  final List<Object?> positionalArguments;

  @override
  final Map<Symbol, Object?> namedArguments;

  @override
  final List<Type> typeArguments;

  @override
  final bool isMethod;

  @override
  final bool isGetter;

  @override
  final bool isSetter;

  @override
  bool get isAccessor => isGetter || isSetter;
}
