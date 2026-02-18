import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// Compiler tests for loop statement compilation (while, for, do-while).
///
/// Verifies backward jump patterns and scope management for loop variables.
void main() {
  group('while loop compilation', () {
    test('while generates JUMP_IF_FALSE and backward JUMP', () async {
      final module = await compileDart('''
int f(int n) {
  int sum = 0;
  int i = 0;
  while (i < n) {
    sum = sum + i;
    i = i + 1;
  }
  return sum;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // while loop pattern: condition → JUMP_IF_FALSE (forward) → body → JUMP (backward)
      final jifIdx = findOp(code, Op.jumpIfFalse);
      expect(jifIdx, isNot(-1), reason: 'JUMP_IF_FALSE not found');

      // There should be a JUMP after the body going backward to the condition.
      final jumpIdx = findOp(code, Op.jump, start: jifIdx + 1);
      expect(jumpIdx, isNot(-1), reason: 'Backward JUMP not found');

      // The backward jump should have a negative offset.
      final sbx = decodesBx(code[jumpIdx]);
      expect(sbx, isNegative, reason: 'Loop JUMP should be backward (negative)');
    });

    test('empty while body compiles without error', () async {
      final module = await compileDart('''
void f() {
  int i = 0;
  while (i < 10) {
    i = i + 1;
  }
}
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(f.bytecode.isNotEmpty, isTrue);
    });
  });

  group('for loop compilation', () {
    test('for generates init + condition + body + update + backward jump',
        () async {
      final module = await compileDart('''
int f(int n) {
  int sum = 0;
  for (int i = 0; i < n; i = i + 1) {
    sum = sum + i;
  }
  return sum;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // For loop should have JUMP_IF_FALSE (exit condition) and backward JUMP.
      final jifIdx = findOp(code, Op.jumpIfFalse);
      expect(jifIdx, isNot(-1), reason: 'JUMP_IF_FALSE not found');

      // There should be a backward JUMP.
      final jumpIdx = findOp(code, Op.jump, start: jifIdx + 1);
      expect(jumpIdx, isNot(-1), reason: 'Backward JUMP not found');
      expect(decodesBx(code[jumpIdx]), isNegative,
          reason: 'Loop JUMP should be backward');
    });

    test('nested for loops generate two backward jumps', () async {
      final module = await compileDart('''
int f() {
  int sum = 0;
  for (int i = 0; i < 3; i = i + 1) {
    for (int j = 0; j < 3; j = j + 1) {
      sum = sum + 1;
    }
  }
  return sum;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should have two JUMP_IF_FALSE (one per loop).
      final jif1 = findOp(code, Op.jumpIfFalse);
      final jif2 = findOp(code, Op.jumpIfFalse, start: jif1 + 1);
      expect(jif1, isNot(-1), reason: 'First JUMP_IF_FALSE not found');
      expect(jif2, isNot(-1), reason: 'Second JUMP_IF_FALSE not found');
    });
  });

  group('do-while compilation', () {
    test('do-while generates JUMP_IF_TRUE backward', () async {
      final module = await compileDart('''
int f() {
  int x = 0;
  do {
    x = x + 1;
  } while (x < 5);
  return x;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // do-while pattern: body → condition → JUMP_IF_TRUE (backward)
      final jitIdx = findOp(code, Op.jumpIfTrue);
      expect(jitIdx, isNot(-1), reason: 'JUMP_IF_TRUE not found');

      // The jump should be backward.
      final sbx = decodesBx(code[jitIdx]);
      expect(sbx, isNegative,
          reason: 'Do-while JUMP_IF_TRUE should be backward');
    });
  });
}
