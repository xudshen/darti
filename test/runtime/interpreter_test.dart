import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/error.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

/// Helper: builds a single-function DarticModule from bytecode.
DarticModule _module(
  Uint32List bytecode, {
  int valueRegCount = 0,
  int refRegCount = 0,
  int paramCount = 0,
}) {
  final proto = DarticFuncProto(
    funcId: 0,
    bytecode: bytecode,
    valueRegCount: valueRegCount,
    refRegCount: refRegCount,
    paramCount: paramCount,
  );
  return DarticModule(
    functions: [proto],
    constantPool: ConstantPool(),
    entryFuncId: 0,
  );
}

void main() {
  late DarticInterpreter interpreter;

  setUp(() {
    interpreter = DarticInterpreter();
  });

  group('HALT', () {
    test('stops execution immediately', () {
      final module = _module(
        Uint32List.fromList([encodeAx(Opcode.halt.code, 0)]),
      );
      // Should complete without error.
      interpreter.execute(module);
    });

    test('pops the root frame from CallStack', () {
      final module = _module(
        Uint32List.fromList([encodeAx(Opcode.halt.code, 0)]),
        valueRegCount: 4,
        refRegCount: 2,
      );
      interpreter.execute(module);

      expect(interpreter.callStack.depth, 0);
      expect(interpreter.valueStack.sp, 0);
      expect(interpreter.refStack.sp, 0);
    });
  });

  group('NOP', () {
    test('is skipped without side effects', () {
      final module = _module(
        Uint32List.fromList([
          encodeABC(Opcode.nop.code, 0, 0, 0),
          encodeAx(Opcode.halt.code, 0),
        ]),
      );
      interpreter.execute(module);
    });

    test('multiple NOPs advance PC correctly', () {
      final module = _module(
        Uint32List.fromList([
          encodeABC(Opcode.nop.code, 0, 0, 0),
          encodeABC(Opcode.nop.code, 0, 0, 0),
          encodeABC(Opcode.nop.code, 0, 0, 0),
          encodeAx(Opcode.halt.code, 0),
        ]),
      );
      // Reaches HALT after 3 NOPs — no error.
      interpreter.execute(module);
    });
  });

  group('illegal opcode', () {
    test('throws DarticError for reserved opcode', () {
      final module = _module(
        // 0xA8 is in the reserved/superinstruction range.
        Uint32List.fromList([encodeABC(0xA8, 0, 0, 0)]),
      );
      expect(
        () => interpreter.execute(module),
        throwsA(isA<DarticError>()),
      );
    });

    test('error message contains the opcode value', () {
      final module = _module(
        Uint32List.fromList([encodeABC(0xB0, 0, 0, 0)]),
      );
      expect(
        () => interpreter.execute(module),
        throwsA(
          isA<DarticError>().having(
            (e) => e.message,
            'message',
            contains('0xb0'),
          ),
        ),
      );
    });
  });

  group('fuel', () {
    test('exhaustion stops execution without error', () {
      interpreter = DarticInterpreter(fuelBudget: 3);
      // 10 NOPs + HALT — fuel runs out well before HALT.
      final instrs = List.generate(
        10,
        (_) => encodeABC(Opcode.nop.code, 0, 0, 0),
      );
      instrs.add(encodeAx(Opcode.halt.code, 0));

      final module = _module(
        Uint32List.fromList(instrs),
        valueRegCount: 2,
        refRegCount: 1,
      );

      // No exception thrown.
      interpreter.execute(module);

      // Frame is still alive (HALT was not reached).
      expect(interpreter.callStack.depth, 1);
      expect(interpreter.valueStack.sp, 2);
      expect(interpreter.refStack.sp, 1);
    });
  });
}
