/// Registers `StringBuffer` host bindings for the CALL_HOST pipeline.
library;

import '../host_function_registry.dart';

/// Registers all `dart:core::StringBuffer` host function bindings.
abstract final class StringBufferBindings {
  static void register(HostFunctionRegistry registry) {
    // Constructor: StringBuffer([Object content = ''])
    registry.register('dart:core::StringBuffer::#1', (args) {
      if (args.isNotEmpty && args[0] != null) {
        return StringBuffer(args[0]!);
      }
      return StringBuffer();
    });

    // Getters
    registry.register('dart:core::StringBuffer::length#0', (args) {
      return (args[0] as StringBuffer).length;
    });
    registry.register('dart:core::StringBuffer::isEmpty#0', (args) {
      return (args[0] as StringBuffer).isEmpty;
    });
    registry.register('dart:core::StringBuffer::isNotEmpty#0', (args) {
      return (args[0] as StringBuffer).isNotEmpty;
    });

    // Methods
    registry.register('dart:core::StringBuffer::write#1', (args) {
      (args[0] as StringBuffer).write(args[1]);
      return null;
    });
    registry.register('dart:core::StringBuffer::writeln#1', (args) {
      if (args.length > 1 && args[1] != null) {
        (args[0] as StringBuffer).writeln(args[1]);
      } else {
        (args[0] as StringBuffer).writeln();
      }
      return null;
    });
    registry.register('dart:core::StringBuffer::writeAll#2', (args) {
      final sb = args[0] as StringBuffer;
      final objects = args[1] as Iterable;
      if (args.length > 2 && args[2] != null) {
        sb.writeAll(objects, args[2] as String);
      } else {
        sb.writeAll(objects);
      }
      return null;
    });
    registry.register('dart:core::StringBuffer::writeCharCode#1', (args) {
      (args[0] as StringBuffer).writeCharCode(args[1] as int);
      return null;
    });
    registry.register('dart:core::StringBuffer::clear#0', (args) {
      (args[0] as StringBuffer).clear();
      return null;
    });
    registry.register('dart:core::StringBuffer::toString#0', (args) {
      return (args[0] as StringBuffer).toString();
    });
  }
}
