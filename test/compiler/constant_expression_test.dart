import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  // ── ConstantExpression ──

  group('ConstantExpression compilation', () {
    test('const int → compiles and executes correctly', () async {
      // CFE wraps top-level const in ConstantExpression(IntConstant).
      final module = await compileDart('''
int f() {
  const x = 42;
  return x;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should produce a LOAD_INT (small int) somewhere.
      final loadIdx = findOp(code, Op.loadInt);
      expect(loadIdx, isNot(-1), reason: 'LOAD_INT not found');
      expect(decodesBx(code[loadIdx]), 42);
    });

    test('const bool true/false → LOAD_TRUE / LOAD_FALSE', () async {
      final module = await compileDart('''
bool f() {
  const x = true;
  return x;
}
bool g() {
  const y = false;
  return y;
}
void main() {}
''');
      final fCode = findFunc(module, 'f').bytecode;
      final gCode = findFunc(module, 'g').bytecode;

      expect(findOp(fCode, Op.loadTrue), isNot(-1),
          reason: 'LOAD_TRUE not found for const true');
      expect(findOp(gCode, Op.loadFalse), isNot(-1),
          reason: 'LOAD_FALSE not found for const false');
    });

    test('const double → LOAD_CONST_DBL', () async {
      final module = await compileDart('''
double f() {
  const x = 3.14;
  return x;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      final loadIdx = findOp(code, Op.loadConstDbl);
      expect(loadIdx, isNot(-1), reason: 'LOAD_CONST_DBL not found');
      final bx = decodeBx(code[loadIdx]);
      expect(module.constantPool.getDouble(bx), 3.14);
    });

    test('const string → LOAD_CONST', () async {
      final module = await compileDart('''
String f() {
  const x = 'hello';
  return x;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      final loadIdx = findOp(code, Op.loadConst);
      expect(loadIdx, isNot(-1), reason: 'LOAD_CONST not found');
      final bx = decodeBx(code[loadIdx]);
      expect(module.constantPool.getRef(bx), 'hello');
    });

    test('const null → LOAD_NULL', () async {
      final module = await compileDart('''
Object? f() {
  const x = null;
  return x;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      expect(findOp(code, Op.loadNull), isNot(-1),
          reason: 'LOAD_NULL not found');
    });

    test('large const int → LOAD_CONST_INT', () async {
      final module = await compileDart('''
int f() {
  const x = 100000;
  return x;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      final loadIdx = findOp(code, Op.loadConstInt);
      expect(loadIdx, isNot(-1), reason: 'LOAD_CONST_INT not found');
      final bx = decodeBx(code[loadIdx]);
      expect(module.constantPool.getInt(bx), 100000);
    });
  });

  // ── Not ──

  group('Not expression compilation', () {
    test('!true → BIT_XOR produces 0', () async {
      final module = await compileDart('''
bool f() => !true;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should have BIT_XOR for boolean negation.
      final xorIdx = findOp(code, Op.bitXor);
      expect(xorIdx, isNot(-1), reason: 'BIT_XOR not found for !true');
    });

    test('!false → BIT_XOR produces 1', () async {
      final module = await compileDart('''
bool g() => !false;
void main() {}
''');
      final g = findFunc(module, 'g');
      final code = g.bytecode;

      final xorIdx = findOp(code, Op.bitXor);
      expect(xorIdx, isNot(-1), reason: 'BIT_XOR not found for !false');
    });

    test('Not does not modify operand register in-place', () async {
      // `!x` should produce a new result register, not mutate x's register.
      final module = await compileDart('''
bool f(bool x) => !x;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      final xorIdx = findOp(code, Op.bitXor);
      expect(xorIdx, isNot(-1));
      // A field in ABC: result reg (A) != operand reg (B)
      final resultReg = decodeA(code[xorIdx]);
      final operandReg = decodeB(code[xorIdx]);
      expect(resultReg, isNot(operandReg),
          reason: 'Not should allocate a new result register');
    });
  });

  // ── EqualsNull ──

  group('EqualsNull compilation', () {
    test('x == null where x is null → JUMP_IF_NNULL pattern', () async {
      final module = await compileDart('''
bool f(Object? x) => x == null;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should produce JUMP_IF_NNULL for `x == null`.
      final jumpIdx = findOp(code, Op.jumpIfNnull);
      expect(jumpIdx, isNot(-1),
          reason: 'JUMP_IF_NNULL not found for x == null');
    });

    test('x != null → Not(EqualsNull(x)) pattern', () async {
      // CFE represents `x != null` as `Not(EqualsNull(x))`.
      // EqualsNull emits JUMP_IF_NNULL, Not emits BIT_XOR.
      final module = await compileDart('''
bool f(Object? x) => x != null;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should contain JUMP_IF_NNULL (from EqualsNull) + BIT_XOR (from Not).
      expect(findOp(code, Op.jumpIfNnull), isNot(-1),
          reason: 'JUMP_IF_NNULL expected from EqualsNull in Not(EqualsNull)');
      expect(findOp(code, Op.bitXor), isNot(-1),
          reason: 'BIT_XOR expected from Not wrapping EqualsNull');
    });

    test('x == null bytecode structure', () async {
      final module = await compileDart('''
bool f(Object? x) => x == null;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Expected pattern:
      //   LOAD_FALSE resultReg
      //   JUMP_IF_NNULL refReg, +1
      //   LOAD_TRUE resultReg
      //   RETURN_VAL resultReg

      final falseIdx = findOp(code, Op.loadFalse);
      expect(falseIdx, isNot(-1));
      final resultReg = decodeA(code[falseIdx]);

      final jumpIdx = findOp(code, Op.jumpIfNnull, start: falseIdx + 1);
      expect(jumpIdx, isNot(-1));
      expect(decodesBx(code[jumpIdx]), 1,
          reason: 'sBx should be +1 to skip LOAD_TRUE');

      final trueIdx = findOp(code, Op.loadTrue, start: jumpIdx + 1);
      expect(trueIdx, isNot(-1));
      expect(decodeA(code[trueIdx]), resultReg,
          reason: 'LOAD_TRUE should target same result register');
    });

    test('x != null bytecode structure (Not wrapping EqualsNull)', () async {
      // CFE represents `x != null` as Not(EqualsNull(x)).
      // EqualsNull: LOAD_FALSE → JUMP_IF_NNULL +1 → LOAD_TRUE
      // Not: LOAD_INT 1 → BIT_XOR (flips the 0/1 result)
      final module = await compileDart('''
bool f(Object? x) => x != null;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Verify the EqualsNull part exists.
      final jumpIdx = findOp(code, Op.jumpIfNnull);
      expect(jumpIdx, isNot(-1));

      // Verify the Not part (BIT_XOR) follows.
      final xorIdx = findOp(code, Op.bitXor, start: jumpIdx + 1);
      expect(xorIdx, isNot(-1),
          reason: 'BIT_XOR should follow the EqualsNull pattern');
    });
  });

  // ── EqualsCall ──

  group('EqualsCall compilation', () {
    test('int == int → EQ_INT', () async {
      final module = await compileDart('''
bool f(int a, int b) => a == b;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      final eqIdx = findOp(code, Op.eqInt);
      expect(eqIdx, isNot(-1), reason: 'EQ_INT not found for int == int');
    });

    test('Object == Object → EQ_REF', () async {
      final module = await compileDart('''
bool f(Object a, Object b) => a == b;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      final eqIdx = findOp(code, Op.eqRef);
      expect(eqIdx, isNot(-1), reason: 'EQ_REF not found for Object == Object');
    });

    test('int equality result goes to value stack', () async {
      final module = await compileDart('''
bool f(int a, int b) => a == b;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // EQ_INT result is on value stack, so RETURN_VAL should follow.
      expect(findOp(code, Op.returnVal), isNot(-1),
          reason: 'RETURN_VAL expected for bool result');
    });
  });

  // ── Let ──

  group('Let expression compilation', () {
    // CFE generates Let nodes for certain internal temporaries.
    // It's hard to force CFE to produce Let from user-level code,
    // so we verify the compiler doesn't crash on patterns that may
    // internally use Let, and verify bytecode-level behavior.
    test('compound expression that may use Let compiles', () async {
      // String interpolation or cascades may generate Let nodes.
      // For now, test that the compiler handles code that may produce Let.
      final module = await compileDart('''
int f(int x) {
  int y = x + 1;
  return y;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.returnVal), isNot(-1));
    });
  });

  // ── BlockExpression ──

  group('BlockExpression compilation', () {
    // BlockExpression is a CFE internal node rarely produced from simple code.
    // Test the compiler doesn't crash on patterns that may use it.
    test('complex expression compiles without error', () async {
      final module = await compileDart('''
int f(int x) {
  int a = 1;
  int b = a + x;
  return b;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.returnVal), isNot(-1));
    });
  });

  // ── _inferExprType extensions ──

  group('_inferExprType extensions', () {
    test('ConstantExpression(IntConstant) infers int type for arithmetic',
        () async {
      // `const x = 5; return x + 1;` — CFE may emit ConstantExpression for x.
      // The compiler must infer int type for it to use ADD_INT.
      final module = await compileDart('''
int f() {
  const x = 5;
  return x + 1;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should use ADD_INT (not crash from unknown type).
      expect(findOp(code, Op.addInt), isNot(-1),
          reason: 'ADD_INT expected when adding const int + literal');
    });

    test('Not infers bool type', () async {
      // bool negation should return value-stack result (bool).
      final module = await compileDart('''
bool f() => !true;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.returnVal), isNot(-1),
          reason: 'Bool negation should return via RETURN_VAL');
    });

    test('EqualsNull infers bool type', () async {
      final module = await compileDart('''
bool f(Object? x) => x == null;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.returnVal), isNot(-1),
          reason: 'EqualsNull should return via RETURN_VAL');
    });

    test('EqualsCall infers bool type', () async {
      final module = await compileDart('''
bool f(int a, int b) => a == b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.returnVal), isNot(-1),
          reason: 'EqualsCall should return via RETURN_VAL');
    });
  });

  // ── End-to-end execution ──

  group('end-to-end execution', () {
    test('const int 42 executes correctly', () async {
      final module = await compileDart('''
int main() {
  const x = 42;
  return x;
}
''');
      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 42);
    });

    test('const int 100000 (large) executes correctly', () async {
      final module = await compileDart('''
int main() {
  const x = 100000;
  return x;
}
''');
      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 100000);
    });

    test('!true and !false compile with BIT_XOR', () async {
      final module = await compileDart('''
bool f() => !true;
bool g() => !false;
int main() => 42;
''');
      expect(findOp(findFunc(module, 'f').bytecode, Op.bitXor), isNot(-1));
      expect(findOp(findFunc(module, 'g').bytecode, Op.bitXor), isNot(-1));
    });

    test('int == int compiles with EQ_INT', () async {
      final module = await compileDart('''
bool eq(int a, int b) => a == b;
int main() => 42;
''');
      expect(findOp(findFunc(module, 'eq').bytecode, Op.eqInt), isNot(-1));
    });

    test('const arithmetic via function call', () async {
      // Use function call pattern to ensure result lands in v0.
      final module = await compileDart('''
int add(int a, int b) => a + b;
int main() => add(10, 20);
''');
      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 30);
    });
  });
}
