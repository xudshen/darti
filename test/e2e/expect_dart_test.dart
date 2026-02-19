import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// Simplified expect.dart source that mirrors the co19 Utils/expect.dart
/// structure but avoids unsupported features (dart:async, generics,
/// string interpolation, library/part directives).
const _expectDartSource = '''
void _fail(String message) {
  throw ExpectException(message);
}

class Expect {
  static void equals(Object? expected, Object? actual) {
    if (expected != actual) {
      _fail('Expect.equals fails');
    }
  }
  static void isTrue(Object? actual) {
    if (actual != true) {
      _fail('Expect.isTrue fails');
    }
  }
  static void isFalse(Object? actual) {
    if (actual != false) {
      _fail('Expect.isFalse fails');
    }
  }
  static void throws(void Function() func) {
    try {
      func();
    } catch (e) {
      return;
    }
    _fail('Expect.throws fails');
  }
}

class ExpectException {
  String? message;
  ExpectException(this.message);
  String toString() => message ?? '';
}
''';

void main() {
  group('simplified expect.dart', () {
    test('compiles and runs basic usage', () async {
      final result = await compileAndRunMultiFile({
        'main.dart': '''
import 'expect.dart';

int main() {
  Expect.equals(1, 1);
  Expect.isTrue(true);
  Expect.isFalse(false);
  return 42;
}
''',
        'expect.dart': _expectDartSource,
      });
      expect(result, 42);
    });

    test('Expect.equals passes on equal values', () async {
      final result = await compileAndRunMultiFile({
        'main.dart': '''
import 'expect.dart';

int main() {
  Expect.equals(10, 10);
  return 0;
}
''',
        'expect.dart': _expectDartSource,
      });
      expect(result, 0);
    });

    test('Expect.equals fails on unequal values', () async {
      // When Expect.equals fails, it throws ExpectException.
      // Our interpreter should propagate this as a runtime error.
      expect(
        () => compileAndRunMultiFile({
          'main.dart': '''
import 'expect.dart';

int main() {
  Expect.equals(1, 2);
  return 0;
}
''',
          'expect.dart': _expectDartSource,
        }),
        throwsA(anything),
      );
    });

    test('Expect.isTrue passes on true', () async {
      final result = await compileAndRunMultiFile({
        'main.dart': '''
import 'expect.dart';

int main() {
  Expect.isTrue(true);
  return 0;
}
''',
        'expect.dart': _expectDartSource,
      });
      expect(result, 0);
    });

    test('Expect.isFalse passes on false', () async {
      final result = await compileAndRunMultiFile({
        'main.dart': '''
import 'expect.dart';

int main() {
  Expect.isFalse(false);
  return 0;
}
''',
        'expect.dart': _expectDartSource,
      });
      expect(result, 0);
    });

    test('Expect.throws catches exception', () async {
      final result = await compileAndRunMultiFile({
        'main.dart': '''
import 'expect.dart';

int main() {
  Expect.throws(() { throw 'error'; });
  return 0;
}
''',
        'expect.dart': _expectDartSource,
      });
      expect(result, 0);
    });
  });
}
