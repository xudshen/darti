/// Registers Invocation property bindings for noSuchMethod support.
///
/// When user code overrides noSuchMethod and accesses `invocation.memberName`,
/// `invocation.positionalArguments`, etc., the compiler emits CALL_HOST
/// (static type is Invocation). These bindings resolve those calls.
///
/// See: docs/design/04-interop.md
library;

import '../host_bindings.dart';

/// Registers all `dart:core::Invocation` property bindings.
abstract final class InvocationBindings {
  static void register(HostBindings bindings) {
    bindings.register('dart:core::Invocation::memberName#0', (args) {
      return (args[0] as Invocation).memberName;
    });

    bindings.register('dart:core::Invocation::positionalArguments#0', (args) {
      return (args[0] as Invocation).positionalArguments;
    });

    bindings.register('dart:core::Invocation::namedArguments#0', (args) {
      return (args[0] as Invocation).namedArguments;
    });

    bindings.register('dart:core::Invocation::typeArguments#0', (args) {
      return (args[0] as Invocation).typeArguments;
    });

    bindings.register('dart:core::Invocation::isMethod#0', (args) {
      return (args[0] as Invocation).isMethod;
    });

    bindings.register('dart:core::Invocation::isGetter#0', (args) {
      return (args[0] as Invocation).isGetter;
    });

    bindings.register('dart:core::Invocation::isSetter#0', (args) {
      return (args[0] as Invocation).isSetter;
    });

    bindings.register('dart:core::Invocation::isAccessor#0', (args) {
      return (args[0] as Invocation).isAccessor;
    });
  }
}
