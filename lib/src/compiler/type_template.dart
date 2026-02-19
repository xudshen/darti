/// Compile-time type encoding for deferred generic instantiation.
///
/// TypeTemplates are stored in the constant pool and resolved at runtime
/// using ITA (Instance Type Arguments) and FTA (Function Type Arguments).
///
/// See: docs/design/06-generics.md "TypeTemplate"
library;

// ── Type tags for serialization ──

/// Discriminator tags for serialized TypeTemplate variants.
///
/// Each tag occupies one int in the serialized stream, followed by
/// variant-specific payload.
abstract final class _TypeTag {
  static const int voidType = 0;
  static const int dynamicType = 1;
  static const int neverType = 2;
  static const int interfaceType = 3;
  static const int functionType = 4;
  static const int typeParameter = 5;
  static const int nullableType = 6;
}

// ── Base class ──

/// A compile-time type descriptor that encodes Dart types for constant-pool
/// storage and deferred runtime instantiation.
///
/// At runtime, [resolveType] walks a TypeTemplate and substitutes
/// [TypeParameterTemplate] nodes using ITA/FTA from the current stack frame,
/// producing a canonical [DarticType] via the TypeRegistry.
sealed class TypeTemplate {
  const TypeTemplate();

  /// Serialize this template to a list of ints for constant pool storage.
  List<int> serialize();

  /// Deserialize a [TypeTemplate] from [data] starting at [offset].
  ///
  /// Returns a tuple of the deserialized template and the new offset
  /// (one past the last consumed element).
  static (TypeTemplate, int) deserialize(List<int> data, int offset) {
    final tag = data[offset++];
    return switch (tag) {
      _TypeTag.voidType => (const VoidTemplate(), offset),
      _TypeTag.dynamicType => (const DynamicTemplate(), offset),
      _TypeTag.neverType => (const NeverTemplate(), offset),
      _TypeTag.interfaceType => _deserializeInterface(data, offset),
      _TypeTag.functionType => _deserializeFunction(data, offset),
      _TypeTag.typeParameter => _deserializeTypeParameter(data, offset),
      _TypeTag.nullableType => _deserializeNullable(data, offset),
      _ => throw FormatException('Unknown TypeTemplate tag: $tag'),
    };
  }

  // ── Private deserialization helpers ──

  static (InterfaceTypeTemplate, int) _deserializeInterface(
    List<int> data,
    int offset,
  ) {
    final classId = data[offset++];
    final argCount = data[offset++];
    final typeArgs = <TypeTemplate>[];
    for (var i = 0; i < argCount; i++) {
      final (arg, newOffset) = deserialize(data, offset);
      typeArgs.add(arg);
      offset = newOffset;
    }
    return (
      InterfaceTypeTemplate(classId: classId, typeArgs: typeArgs),
      offset,
    );
  }

  static (FunctionTypeTemplate, int) _deserializeFunction(
    List<int> data,
    int offset,
  ) {
    // Positional params
    final posCount = data[offset++];
    final positionalParams = <TypeTemplate>[];
    for (var i = 0; i < posCount; i++) {
      final (param, newOffset) = deserialize(data, offset);
      positionalParams.add(param);
      offset = newOffset;
    }

    // Named params
    final namedCount = data[offset++];
    final namedParams = <({String name, TypeTemplate type})>[];
    for (var i = 0; i < namedCount; i++) {
      // Name is encoded as length + codeUnits
      final nameLen = data[offset++];
      final codeUnits = data.sublist(offset, offset + nameLen);
      offset += nameLen;
      final name = String.fromCharCodes(codeUnits);

      final (type, newOffset) = deserialize(data, offset);
      namedParams.add((name: name, type: type));
      offset = newOffset;
    }

    // Return type
    final (returnType, newOffset) = deserialize(data, offset);
    offset = newOffset;

    return (
      FunctionTypeTemplate(
        returnType: returnType,
        positionalParams: positionalParams,
        namedParams: namedParams,
      ),
      offset,
    );
  }

  static (TypeParameterTemplate, int) _deserializeTypeParameter(
    List<int> data,
    int offset,
  ) {
    final index = data[offset++];
    final isFunctionTypeParam = data[offset++] != 0;
    return (
      TypeParameterTemplate(
        index: index,
        isFunctionTypeParam: isFunctionTypeParam,
      ),
      offset,
    );
  }

  static (NullableTemplate, int) _deserializeNullable(
    List<int> data,
    int offset,
  ) {
    final (inner, newOffset) = deserialize(data, offset);
    return (NullableTemplate(inner: inner), newOffset);
  }
}

// ── Private helpers ──

