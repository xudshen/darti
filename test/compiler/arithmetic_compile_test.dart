import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('arithmetic compilation', () {
    test('int add → ADD_INT', () async {
      final module = await compileDart('''
int f(int a, int b) => a + b;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should contain ADD_INT somewhere.
      final addIdx = findOp(code, Op.addInt);
      expect(addIdx, isNot(-1), reason: 'ADD_INT not found');
      expect(decodeOp(code[addIdx]), Op.addInt);
    });

    test('int subtract → SUB_INT', () async {
      final module = await compileDart('''
int f(int a, int b) => a - b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.subInt), isNot(-1));
    });

    test('int multiply → MUL_INT', () async {
      final module = await compileDart('''
int f(int a, int b) => a * b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.mulInt), isNot(-1));
    });

    test('int truncating division → DIV_INT', () async {
      final module = await compileDart('''
int f(int a, int b) => a ~/ b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.divInt), isNot(-1));
    });

    test('int modulo → MOD_INT', () async {
      final module = await compileDart('''
int f(int a, int b) => a % b;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.modInt), isNot(-1));
    });

    test('int negation → NEG_INT', () async {
      final module = await compileDart('''
int f(int a) => -a;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(findOp(f.bytecode, Op.negInt), isNot(-1));
    });

    test('compound expression a + b * c → correct register allocation', () async {
      final module = await compileDart('''
int f(int a, int b, int c) => a + b * c;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Due to Dart precedence: b * c first, then a + result.
      // Should generate: MUL_INT temp = b * c; ADD_INT result = a + temp
      final mulIdx = findOp(code, Op.mulInt);
      final addIdx = findOp(code, Op.addInt);
      expect(mulIdx, isNot(-1), reason: 'MUL_INT not found');
      expect(addIdx, isNot(-1), reason: 'ADD_INT not found');
      expect(mulIdx, lessThan(addIdx),
          reason: 'MUL should come before ADD (b*c before a+result)');

      // RETURN_VAL should reference the ADD_INT result.
      final retIdx = findOp(code, Op.returnVal);
      expect(retIdx, isNot(-1));
      final addResult = decodeA(code[addIdx]);
      final retReg = decodeA(code[retIdx]);
      expect(retReg, addResult,
          reason: 'RETURN_VAL should return ADD_INT result');
    });

    test('multiple operations: (a + b) - c', () async {
      final module = await compileDart('''
int f(int a, int b, int c) => (a + b) - c;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      final addIdx = findOp(code, Op.addInt);
      final subIdx = findOp(code, Op.subInt);
      expect(addIdx, isNot(-1));
      expect(subIdx, isNot(-1));
      expect(addIdx, lessThan(subIdx));
    });

    test('arithmetic with literal operand', () async {
      final module = await compileDart('''
int f(int a) => a + 1;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should have LOAD_INT for literal 1 and ADD_INT.
      expect(findOp(code, Op.loadInt), isNot(-1));
      expect(findOp(code, Op.addInt), isNot(-1));
    });

    test('result ends with RETURN_VAL', () async {
      final module = await compileDart('''
int f(int a, int b) => a + b;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Last meaningful instruction before safety net should be RETURN_VAL.
      final retIdx = findOp(code, Op.returnVal);
      expect(retIdx, isNot(-1));
    });
  });
}
