/// Generic proxy wrapping an interpreter [DarticObject] for host VM use.
///
/// Provides identity-correct `==`, `hashCode`, and a basic `toString()`.
/// Property/method forwarding via DarticRuntime.invokeMethod is deferred
/// to Task 5.3.4 (HostDispatcher dynamic dispatch).
///
/// See: docs/design/04-interop.md "DarticProxy"
library;

import '../runtime/object.dart';

/// Wraps a [DarticObject] so the host VM can hold and compare it.
///
/// Two proxies wrapping the same [DarticObject] are `==` and share the
/// same [hashCode] (identity-based). This ensures that interpreter objects
/// passed through the VM boundary maintain consistent identity.
class DarticProxy {
  DarticProxy(this.target);

  /// The interpreter-side object being proxied.
  final DarticObject target;

  @override
  bool operator ==(Object other) =>
      other is DarticProxy && identical(target, other.target);

  @override
  int get hashCode => identityHashCode(target);

  @override
  String toString() => 'DarticProxy(classId=${target.classId})';
}
