import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// End-to-end tests for exception handling.
void main() {
  group('try/catch e2e', () {
    test('catch catches thrown exception and returns value', () async {
      final result = await compileAndRun('''
int f() {
  try {
    throw 'error';
  } catch (e) {
    return 42;
  }
  return 0;
}
int main() => f();
''');
      expect(result, 42);
    });

    test('no exception: try body executes normally', () async {
      final result = await compileAndRun('''
int f() {
  int x = 0;
  try {
    x = 10;
  } catch (e) {
    x = -1;
  }
  return x;
}
int main() => f();
''');
      expect(result, 10);
    });

    test('nested try-catch: inner catch handles exception', () async {
      final result = await compileAndRun('''
int f() {
  try {
    try {
      throw 'inner';
    } catch (e) {
      return 1;
    }
  } catch (e) {
    return 2;
  }
  return 0;
}
int main() => f();
''');
      expect(result, 1);
    });

    test('rethrow propagates to outer catch', () async {
      final result = await compileAndRun('''
int f() {
  try {
    try {
      throw 'error';
    } catch (e) {
      rethrow;
    }
  } catch (e) {
    return 99;
  }
  return 0;
}
int main() => f();
''');
      expect(result, 99);
    });
  });

  group('try/finally e2e', () {
    test('finally executes on normal path', () async {
      final result = await compileAndRun('''
int f() {
  int x = 0;
  try {
    x = 1;
  } finally {
    x = x + 10;
  }
  return x;
}
int main() => f();
''');
      expect(result, 11);
    });

    test('finally executes on exception path', () async {
      final result = await compileAndRun('''
int f() {
  int x = 0;
  try {
    try {
      x = 1;
      throw 'error';
    } finally {
      x = x + 10;
    }
  } catch (e) {
    return x;
  }
  return -1;
}
int main() => f();
''');
      // x = 1, then finally adds 10, so x = 11 when caught
      expect(result, 11);
    });
  });

  group('throw expression', () {
    test('throw in conditional expression', () async {
      final result = await compileAndRun('''
int f(int x) {
  try {
    int y = x > 0 ? x : throw 'negative';
    return y;
  } catch (e) {
    return -1;
  }
}
int main() => f(-5);
''');
      expect(result, -1);
    });

    test('throw in conditional, no exception path', () async {
      final result = await compileAndRun('''
int f(int x) {
  try {
    int y = x > 0 ? x : throw 'negative';
    return y;
  } catch (e) {
    return -1;
  }
}
int main() => f(5);
''');
      expect(result, 5);
    });
  });

  group('typed catch (on Type)', () {
    test('on typed catch catches matching type', () async {
      final result = await compileAndRun('''
class MyException {
  int code;
  MyException(this.code);
}
int f() {
  try {
    throw MyException(42);
  } on MyException catch (e) {
    return e.code;
  } catch (e) {
    return -1;
  }
  return 0;
}
int main() => f();
''');
      expect(result, 42);
    });

    test('typed catch skips non-matching type, falls through to catch-all',
        () async {
      final result = await compileAndRun('''
class ExA {
  int val;
  ExA(this.val);
}
class ExB {
  int val;
  ExB(this.val);
}
int f() {
  try {
    throw ExB(99);
  } on ExA catch (e) {
    return e.val;
  } catch (e) {
    return -1;
  }
  return 0;
}
int main() => f();
''');
      expect(result, -1);
    });

    test('multiple typed catch clauses match in order', () async {
      final result = await compileAndRun('''
class Base {
  int val;
  Base(this.val);
}
class Sub extends Base {
  Sub(int v) : super(v);
}
int f() {
  try {
    throw Sub(77);
  } on Sub catch (e) {
    return e.val;
  } on Base catch (e) {
    return e.val + 100;
  } catch (e) {
    return -1;
  }
  return 0;
}
int main() => f();
''');
      // Sub matches first
      expect(result, 77);
    });

    test('typed catch matches subclass via supertype guard', () async {
      final result = await compileAndRun('''
class Base {
  int val;
  Base(this.val);
}
class Sub extends Base {
  Sub(int v) : super(v);
}
int f() {
  try {
    throw Sub(55);
  } on Base catch (e) {
    return e.val;
  } catch (e) {
    return -1;
  }
  return 0;
}
int main() => f();
''');
      // Sub is a subtype of Base, so on Base catches it
      expect(result, 55);
    });

    test('catch-all still works with no guard', () async {
      final result = await compileAndRun('''
class MyEx {
  int val;
  MyEx(this.val);
}
int f() {
  try {
    throw MyEx(10);
  } catch (e) {
    return 42;
  }
  return 0;
}
int main() => f();
''');
      expect(result, 42);
    });
  });
}
