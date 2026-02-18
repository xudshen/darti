import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('literal compilation', () {
    test('int literal (small) → LOAD_INT + RETURN_VAL', () async {
      final module = await compileDart('''
int f() => 42;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // LOAD_INT reg, 42
      expect(decodeOp(code[0]), Op.loadInt);
      expect(decodesBx(code[0]), 42);
      final reg = decodeA(code[0]);

      // RETURN_VAL reg
      expect(decodeOp(code[1]), Op.returnVal);
      expect(decodeA(code[1]), reg);
    });

    test('int literal (large) → LOAD_CONST_INT + RETURN_VAL', () async {
      final module = await compileDart('''
int f() => 100000;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // LOAD_CONST_INT reg, Bx
      expect(decodeOp(code[0]), Op.loadConstInt);
      final reg = decodeA(code[0]);
      final bx = decodeBx(code[0]);
      expect(module.constantPool.getInt(bx), 100000);

      // RETURN_VAL reg
      expect(decodeOp(code[1]), Op.returnVal);
      expect(decodeA(code[1]), reg);
    });

    test('int literal (negative small) → LOAD_INT + NEG_INT', () async {
      // The CFE represents `-5` as InstanceInvocation(IntLiteral(5), 'unary-')
      // rather than IntLiteral(-5). The compiler generates LOAD_INT + NEG_INT.
      final module = await compileDart('''
int f() => -5;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // LOAD_INT reg, 5
      expect(decodeOp(code[0]), Op.loadInt);
      expect(decodesBx(code[0]), 5);

      // NEG_INT result, reg
      expect(decodeOp(code[1]), Op.negInt);

      // RETURN_VAL result
      expect(decodeOp(code[2]), Op.returnVal);
    });

    test('bool literal true → LOAD_TRUE + RETURN_VAL', () async {
      final module = await compileDart('''
bool f() => true;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // LOAD_TRUE reg
      expect(decodeOp(code[0]), Op.loadTrue);
      final reg = decodeA(code[0]);

      // RETURN_VAL reg
      expect(decodeOp(code[1]), Op.returnVal);
      expect(decodeA(code[1]), reg);
    });

    test('bool literal false → LOAD_FALSE + RETURN_VAL', () async {
      final module = await compileDart('''
bool f() => false;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      expect(decodeOp(code[0]), Op.loadFalse);
      final reg = decodeA(code[0]);

      expect(decodeOp(code[1]), Op.returnVal);
      expect(decodeA(code[1]), reg);
    });

    test('string literal → LOAD_CONST + RETURN_REF', () async {
      final module = await compileDart('''
String f() => 'hello';
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // LOAD_CONST reg, Bx
      expect(decodeOp(code[0]), Op.loadConst);
      final reg = decodeA(code[0]);
      final bx = decodeBx(code[0]);
      expect(module.constantPool.getRef(bx), 'hello');

      // RETURN_REF reg
      expect(decodeOp(code[1]), Op.returnRef);
      expect(decodeA(code[1]), reg);
    });

    test('null literal → LOAD_NULL + RETURN_REF', () async {
      final module = await compileDart('''
Object? f() => null;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // LOAD_NULL reg
      expect(decodeOp(code[0]), Op.loadNull);
      final reg = decodeA(code[0]);

      // RETURN_REF reg
      expect(decodeOp(code[1]), Op.returnRef);
      expect(decodeA(code[1]), reg);
    });

    test('double literal → LOAD_CONST_DBL + RETURN_VAL', () async {
      final module = await compileDart('''
double f() => 3.14;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // LOAD_CONST_DBL reg, Bx
      expect(decodeOp(code[0]), Op.loadConstDbl);
      final reg = decodeA(code[0]);
      final bx = decodeBx(code[0]);
      expect(module.constantPool.getDouble(bx), 3.14);

      // RETURN_VAL reg
      expect(decodeOp(code[1]), Op.returnVal);
      expect(decodeA(code[1]), reg);
    });
  });
}
