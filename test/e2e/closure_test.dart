import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// End-to-end tests for closures: Dart source -> CFE -> DarticCompiler ->
/// DarticInterpreter.
///
/// Covers: FunctionDeclaration, upvalue capture, mutation sharing,
/// nested closures, and LocalFunctionInvocation.
void main() {
  group('simple closure captures variable', () {
    test('read-only capture of int', () async {
      final result = await compileAndRun('''
int f() {
  int x = 10;
  int g() => x;
  return g();
}
int main() => f();
''');
      expect(result, 10);
    });

    test('capture multiple variables', () async {
      final result = await compileAndRun('''
int f() {
  int a = 3;
  int b = 7;
  int g() => a + b;
  return g();
}
int main() => f();
''');
      expect(result, 10);
    });
  });

  group('closure mutation sharing', () {
    test('inner function increments captured variable', () async {
      final result = await compileAndRun('''
int f() {
  int x = 0;
  void inc() { x = x + 1; }
  inc();
  inc();
  return x;
}
int main() => f();
''');
      expect(result, 2);
    });

    test('two closures share the same captured variable', () async {
      final result = await compileAndRun('''
int f() {
  int x = 0;
  void inc() { x = x + 1; }
  int get() => x;
  inc();
  inc();
  inc();
  return get();
}
int main() => f();
''');
      expect(result, 3);
    });
  });

  group('nested closures (transitive upvalue)', () {
    test('two-level nesting', () async {
      final result = await compileAndRun('''
int f() {
  int x = 5;
  int g() {
    int h() => x;
    return h();
  }
  return g();
}
int main() => f();
''');
      expect(result, 5);
    });

    test('three-level nesting', () async {
      final result = await compileAndRun('''
int f() {
  int x = 42;
  int a() {
    int b() {
      int c() => x;
      return c();
    }
    return b();
  }
  return a();
}
int main() => f();
''');
      expect(result, 42);
    });
  });

  group('closure with parameters', () {
    test('closure takes parameter and uses captured variable', () async {
      final result = await compileAndRun('''
int f() {
  int base = 100;
  int add(int n) => base + n;
  return add(23);
}
int main() => f();
''');
      expect(result, 123);
    });
  });

  group('closure with named parameters', () {
    test('local function with named parameter', () async {
      final result = await compileAndRun('''
int f() {
  int g({required int x}) => x + 1;
  return g(x: 41);
}
int main() => f();
''');
      expect(result, 42);
    });

    test('local function with positional and named parameters', () async {
      final result = await compileAndRun('''
int f() {
  int g(int a, {required int b}) => a + b;
  return g(10, b: 20);
}
int main() => f();
''');
      expect(result, 30);
    });

    test('lambda with named parameter via FunctionInvocation', () async {
      final result = await compileAndRun('''
int f() {
  var g = ({required int x}) => x * 2;
  return g(x: 21);
}
int main() => f();
''');
      expect(result, 42);
    });
  });

  group('closure returning closure', () {
    test('factory pattern: outer returns inner closure', () async {
      final result = await compileAndRun('''
int f() {
  int x = 10;
  int Function() maker() {
    return () => x;
  }
  var g = maker();
  return g();
}
int main() => f();
''');
      expect(result, 10);
    });
  });

  group('block-scoped closure upvalue closing (L1)', () {
    test('closure captures block-local variable, reads correct value after block exits',
        () async {
      final result = await compileAndRun('''
int main() {
  int Function() fn = () => 0;
  {
    int x = 42;
    fn = () => x;
  }
  // After block exits, x's register may be reused.
  // CLOSE_UPVALUE should have snapshotted x's value.
  return fn();
}
''');
      expect(result, 42);
    });

    test('nested block closure captures and returns correct value', () async {
      final result = await compileAndRun('''
int main() {
  int Function() fn = () => 0;
  {
    int a = 10;
    {
      int b = 32;
      fn = () => a + b;
    }
    // b's register may be reused here, but CLOSE_UPVALUE snapshotted it.
  }
  return fn();
}
''');
      expect(result, 42);
    });
  });
}
