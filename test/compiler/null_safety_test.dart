import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/error.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('NullCheck compilation', () {
    test('x! on non-null generates NULL_CHECK', () async {
      final module = await compileDart('''
String f(String? x) => x!;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;
      expect(findOp(code, Op.nullCheck), isNot(-1),
          reason: 'NULL_CHECK not found for x! operator');
    });

    test('x! on nullable int generates NULL_CHECK', () async {
      final module = await compileDart('''
int f(int? x) => x!;
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;
      expect(findOp(code, Op.nullCheck), isNot(-1),
          reason: 'NULL_CHECK not found for int? x! operator');
    });
  });

  group('NullCheck end-to-end execution', () {
    test('non-null value passes null check', () async {
      final module = await compileDart('''
String identity(String? x) => x!;
String main() => identity('hello');
''');
      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.refStack.read(0), 'hello');
    });

    test('null value triggers null check error', () async {
      final module = await compileDart('''
String identity(String? x) => x!;
String main() => identity(null);
''');
      final interp = DarticInterpreter();
      expect(
        () => interp.execute(module),
        throwsA(isA<DarticError>().having(
          (e) => e.message,
          'message',
          contains('Null check'),
        )),
      );
    });

    test('null check with EqualsNull combined (x == null already tested in 2.1.1)',
        () async {
      // Verify that x == null and x! coexist correctly.
      final module = await compileDart('''
bool isNull(Object? x) => x == null;
String force(String? x) => x!;
int main() => 0;
''');
      // Just check compilation succeeds and both patterns are present.
      final isNullF = findFunc(module, 'isNull');
      expect(findOp(isNullF.bytecode, Op.jumpIfNnull), isNot(-1));
      final forceF = findFunc(module, 'force');
      expect(findOp(forceF.bytecode, Op.nullCheck), isNot(-1));
    });
  });
}
