import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  late HostFunctionRegistry registry;

  setUp(() {
    registry = HostFunctionRegistry();
    CoreBindings.registerAll(registry);
  });

  // ── Helper to invoke a binding by symbolic name ──
  Object? invoke(String name, List<Object?> args) {
    final id = registry.lookupByName(name);
    if (id == -1) fail('Binding not found: $name');
    return registry.invoke(id, args);
  }

  // ════════════════════════════════════════════════════════════════════
  // StringBuffer
  // ════════════════════════════════════════════════════════════════════

  group('StringBufferBindings registration', () {
    test('StringBuffer bindings are registered', () {
      expect(registry.lookupByName('dart:core::StringBuffer::#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::StringBuffer::length#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::StringBuffer::isEmpty#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::StringBuffer::isNotEmpty#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::StringBuffer::write#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::StringBuffer::writeln#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::StringBuffer::writeAll#2'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::StringBuffer::writeCharCode#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::StringBuffer::clear#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::StringBuffer::toString#0'),
          isNot(equals(-1)));
    });
  });

  group('StringBufferBindings invoke', () {
    test('StringBuffer constructor with no args', () {
      final sb = invoke('dart:core::StringBuffer::#1', [null]);
      expect(sb, isA<StringBuffer>());
      expect((sb as StringBuffer).isEmpty, true);
    });

    test('StringBuffer constructor with initial content', () {
      final sb = invoke('dart:core::StringBuffer::#1', ['hello']);
      expect(sb, isA<StringBuffer>());
      expect((sb as StringBuffer).toString(), 'hello');
    });

    test('StringBuffer.length', () {
      final sb = StringBuffer('abc');
      expect(invoke('dart:core::StringBuffer::length#0', [sb]), 3);
    });

    test('StringBuffer.isEmpty / isNotEmpty', () {
      final empty = StringBuffer();
      final nonEmpty = StringBuffer('x');
      expect(invoke('dart:core::StringBuffer::isEmpty#0', [empty]), true);
      expect(invoke('dart:core::StringBuffer::isEmpty#0', [nonEmpty]), false);
      expect(invoke('dart:core::StringBuffer::isNotEmpty#0', [empty]), false);
      expect(invoke('dart:core::StringBuffer::isNotEmpty#0', [nonEmpty]), true);
    });

    test('StringBuffer.write', () {
      final sb = StringBuffer();
      invoke('dart:core::StringBuffer::write#1', [sb, 'hello']);
      expect(sb.toString(), 'hello');
    });

    test('StringBuffer.writeln with argument', () {
      final sb = StringBuffer();
      invoke('dart:core::StringBuffer::writeln#1', [sb, 'line1']);
      expect(sb.toString(), 'line1\n');
    });

    test('StringBuffer.writeln with no argument', () {
      final sb = StringBuffer('text');
      invoke('dart:core::StringBuffer::writeln#1', [sb, null]);
      expect(sb.toString(), 'text\n');
    });

    test('StringBuffer.writeAll without separator', () {
      final sb = StringBuffer();
      invoke('dart:core::StringBuffer::writeAll#2', [
        sb,
        ['a', 'b', 'c'],
        null
      ]);
      expect(sb.toString(), 'abc');
    });

    test('StringBuffer.writeAll with separator', () {
      final sb = StringBuffer();
      invoke('dart:core::StringBuffer::writeAll#2', [
        sb,
        ['a', 'b', 'c'],
        ', '
      ]);
      expect(sb.toString(), 'a, b, c');
    });

    test('StringBuffer.writeCharCode', () {
      final sb = StringBuffer();
      invoke('dart:core::StringBuffer::writeCharCode#1', [sb, 65]); // 'A'
      expect(sb.toString(), 'A');
    });

    test('StringBuffer.clear', () {
      final sb = StringBuffer('hello');
      invoke('dart:core::StringBuffer::clear#0', [sb]);
      expect(sb.isEmpty, true);
    });

    test('StringBuffer.toString', () {
      final sb = StringBuffer('result');
      expect(invoke('dart:core::StringBuffer::toString#0', [sb]), 'result');
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Runes
  // ════════════════════════════════════════════════════════════════════

  group('RunesBindings registration', () {
    test('Runes bindings are registered', () {
      expect(registry.lookupByName('dart:core::Runes::#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Runes::length#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Runes::first#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Runes::last#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Runes::isEmpty#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Runes::isNotEmpty#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Runes::hashCode#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Runes::iterator#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Runes::elementAt#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Runes::contains#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Runes::toList#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Runes::toString#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Runes::single#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Runes::join#1'),
          isNot(equals(-1)));
    });
  });

  group('RunesBindings invoke', () {
    test('Runes constructor', () {
      final runes = invoke('dart:core::Runes::#1', ['hello']);
      expect(runes, isA<Runes>());
    });

    test('Runes.length', () {
      final runes = 'hello'.runes;
      expect(invoke('dart:core::Runes::length#0', [runes]), 5);
    });

    test('Runes.first', () {
      final runes = 'hello'.runes;
      expect(invoke('dart:core::Runes::first#0', [runes]), 104); // 'h'
    });

    test('Runes.last', () {
      final runes = 'hello'.runes;
      expect(invoke('dart:core::Runes::last#0', [runes]), 111); // 'o'
    });

    test('Runes.isEmpty / isNotEmpty', () {
      final emptyRunes = ''.runes;
      final nonEmptyRunes = 'a'.runes;
      expect(invoke('dart:core::Runes::isEmpty#0', [emptyRunes]), true);
      expect(invoke('dart:core::Runes::isEmpty#0', [nonEmptyRunes]), false);
      expect(invoke('dart:core::Runes::isNotEmpty#0', [emptyRunes]), false);
      expect(invoke('dart:core::Runes::isNotEmpty#0', [nonEmptyRunes]), true);
    });

    test('Runes.hashCode', () {
      final runes = 'test'.runes;
      expect(invoke('dart:core::Runes::hashCode#0', [runes]), runes.hashCode);
    });

    test('Runes.iterator', () {
      final runes = 'ab'.runes;
      final iter = invoke('dart:core::Runes::iterator#0', [runes]);
      expect(iter, isA<RuneIterator>());
    });

    test('Runes.elementAt', () {
      final runes = 'hello'.runes;
      expect(invoke('dart:core::Runes::elementAt#1', [runes, 0]), 104); // 'h'
      expect(invoke('dart:core::Runes::elementAt#1', [runes, 4]), 111); // 'o'
    });

    test('Runes.contains', () {
      final runes = 'hello'.runes;
      expect(invoke('dart:core::Runes::contains#1', [runes, 104]), true); // 'h'
      expect(invoke('dart:core::Runes::contains#1', [runes, 0]), false);
    });

    test('Runes.toList without growable arg', () {
      final runes = 'abc'.runes;
      final list = invoke('dart:core::Runes::toList#1', [runes]);
      expect(list, [97, 98, 99]);
    });

    test('Runes.toList with growable false', () {
      final runes = 'ab'.runes;
      final list = invoke('dart:core::Runes::toList#1', [runes, false]);
      expect(list, [97, 98]);
    });

    test('Runes.toString', () {
      final runes = 'hello'.runes;
      final result = invoke('dart:core::Runes::toString#0', [runes]);
      expect(result, isA<String>());
    });

    test('Runes.single', () {
      final runes = 'x'.runes;
      expect(invoke('dart:core::Runes::single#0', [runes]), 120); // 'x'
    });

    test('Runes.join with separator', () {
      final runes = 'ab'.runes;
      expect(invoke('dart:core::Runes::join#1', [runes, '-']), '97-98');
    });

    test('Runes.join without separator', () {
      final runes = 'ab'.runes;
      expect(invoke('dart:core::Runes::join#1', [runes]), '9798');
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // RuneIterator
  // ════════════════════════════════════════════════════════════════════

  group('RuneIterator registration', () {
    test('RuneIterator bindings are registered', () {
      expect(registry.lookupByName('dart:core::RuneIterator::current#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::RuneIterator::currentSize#0'),
          isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::RuneIterator::currentAsString#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::RuneIterator::rawIndex#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::RuneIterator::moveNext#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::RuneIterator::reset#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::RuneIterator::movePrevious#0'),
          isNot(equals(-1)));
    });
  });

  group('RuneIterator invoke', () {
    test('RuneIterator.moveNext and current', () {
      final iter = 'hi'.runes.iterator;
      expect(invoke('dart:core::RuneIterator::moveNext#0', [iter]), true);
      expect(invoke('dart:core::RuneIterator::current#0', [iter]), 104); // 'h'
      expect(invoke('dart:core::RuneIterator::moveNext#0', [iter]), true);
      expect(invoke('dart:core::RuneIterator::current#0', [iter]), 105); // 'i'
      expect(invoke('dart:core::RuneIterator::moveNext#0', [iter]), false);
    });

    test('RuneIterator.currentSize', () {
      final iter = 'A'.runes.iterator;
      invoke('dart:core::RuneIterator::moveNext#0', [iter]);
      expect(invoke('dart:core::RuneIterator::currentSize#0', [iter]), 1);
    });

    test('RuneIterator.currentAsString', () {
      final iter = 'X'.runes.iterator;
      invoke('dart:core::RuneIterator::moveNext#0', [iter]);
      expect(
          invoke('dart:core::RuneIterator::currentAsString#0', [iter]), 'X');
    });

    test('RuneIterator.rawIndex', () {
      final iter = 'abc'.runes.iterator;
      invoke('dart:core::RuneIterator::moveNext#0', [iter]);
      expect(invoke('dart:core::RuneIterator::rawIndex#0', [iter]), 0);
      invoke('dart:core::RuneIterator::moveNext#0', [iter]);
      expect(invoke('dart:core::RuneIterator::rawIndex#0', [iter]), 1);
    });

    test('RuneIterator.reset with no argument', () {
      final iter = 'ab'.runes.iterator;
      invoke('dart:core::RuneIterator::moveNext#0', [iter]);
      invoke('dart:core::RuneIterator::moveNext#0', [iter]);
      invoke('dart:core::RuneIterator::reset#1', [iter, null]);
      expect(invoke('dart:core::RuneIterator::moveNext#0', [iter]), true);
      expect(invoke('dart:core::RuneIterator::current#0', [iter]), 97); // 'a'
    });

    test('RuneIterator.reset with index argument', () {
      final iter = 'abc'.runes.iterator;
      invoke('dart:core::RuneIterator::reset#1', [iter, 1]);
      expect(invoke('dart:core::RuneIterator::moveNext#0', [iter]), true);
      expect(invoke('dart:core::RuneIterator::current#0', [iter]), 98); // 'b'
    });

    test('RuneIterator.movePrevious', () {
      final iter = 'abc'.runes.iterator;
      invoke('dart:core::RuneIterator::moveNext#0', [iter]);
      invoke('dart:core::RuneIterator::moveNext#0', [iter]);
      // Now at 'b', move back to 'a'
      expect(invoke('dart:core::RuneIterator::movePrevious#0', [iter]), true);
      expect(invoke('dart:core::RuneIterator::current#0', [iter]), 97); // 'a'
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // E2e tests (compile and run Dart source)
  // ════════════════════════════════════════════════════════════════════

  group('StringBuffer e2e', () {
    test('StringBuffer multi-write then toString', () async {
      final result = await compileAndRunWithHost('''
String main() {
  var sb = StringBuffer();
  sb.write('hello');
  sb.write(' ');
  sb.write('world');
  return sb.toString();
}
''');
      expect(result, 'hello world');
    });

    test('StringBuffer constructor with initial content', () async {
      final result = await compileAndRunWithHost('''
String main() {
  var sb = StringBuffer('start');
  sb.write('_end');
  return sb.toString();
}
''');
      expect(result, 'start_end');
    });

    test('StringBuffer.length getter', () async {
      final result = await compileAndRunWithHost('''
int main() {
  var sb = StringBuffer('abc');
  return sb.length;
}
''');
      expect(result, 3);
    });

    test('StringBuffer.isEmpty and isNotEmpty', () async {
      final result = await compileAndRunWithHost('''
bool main() {
  var sb = StringBuffer();
  bool wasEmpty = sb.isEmpty;
  sb.write('x');
  return wasEmpty && sb.isNotEmpty;
}
''');
      expect(result, true);
    });

    test('StringBuffer.writeCharCode', () async {
      final result = await compileAndRunWithHost('''
String main() {
  var sb = StringBuffer();
  sb.writeCharCode(65); // 'A'
  sb.writeCharCode(66); // 'B'
  return sb.toString();
}
''');
      expect(result, 'AB');
    });

    test('StringBuffer.clear', () async {
      final result = await compileAndRunWithHost('''
String main() {
  var sb = StringBuffer('hello');
  sb.clear();
  sb.write('new');
  return sb.toString();
}
''');
      expect(result, 'new');
    });
  });

  group('Runes e2e', () {
    test("'hello'.runes.length", () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 'hello'.runes.length;
}
''');
      expect(result, 5);
    });

    test("'hello'.runes.first", () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 'hello'.runes.first;
}
''');
      expect(result, 104); // 'h'
    });
  });
}
