import '../bytecode/module.dart';
import '../compiler/type_template.dart';

/// Classifies which stack a variable or field lives on.
///
/// Enum order: ref(0) as default/fallback, then value types grouped by
/// intView (boolVal, intVal) and doubleView (doubleVal).
///
/// See: docs/design/02-object-model.md "StackKind 分类"
enum StackKind {
  /// String, object instances, closures, null, dynamic, num — RefStack.
  ref, // 0 — default/fallback

  /// bool (encoded as 0/1) — ValueStack intView.
  boolVal, // 1

  /// int — ValueStack intView.
  intVal, // 2

  /// double — ValueStack doubleView.
  doubleVal; // 3

  /// Whether this kind uses the value stack (all non-ref kinds).
  bool get isValue => this != ref;

  /// Compile-time constant for [ref.index], usable as default parameter values.
  static const int refDefault = 0;
}

/// Field layout descriptor — maps a field name index to its storage location.
///
/// See: docs/design/02-object-model.md "FieldLayout"
class FieldLayout {
  const FieldLayout({required this.offset, required this.kind});

  /// Offset within refFields or valueFields.
  final int offset;

  /// Which stack/storage this field uses.
  final StackKind kind;
}

/// Dart 3 class modifier flags stored as a bitfield.
///
/// These modifiers are compile-time restrictions enforced by the Dart CFE.
/// The dartic runtime stores them for debugging and future reflection support.
abstract final class ClassModifiers {
  static const int none = 0;
  static const int sealed = 1 << 0;
  static const int base = 1 << 1;
  static const int interface = 1 << 2;
  static const int final_ = 1 << 3;
  static const int mixin_ = 1 << 4;
  static const int abstract_ = 1 << 5;
}

/// Class metadata for interpreter-defined classes.
///
/// Maintains method table, field layout, and supertype information.
/// Phase 1 uses a simple Map for the method table; the dual-strategy
/// optimization (sorted list for <=8 methods) is deferred to Phase 3.
///
/// See: docs/design/02-object-model.md "类元数据"
class DarticClassInfo {
  DarticClassInfo({
    required this.classId,
    required this.name,
    required this.superClassId,
    required this.refFieldCount,
    required this.valueFieldCount,
    this.typeParamCount = 0,
    this.modifiers = ClassModifiers.none,
  });

  /// Unique class identifier.
  final int classId;

  /// Class name (for debugging and reflection).
  final String name;

  /// Parent class ID.
  final int superClassId;

  /// Number of reference-type fields.
  final int refFieldCount;

  /// Number of value-type fields (int/double/bool).
  final int valueFieldCount;

  /// Number of type parameters (e.g., `List<T>` -> 1, `Map<K,V>` -> 2).
  final int typeParamCount;

  /// Dart 3 class modifier flags (sealed / base / final / interface / mixin / abstract).
  /// See [ClassModifiers] for bit constants.
  final int modifiers;

  /// Method name index -> DarticFuncProto.
  /// Phase 1: simple Map. Phase 3: dual-strategy (sorted list / hash map).
  final Map<int, DarticFuncProto> methods = {};

  /// Field name index -> FieldLayout.
  final Map<int, FieldLayout> fields = {};

  /// Whether this class has the `sealed` modifier.
  bool get isSealed => modifiers & ClassModifiers.sealed != 0;

  /// Whether this class has the `base` modifier.
  bool get isBase => modifiers & ClassModifiers.base != 0;

  /// Whether this class has the `interface` modifier.
  bool get isInterface => modifiers & ClassModifiers.interface != 0;

  /// Whether this class has the `final` modifier.
  bool get isFinal => modifiers & ClassModifiers.final_ != 0;

  /// Whether this class has the `mixin` modifier (mixin class).
  bool get isMixinClass => modifiers & ClassModifiers.mixin_ != 0;

  /// Whether this class is abstract.
  bool get isAbstract => modifiers & ClassModifiers.abstract_ != 0;

  @override
  String toString() => 'ClassInfo(#$classId $name, '
      'super=$superClassId, '
      'refs=$refFieldCount, vals=$valueFieldCount)';

  /// Transitive closure of all supertype classIds (self + parents + interfaces).
  /// Used for O(1) `INSTANCEOF` checks.
  final Set<int> supertypeIds = {};

  /// SuperTypeMap: maps a supertype classId to the type argument mapping.
  ///
  /// For example, if `class MyList<T> extends List<T>`, the entry
  /// `{listClassId: [TypeParameterTemplate(index: 0)]}` allows the subtype
  /// checker to resolve `T` from the sub's ITA when comparing against
  /// `List<SomeType>`.
  ///
  /// Populated by the compiler from [SuperTypeEntry] data.
  final Map<int, List<TypeTemplate>> superTypeArgs = {};
}