/// Structural list equality for [TypeTemplate] lists.
bool _listEquals(List<TypeTemplate> a, List<TypeTemplate> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ── Concrete variants ──

/// Represents the `void` type.
class VoidTemplate extends TypeTemplate {
  const VoidTemplate();

  @override
  List<int> serialize() => [_TypeTag.voidType];

  @override
  bool operator ==(Object other) => other is VoidTemplate;

  @override
  int get hashCode => _TypeTag.voidType.hashCode;

  @override
  String toString() => 'VoidTemplate';
}

/// Represents the `dynamic` type.
class DynamicTemplate extends TypeTemplate {
  const DynamicTemplate();

  @override
  List<int> serialize() => [_TypeTag.dynamicType];

  @override
  bool operator ==(Object other) => other is DynamicTemplate;

  @override
  int get hashCode => _TypeTag.dynamicType.hashCode;

  @override
  String toString() => 'DynamicTemplate';
}

/// Represents the `Never` type.
class NeverTemplate extends TypeTemplate {
  const NeverTemplate();

  @override
  List<int> serialize() => [_TypeTag.neverType];

  @override
  bool operator ==(Object other) => other is NeverTemplate;

  @override
  int get hashCode => _TypeTag.neverType.hashCode;

  @override
  String toString() => 'NeverTemplate';
}

/// Represents a class or interface type, possibly with type arguments.
///
/// Examples:
/// - `int` : `InterfaceTypeTemplate(classId: 0, typeArgs: [])`
/// - `List<int>` : `InterfaceTypeTemplate(classId: 1, typeArgs: [InterfaceTypeTemplate(classId: 0)])`
class InterfaceTypeTemplate extends TypeTemplate {
  InterfaceTypeTemplate({
    required this.classId,
    required this.typeArgs,
  });

  /// The compile-time class identifier (matches [DarticClassInfo.classId]).
  final int classId;

  /// Type argument templates (empty for non-generic types).
  final List<TypeTemplate> typeArgs;

  @override
  List<int> serialize() {
    final result = <int>[_TypeTag.interfaceType, classId, typeArgs.length];
    for (final arg in typeArgs) {
      result.addAll(arg.serialize());
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is InterfaceTypeTemplate &&
      classId == other.classId &&
      _listEquals(typeArgs, other.typeArgs);

  @override
  int get hashCode => Object.hash(classId, Object.hashAll(typeArgs));

  @override
  String toString() => typeArgs.isEmpty
      ? 'InterfaceTypeTemplate(classId: $classId)'
      : 'InterfaceTypeTemplate(classId: $classId, typeArgs: $typeArgs)';
}

/// Represents a function type with return type, positional and named params.
///
/// Example: `void Function(int, {String label})`
class FunctionTypeTemplate extends TypeTemplate {
  FunctionTypeTemplate({
    required this.returnType,
    required this.positionalParams,
    required this.namedParams,
  });

  /// Return type of the function.
  final TypeTemplate returnType;

  /// Positional parameter types (required + optional).
  final List<TypeTemplate> positionalParams;

  /// Named parameter descriptors, each with a name and type.
  final List<({String name, TypeTemplate type})> namedParams;

  @override
  List<int> serialize() {
    final result = <int>[_TypeTag.functionType];

    // Positional params
    result.add(positionalParams.length);
    for (final param in positionalParams) {
      result.addAll(param.serialize());
    }

    // Named params
    result.add(namedParams.length);
    for (final named in namedParams) {
      // Encode name as length + codeUnits
      final codeUnits = named.name.codeUnits;
      result.add(codeUnits.length);
      result.addAll(codeUnits);
      result.addAll(named.type.serialize());
    }

    // Return type
    result.addAll(returnType.serialize());

    return result;
  }

  @override
  bool operator ==(Object other) {
    if (other is! FunctionTypeTemplate) return false;
    if (returnType != other.returnType) return false;
    if (!_listEquals(positionalParams, other.positionalParams)) return false;
    if (namedParams.length != other.namedParams.length) return false;
    for (var i = 0; i < namedParams.length; i++) {
      if (namedParams[i].name != other.namedParams[i].name ||
          namedParams[i].type != other.namedParams[i].type) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    var h = returnType.hashCode;
    h = Object.hash(h, Object.hashAll(positionalParams));
    for (final named in namedParams) {
      h = Object.hash(h, named.name, named.type);
    }
    return h;
  }

  @override
  String toString() => 'FunctionTypeTemplate('
      'ret: $returnType, '
      'pos: $positionalParams, '
      'named: [${namedParams.map((n) => '${n.name}: ${n.type}').join(', ')}])';
}

/// Represents a reference to a type parameter, resolved at runtime via
/// ITA (Instance Type Arguments) or FTA (Function Type Arguments).
///
/// The [index] is a positional index into the type argument vector.
/// [isFunctionTypeParam] selects between FTA (`true`) and ITA (`false`).
class TypeParameterTemplate extends TypeTemplate {
  TypeParameterTemplate({
    required this.index,
    required this.isFunctionTypeParam,
  });

  /// Zero-based index into the ITA or FTA vector.
  final int index;

  /// `true` = look up in FTA (function type args);
  /// `false` = look up in ITA (instance type args).
  final bool isFunctionTypeParam;

  @override
  List<int> serialize() => [
        _TypeTag.typeParameter,
        index,
        isFunctionTypeParam ? 1 : 0,
      ];

  @override
  bool operator ==(Object other) =>
      other is TypeParameterTemplate &&
      index == other.index &&
      isFunctionTypeParam == other.isFunctionTypeParam;

  @override
  int get hashCode => Object.hash(index, isFunctionTypeParam);

  @override
  String toString() => 'TypeParameterTemplate('
      'index: $index, '
      '${isFunctionTypeParam ? "FTA" : "ITA"})';
}

/// Wraps an inner [TypeTemplate] to represent its nullable variant (e.g. `int?`).
class NullableTemplate extends TypeTemplate {
  const NullableTemplate({required this.inner});

  /// The non-nullable base type.
  final TypeTemplate inner;

  @override
  List<int> serialize() {
    final result = <int>[_TypeTag.nullableType];
    result.addAll(inner.serialize());
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is NullableTemplate && inner == other.inner;

  @override
  int get hashCode => Object.hash(_TypeTag.nullableType, inner);

  @override
  String toString() => 'NullableTemplate($inner)';
}
