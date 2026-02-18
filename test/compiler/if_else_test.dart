import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// Compiler tests for if/else statement compilation.
///
/// Verifies the bytecode pattern:
///   compile condition → JUMP_IF_FALSE to else → compile then →
///   JUMP to end → backpatch else → compile else → backpatch end
void main() {
  group('if/else compilation', () {
    test('single if (no else) generates JUMP_IF_FALSE', () async {
      final module = await compileDart('''
int f(int x) {
  if (x > 0) {
    return 1;
  }
  return 0;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should contain GT_INT (condition) followed by JUMP_IF_FALSE.
      final gtIdx = findOp(code, Op.gtInt);
      expect(gtIdx, isNot(-1), reason: 'GT_INT not found');

      final jifIdx = findOp(code, Op.jumpIfFalse, start: gtIdx);
      expect(jifIdx, isNot(-1), reason: 'JUMP_IF_FALSE not found after GT_INT');
    });

    test('if/else generates JUMP_IF_FALSE and JUMP', () async {
      final module = await compileDart('''
int f(int x) {
  if (x > 0) {
    return 1;
  } else {
    return -1;
  }
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Pattern: condition → JUMP_IF_FALSE → then body → JUMP → else body
      final jifIdx = findOp(code, Op.jumpIfFalse);
      expect(jifIdx, isNot(-1), reason: 'JUMP_IF_FALSE not found');

      // There should be a JUMP (unconditional) in the then branch to skip else.
      final jumpIdx = findOp(code, Op.jump, start: jifIdx + 1);
      expect(jumpIdx, isNot(-1), reason: 'JUMP not found after JUMP_IF_FALSE');

      // The JUMP should come after at least one RETURN in the then branch.
      final retIdx = findOp(code, Op.returnVal, start: jifIdx + 1);
      expect(retIdx, isNot(-1), reason: 'RETURN_VAL not found in then branch');
    });

    test('nested if/else generates multiple JUMP_IF_FALSE', () async {
      final module = await compileDart('''
int f(int x) {
  if (x > 0) {
    if (x > 10) {
      return 2;
    }
    return 1;
  }
  return 0;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should have two JUMP_IF_FALSE instructions for nested ifs.
      final jif1 = findOp(code, Op.jumpIfFalse);
      expect(jif1, isNot(-1), reason: 'First JUMP_IF_FALSE not found');

      final jif2 = findOp(code, Op.jumpIfFalse, start: jif1 + 1);
      expect(jif2, isNot(-1), reason: 'Second JUMP_IF_FALSE not found');
    });

    test('if body block scope: variable declared in if block', () async {
      // Variables declared in if blocks should use block scope.
      final module = await compileDart('''
int f(int x) {
  if (x > 0) {
    int y = x + 1;
    return y;
  }
  return 0;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      // Should compile without errors — variable y is in block scope.
      expect(f.bytecode.isNotEmpty, isTrue);
    });
  });
}
