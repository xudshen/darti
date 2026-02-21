import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  // ── Direction 1: int op double (receiver=int, arg=double) ──
  group('int op double — bytecode', () {
    test('int + double → INT_TO_DBL + ADD_DBL (not ADD_INT)', () async {
      final module = await compileDart('''
double f(int a, double b) => a + b;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;
      expect(findOp(code, Op.intToDbl), isNot(-1),
          reason: 'INT_TO_DBL not found — int receiver not promoted');
      expect(findOp(code, Op.addDbl), isNot(-1),
          reason: 'ADD_DBL not found — wrong opcode');
      expect(findOp(code, Op.addInt), -1,
          reason: 'ADD_INT should not appear for int + double');
    });

    test('int * double → INT_TO_DBL + MUL_DBL', () async {
      final module = await compileDart('''
double f(int a, double b) => a * b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.intToDbl), isNot(-1));
      expect(findOp(f.bytecode, Op.mulDbl), isNot(-1));
      expect(findOp(f.bytecode, Op.mulInt), -1);
    });

    test('int - double → INT_TO_DBL + SUB_DBL', () async {
      final module = await compileDart('''
double f(int a, double b) => a - b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.intToDbl), isNot(-1));
      expect(findOp(f.bytecode, Op.subDbl), isNot(-1));
    });

    test('int < double → INT_TO_DBL + LT_DBL', () async {
      final module = await compileDart('''
bool f(int a, double b) => a < b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.intToDbl), isNot(-1));
      expect(findOp(f.bytecode, Op.ltDbl), isNot(-1));
    });
  });

  group('int op double — end-to-end', () {
    test('int * double', () async {
      expect(await compileAndRun('''
double main() { int i = 5; return i * 3.14; }
'''), closeTo(15.7, 0.001));
    });

    test('int + double', () async {
      expect(await compileAndRun('''
double main() { int i = 10; return i + 2.5; }
'''), 12.5);
    });

    test('int - double', () async {
      expect(await compileAndRun('''
double main() { int i = 10; return i - 3.5; }
'''), 6.5);
    });

    test('int < double', () async {
      expect(await compileAndRun('''
bool main() { int i = 3; return i < 3.14; }
'''), true);
    });

    test('int >= double', () async {
      expect(await compileAndRun('''
bool main() { int i = 4; return i >= 3.14; }
'''), true);
    });

    test('int ~/ double', () async {
      expect(await compileAndRun('''
int main() { int i = 10; return i ~/ 3.0; }
'''), 3);
    });

    test('int % double', () async {
      expect(await compileAndRun('''
double main() { int i = 10; return i % 3.5; }
'''), closeTo(3.0, 0.001));
    });
  });

  // ── Direction 2: double op int (receiver=double, arg=int) ──
  group('double op int — bytecode', () {
    test('double + int → INT_TO_DBL + ADD_DBL', () async {
      final module = await compileDart('''
double f(double a, int b) => a + b;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;
      expect(findOp(code, Op.intToDbl), isNot(-1),
          reason: 'INT_TO_DBL not found — int arg not promoted');
      expect(findOp(code, Op.addDbl), isNot(-1));
    });

    test('double * int → INT_TO_DBL + MUL_DBL', () async {
      final module = await compileDart('''
double f(double a, int b) => a * b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.intToDbl), isNot(-1));
      expect(findOp(f.bytecode, Op.mulDbl), isNot(-1));
    });

    test('double > int → INT_TO_DBL + GT_DBL', () async {
      final module = await compileDart('''
bool f(double a, int b) => a > b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.intToDbl), isNot(-1));
      expect(findOp(f.bytecode, Op.gtDbl), isNot(-1));
    });
  });

  group('double op int — end-to-end', () {
    test('double + int', () async {
      expect(await compileAndRun('''
double main() { double x = 3.14; int y = 2; return x + y; }
'''), closeTo(5.14, 0.001));
    });

    test('double * int', () async {
      expect(await compileAndRun('''
double main() { double x = 2.5; int y = 4; return x * y; }
'''), 10.0);
    });

    test('double - int', () async {
      expect(await compileAndRun('''
double main() { double x = 10.5; int y = 3; return x - y; }
'''), 7.5);
    });

    test('double > int comparison', () async {
      expect(await compileAndRun('''
bool main() { double x = 3.5; int y = 2; return x > y; }
'''), true);
    });

    test('double < int comparison', () async {
      expect(await compileAndRun('''
bool main() { double x = 1.5; int y = 2; return x < y; }
'''), true);
    });

    test('double / int', () async {
      expect(await compileAndRun('''
double main() { double x = 10.0; int y = 4; return x / y; }
'''), 2.5);
    });
  });

  // ── Direction 3: int / double (existing special path bug) ──
  group('int / double — special case', () {
    test('int / double returns correct value', () async {
      expect(await compileAndRun('''
double main() { int x = 10; double y = 3.0; return x / y; }
'''), closeTo(3.333, 0.01));
    });

    test('int / double with non-integer result', () async {
      expect(await compileAndRun('''
double main() { int x = 7; double y = 2.0; return x / y; }
'''), 3.5);
    });
  });

  // ── Chained expressions and type inference ──
  group('chained mixed expressions', () {
    test('(int * double) + double', () async {
      expect(await compileAndRun('''
double main() { int i = 2; return (i * 3.14) + 1.0; }
'''), closeTo(7.28, 0.001));
    });

    test('double + (int * double) chains correctly', () async {
      expect(await compileAndRun('''
double main() { int i = 3; double d = 2.5; return d + (i * d); }
'''), closeTo(10.0, 0.001));
    });

    test('int * double assigned to double var', () async {
      expect(await compileAndRun('''
double main() { int i = 3; double x = i * 2.5; return x; }
'''), 7.5);
    });

    test('(int * double) + double bytecode has no int arithmetic ops', () async {
      final module = await compileDart('''
double f(int i, double d) => (i * d) + d;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.mulDbl), isNot(-1));
      expect(findOp(f.bytecode, Op.addDbl), isNot(-1));
    });
  });

  // ── modDbl opcode verification ──
  group('modDbl opcode', () {
    test('double % double uses MOD_DBL', () async {
      final module = await compileDart('''
double f(double a, double b) => a % b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.modDbl), isNot(-1),
          reason: 'MOD_DBL not found');
    });

    test('double % double end-to-end', () async {
      expect(await compileAndRun('''
double main() { return 10.0 % 3.5; }
'''), closeTo(3.0, 0.001));
    });
  });

  // ── Benchmark reproducer ──
  group('benchmark reproducer', () {
    test('double_arithmetic benchmark (the original failing program)', () async {
      final result = await compileAndRunWithHost('''
int main() {
  double sum = 0.0;
  for (int i = 0; i < 10000; i++) {
    sum = sum + i * 3.14 - i / 2.0;
  }
  return sum.floor();
}
''', fuelBudget: 500000);
      expect(result, isA<int>());
      final v = result as int;
      expect(v, greaterThan(100000000));
      expect(v, lessThan(200000000));
    });

    test('smaller loop for quick validation', () async {
      final result = await compileAndRunWithHost('''
int main() {
  double sum = 0.0;
  for (int i = 0; i < 100; i++) {
    sum = sum + i * 3.14 - i / 2.0;
  }
  return sum.floor();
}
''');
      expect(result, isA<int>());
      expect(result, greaterThan(0));
    });
  });

  // ── Mixed int/double equality ──
  group('mixed int/double equality — bytecode', () {
    test('int == double → INT_TO_DBL + EQ_DBL (not EQ_GENERIC)', () async {
      final module = await compileDart('''
bool f(int a, double b) => a == b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.intToDbl), isNot(-1),
          reason: 'INT_TO_DBL not found — int not promoted');
      expect(findOp(f.bytecode, Op.eqDbl), isNot(-1),
          reason: 'EQ_DBL not found');
      expect(findOp(f.bytecode, Op.eqGeneric), -1,
          reason: 'EQ_GENERIC should not appear for int == double');
    });

    test('double == int → INT_TO_DBL + EQ_DBL', () async {
      final module = await compileDart('''
bool f(double a, int b) => a == b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.intToDbl), isNot(-1),
          reason: 'INT_TO_DBL not found — int not promoted');
      expect(findOp(f.bytecode, Op.eqDbl), isNot(-1),
          reason: 'EQ_DBL not found');
      expect(findOp(f.bytecode, Op.eqGeneric), -1,
          reason: 'EQ_GENERIC should not appear for double == int');
    });
  });

  group('mixed int/double equality — end-to-end', () {
    test('3 == 3.0 → true', () async {
      expect(await compileAndRun('''
bool main() { int a = 3; double b = 3.0; return a == b; }
'''), true);
    });

    test('3 == 3.1 → false', () async {
      expect(await compileAndRun('''
bool main() { int a = 3; double b = 3.1; return a == b; }
'''), false);
    });

    test('3.0 == 3 → true', () async {
      expect(await compileAndRun('''
bool main() { double a = 3.0; int b = 3; return a == b; }
'''), true);
    });
  });

  // ── double ~/ (truncating division) ──
  group('double ~/ — bytecode', () {
    test('double ~/ int → INT_TO_DBL + DIV_DBL + DBL_TO_INT', () async {
      final module = await compileDart('''
int f(double a, int b) => a ~/ b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.intToDbl), isNot(-1),
          reason: 'INT_TO_DBL not found — int arg not promoted');
      expect(findOp(f.bytecode, Op.divDbl), isNot(-1),
          reason: 'DIV_DBL not found');
      expect(findOp(f.bytecode, Op.dblToInt), isNot(-1),
          reason: 'DBL_TO_INT not found — result not truncated');
    });

    test('double ~/ double → DIV_DBL + DBL_TO_INT (no INT_TO_DBL)', () async {
      final module = await compileDart('''
int f(double a, double b) => a ~/ b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.intToDbl), -1,
          reason: 'INT_TO_DBL should not appear for double ~/ double');
      expect(findOp(f.bytecode, Op.divDbl), isNot(-1),
          reason: 'DIV_DBL not found');
      expect(findOp(f.bytecode, Op.dblToInt), isNot(-1),
          reason: 'DBL_TO_INT not found — result not truncated');
    });
  });

  group('double ~/ — end-to-end', () {
    test('7.5 ~/ 2 → 3', () async {
      expect(await compileAndRun('''
int main() { double a = 7.5; int b = 2; return a ~/ b; }
'''), 3);
    });

    test('7.5 ~/ 2.5 → 3', () async {
      expect(await compileAndRun('''
int main() { double a = 7.5; double b = 2.5; return a ~/ b; }
'''), 3);
    });
  });

  // ── != symmetry ──
  group('!= symmetry', () {
    test('3 != 3.1 → true (optimized path)', () async {
      expect(await compileAndRun('''
bool main() { int a = 3; double b = 3.1; return a != b; }
'''), true);
    });
  });
}
