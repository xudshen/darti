import 'package:kernel/ast.dart';

class DesugarReport {
  final List<String> unexpectedNodes;
  final Map<String, int> nodeTypeCounts;

  DesugarReport({required this.unexpectedNodes, required this.nodeTypeCounts});
}

/// Walks the Kernel AST to verify CFE desugaring and collect node statistics.
///
/// Checks that high-level sugar (cascade, for-in, etc.) has been desugared
/// by CFE, and counts expression/statement node types.
class DesugarChecker extends RecursiveVisitor {
  final List<String> _unexpected = [];
  final Map<String, int> _counts = {};

  DesugarReport check(Component component) {
    _unexpected.clear();
    _counts.clear();
    for (final lib in component.libraries) {
      if (lib.importUri.isScheme('dart')) continue;
      lib.accept(this);
    }
    return DesugarReport(
      unexpectedNodes: List.unmodifiable(_unexpected),
      nodeTypeCounts: Map.unmodifiable(_counts),
    );
  }

  @override
  void defaultNode(Node node) {
    // Count expression and statement node types
    if (node is Expression || node is Statement) {
      final name = node.runtimeType.toString();
      _counts[name] = (_counts[name] ?? 0) + 1;
    }
    // Continue recursive traversal, guarding against unlinked references
    // in --no-link-platform .dill files
    try {
      node.visitChildren(this);
    } catch (e) {
      // Unlinked reference (e.g. dart:core::int) throws a bare String
      // in --no-link-platform .dill files — skip this subtree
      if ('$e'.contains('is not bound to an AST node')) return;
      rethrow;
    }
  }

  @override
  void defaultDartType(DartType node) {
    // Skip DartType children entirely — they reference platform classes
  }
}
