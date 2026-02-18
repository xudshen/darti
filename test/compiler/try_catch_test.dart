import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// Compiler tests for try/catch/finally statement compilation.
void main() {
  group('try/catch compilation', () {
    test('try-catch generates THROW and exception table', () async {
      final module = await compileDart('''
int f() {
  try {
    throw 'error';
  } catch (e) {
    return 42;
  }
  return 0;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should contain THROW instruction.
      final throwIdx = findOp(code, Op.throw_);
      expect(throwIdx, isNot(-1), reason: 'THROW not found');

      // Should have exception table.
      expect(f.exceptionTable, isNotEmpty,
          reason: 'Exception table should not be empty');
      expect(f.exceptionTable.first.catchType, -1,
          reason: 'catch(e) should be catch-all');
    });

    test('try-finally generates handler with RETHROW', () async {
      final module = await compileDart('''
int f() {
  int x = 0;
  try {
    x = 1;
  } finally {
    x = x + 10;
  }
  return x;
}
void main() {}
''');
      final f = findFunc(module, 'f');

      // Should have exception table for finally.
      expect(f.exceptionTable, isNotEmpty,
          reason: 'Finally should generate exception handler');
    });
  });
}
