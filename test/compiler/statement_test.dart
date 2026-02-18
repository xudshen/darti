import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('ReturnStatement compilation', () {
    test('int return → RETURN_VAL', () async {
      final module = await compileDart('''
int f() => 42;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // LOAD_INT + RETURN_VAL
      final retIdx = findOp(code, Op.returnVal);
      expect(retIdx, isNot(-1), reason: 'RETURN_VAL not found');
    });

    test('String return → RETURN_REF', () async {
      final module = await compileDart('''
String f() => 'hello';
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      final retIdx = findOp(code, Op.returnRef);
      expect(retIdx, isNot(-1), reason: 'RETURN_REF not found');
    });

    test('void return → RETURN_NULL', () async {
      final module = await compileDart('''
void f() { return; }
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      final retIdx = findOp(code, Op.returnNull);
      expect(retIdx, isNot(-1), reason: 'RETURN_NULL not found');
    });

    test('implicit void return → safety net RETURN_NULL', () async {
      final module = await compileDart('''
void f() {}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // An empty non-entry function body should still end with RETURN_NULL
      // from the safety net.
      final retIdx = findOp(code, Op.returnNull);
      expect(retIdx, isNot(-1), reason: 'safety net RETURN_NULL not found');
    });

    test('entry function return → HALT', () async {
      final module = await compileDart('''
void main() { return; }
''');
      final f = findFunc(module, 'main');
      final code = f.bytecode;

      final haltIdx = findOp(code, Op.halt);
      expect(haltIdx, isNot(-1), reason: 'HALT not found for entry function');
    });

    test('entry function implicit return → safety net HALT', () async {
      final module = await compileDart('''
void main() {}
''');
      final f = findFunc(module, 'main');
      final code = f.bytecode;

      final haltIdx = findOp(code, Op.halt);
      expect(haltIdx, isNot(-1));
    });
  });

  group('ExpressionStatement compilation', () {
    test('expression result is computed', () async {
      final module = await compileDart('''
int g() => 1;
void f() {
  g();
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should have CALL_STATIC for g().
      final callIdx = findOp(code, Op.callStatic);
      expect(callIdx, isNot(-1), reason: 'CALL_STATIC not found');
    });
  });

  group('VariableDeclaration compilation', () {
    test('variable with initializer stores value', () async {
      final module = await compileDart('''
int f() {
  int x = 42;
  return x;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // LOAD_INT for 42
      final loadIdx = findOp(code, Op.loadInt);
      expect(loadIdx, isNot(-1));
      expect(decodesBx(code[loadIdx]), 42);

      // RETURN_VAL
      final retIdx = findOp(code, Op.returnVal);
      expect(retIdx, isNot(-1));

      // The return register should match the variable's register.
      final loadReg = decodeA(code[loadIdx]);
      final retReg = decodeA(code[retIdx]);
      expect(retReg, loadReg,
          reason: 'RETURN_VAL should return the variable register');
    });

    test('variable without initializer gets default', () async {
      final module = await compileDart('''
int f() {
  int x;
  x = 10;
  return x;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // First instruction: LOAD_INT reg, 0 (default for uninitialized int).
      expect(decodeOp(code[0]), Op.loadInt);
      expect(decodesBx(code[0]), 0);
    });

    test('ref variable without initializer gets null', () async {
      final module = await compileDart('''
Object? f() {
  Object? x;
  return x;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // First instruction: LOAD_NULL for uninitialized ref variable.
      expect(decodeOp(code[0]), Op.loadNull);
    });

    test('multiple variable declarations track independent registers', () async {
      final module = await compileDart('''
int f() {
  int x = 1;
  int y = 2;
  return x + y;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should have two LOAD_INT instructions with different registers.
      final load1Idx = findOp(code, Op.loadInt);
      expect(load1Idx, isNot(-1));
      final load1Reg = decodeA(code[load1Idx]);

      // Find second LOAD_INT after the first.
      final load2Idx = _findOpAfter(code, Op.loadInt, load1Idx + 1);
      expect(load2Idx, isNot(-1), reason: 'second LOAD_INT not found');
      final load2Reg = decodeA(code[load2Idx]);

      expect(load1Reg, isNot(load2Reg),
          reason: 'x and y should use different registers');

      // ADD_INT should combine them.
      final addIdx = findOp(code, Op.addInt);
      expect(addIdx, isNot(-1));
    });
  });

  group('VariableSet compilation', () {
    test('variable assignment emits MOVE_VAL', () async {
      final module = await compileDart('''
int f() {
  int x = 1;
  x = 2;
  return x;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should contain MOVE_VAL for the assignment x = 2.
      final moveIdx = findOp(code, Op.moveVal);
      expect(moveIdx, isNot(-1), reason: 'MOVE_VAL not found for assignment');
    });
  });

  group('Block compilation', () {
    test('block compiles all statements', () async {
      final module = await compileDart('''
int f() {
  int a = 1;
  int b = 2;
  int c = a + b;
  return c;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should have: LOAD_INT, LOAD_INT, ADD_INT, RETURN_VAL
      expect(findOp(code, Op.loadInt), isNot(-1));
      expect(findOp(code, Op.addInt), isNot(-1));
      expect(findOp(code, Op.returnVal), isNot(-1));
    });
  });

  group('multi-statement function', () {
    test('int f() { var x = 1; return x; } compiles correctly', () async {
      final module = await compileDart('''
int f() {
  var x = 1;
  return x;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // LOAD_INT reg, 1
      expect(decodeOp(code[0]), Op.loadInt);
      expect(decodesBx(code[0]), 1);
      final xReg = decodeA(code[0]);

      // RETURN_VAL reg  (should reference same register)
      expect(decodeOp(code[1]), Op.returnVal);
      expect(decodeA(code[1]), xReg);
    });

    test('function with computation and return', () async {
      final module = await compileDart('''
int f(int a, int b) {
  int sum = a + b;
  return sum;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // ADD_INT for a + b
      final addIdx = findOp(code, Op.addInt);
      expect(addIdx, isNot(-1));
      final sumReg = decodeA(code[addIdx]);

      // RETURN_VAL should reference the ADD_INT result.
      final retIdx = findOp(code, Op.returnVal);
      expect(retIdx, isNot(-1));
      expect(decodeA(code[retIdx]), sumReg);
    });
  });
}

/// Finds the first instruction with the given [op]code at or after [start].
int _findOpAfter(List<int> code, int op, int start) {
  for (var i = start; i < code.length; i++) {
    if (decodeOp(code[i]) == op) return i;
  }
  return -1;
}
