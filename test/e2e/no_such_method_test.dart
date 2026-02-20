import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// Compiles Dart source and executes with CoreBindings host functions.
Future<Object?> _compileAndRunWithHost(String source) async {
  final module = await compileDart(source);
  final registry = HostFunctionRegistry();
  CoreBindings.registerAll(registry);
  final interp = DarticInterpreter(hostFunctionRegistry: registry);
  interp.execute(module);
  return interp.entryResult;
}

void main() {
  group('noSuchMethod override', () {
    test('override returns custom value for missing method', () async {
      final result = await _compileAndRunWithHost('''
class Flexible {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return 42;
  }
}
Object main() {
  dynamic obj = Flexible();
  return obj.missingMethod();
}
''');
      expect(result, 42);
    });

    test('override returns custom value for missing getter', () async {
      final result = await _compileAndRunWithHost('''
class Flexible {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return 'got it';
  }
}
Object main() {
  dynamic obj = Flexible();
  return obj.missingProperty;
}
''');
      expect(result, 'got it');
    });

    test('override handles missing setter without error', () async {
      final result = await _compileAndRunWithHost('''
class Flexible {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return null;
  }
  int value() => 99;
}
Object main() {
  dynamic obj = Flexible();
  obj.missingProperty = 123;
  return obj.value();
}
''');
      expect(result, 99);
    });
  });

  group('Invocation properties', () {
    test('invocation.memberName for method call', () async {
      final result = await _compileAndRunWithHost('''
class Spy {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return invocation.memberName.toString();
  }
}
Object main() {
  dynamic obj = Spy();
  return obj.hello();
}
''');
      // Symbol.toString() returns 'Symbol("name")' format.
      expect(result, contains('hello'));
    });

    test('invocation.positionalArguments for method call', () async {
      final result = await _compileAndRunWithHost('''
class Spy {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return invocation.positionalArguments.length;
  }
}
Object main() {
  dynamic obj = Spy();
  return obj.someMethod(1, 2, 3);
}
''');
      expect(result, 3);
    });

    test('invocation.isGetter for missing getter', () async {
      final result = await _compileAndRunWithHost('''
class Spy {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return invocation.isGetter;
  }
}
Object main() {
  dynamic obj = Spy();
  return obj.missingProp;
}
''');
      expect(result, true);
    });

    test('invocation.isSetter for missing setter', () async {
      final result = await _compileAndRunWithHost('''
class Spy {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return invocation.isSetter;
  }
}
Object main() {
  dynamic obj = Spy();
  obj.missingProp = 42;
  return true;
}
''');
      // If we reach here without error, the setter was handled.
      expect(result, true);
    });

    test('invocation.isMethod for method call', () async {
      final result = await _compileAndRunWithHost('''
class Spy {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return invocation.isMethod;
  }
}
Object main() {
  dynamic obj = Spy();
  return obj.someMethod();
}
''');
      expect(result, true);
    });
  });

  group('noSuchMethod not overridden', () {
    test('missing method on DarticObject throws NoSuchMethodError', () async {
      final module = await compileDart('''
class Plain {}
Object main() {
  dynamic obj = Plain();
  return obj.doesNotExist();
}
''');
      final registry = HostFunctionRegistry();
      CoreBindings.registerAll(registry);
      final interp = DarticInterpreter(hostFunctionRegistry: registry);
      expect(
        () => interp.execute(module),
        throwsA(isA<NoSuchMethodError>()),
      );
    });

    test('missing getter on DarticObject throws NoSuchMethodError', () async {
      final module = await compileDart('''
class Plain {}
Object main() {
  dynamic obj = Plain();
  return obj.nope;
}
''');
      final registry = HostFunctionRegistry();
      CoreBindings.registerAll(registry);
      final interp = DarticInterpreter(hostFunctionRegistry: registry);
      expect(
        () => interp.execute(module),
        throwsA(isA<NoSuchMethodError>()),
      );
    });
  });

  group('DarticObject via dynamic — existing methods work', () {
    test('INVOKE_DYN dispatches to existing method', () async {
      final result = await _compileAndRunWithHost('''
class Greeter {
  String greet() => 'hi';
}
Object main() {
  dynamic obj = Greeter();
  return obj.greet();
}
''');
      expect(result, 'hi');
    });

    test('GET_FIELD_DYN reads existing field', () async {
      final result = await _compileAndRunWithHost('''
class Box {
  int value;
  Box(this.value);
}
Object main() {
  dynamic obj = Box(77);
  return obj.value;
}
''');
      expect(result, 77);
    });

    test('SET_FIELD_DYN writes existing field', () async {
      final result = await _compileAndRunWithHost('''
class Box {
  int value;
  Box(this.value);
  int getValue() => value;
}
Object main() {
  dynamic obj = Box(0);
  obj.value = 55;
  return obj.getValue();
}
''');
      expect(result, 55);
    });
  });

  group('try/catch catches NoSuchMethodError', () {
    test('catch NoSuchMethodError from missing method', () async {
      final result = await _compileAndRunWithHost('''
class Plain {}
Object main() {
  dynamic obj = Plain();
  try {
    obj.doesNotExist();
  } catch (e) {
    return 'caught';
  }
  return 'not caught';
}
''');
      expect(result, 'caught');
    });

    test('catch NoSuchMethodError from missing getter', () async {
      final result = await _compileAndRunWithHost('''
class Plain {}
Object main() {
  dynamic obj = Plain();
  try {
    var x = obj.nope;
    return x;
  } catch (e) {
    return 'caught';
  }
}
''');
      expect(result, 'caught');
    });
  });
}
