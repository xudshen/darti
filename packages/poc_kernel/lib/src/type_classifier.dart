import 'package:kernel/ast.dart';

enum StackKind { value, ref }

class TypeClassifySummary {
  final int valueCount;
  final int refCount;
  int get totalCount => valueCount + refCount;

  TypeClassifySummary({required this.valueCount, required this.refCount});

  @override
  String toString() =>
      'value: $valueCount, ref: $refCount, total: $totalCount '
      '(value ratio: ${(valueCount / totalCount * 100).toStringAsFixed(1)}%)';
}

/// Classifies Kernel DartTypes into [StackKind.value] or [StackKind.ref].
///
/// Works with --no-link-platform .dill files by using canonical name
/// comparison instead of CoreTypes identity checks.
class TypeClassifier {
  static const _valueTypeNames = {'int', 'double', 'bool'};

  StackKind classify(DartType type) {
    if (type is InterfaceType) {
      final name = _resolveClassName(type.classReference);
      if (_valueTypeNames.contains(name)) return StackKind.value;
    }
    return StackKind.ref;
  }

  String _resolveClassName(Reference ref) {
    final node = ref.node;
    if (node is Class) return node.name;
    return ref.canonicalName?.name ?? '';
  }

  TypeClassifySummary summarize(Component component) {
    int valueCount = 0;
    int refCount = 0;

    for (final lib in component.libraries) {
      if (lib.importUri.isScheme('dart')) continue;
      for (final proc in lib.procedures) {
        _countFunction(proc.function, (v, r) {
          valueCount += v;
          refCount += r;
        });
      }
      for (final cls in lib.classes) {
        for (final field in cls.fields) {
          if (classify(field.type) == StackKind.value) {
            valueCount++;
          } else {
            refCount++;
          }
        }
        for (final proc in cls.procedures) {
          _countFunction(proc.function, (v, r) {
            valueCount += v;
            refCount += r;
          });
        }
      }
    }

    return TypeClassifySummary(valueCount: valueCount, refCount: refCount);
  }

  void _countFunction(FunctionNode func, void Function(int v, int r) add) {
    int v = 0, r = 0;
    for (final param in func.positionalParameters) {
      if (classify(param.type) == StackKind.value) {
        v++;
      } else {
        r++;
      }
    }
    for (final param in func.namedParameters) {
      if (classify(param.type) == StackKind.value) {
        v++;
      } else {
        r++;
      }
    }
    if (classify(func.returnType) == StackKind.value) {
      v++;
    } else {
      r++;
    }
    add(v, r);
  }
}
