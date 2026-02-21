import 'dart:typed_data';

import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/error.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/module_helper.dart';

void main() {
  group('Error types', () {
    test('DarticInternalError has correct message and originalException', () {
      final original = StateError('something broke');
      final error = DarticInternalError('interpreter bug', original);
      expect(error.message, 'interpreter bug');
      expect(error.originalException, original);
      expect(error.toString(),
          contains('DarticInternalError: interpreter bug'));
      expect(error.toString(), contains('caused by:'));
    });

    test('DarticInternalError without originalException', () {
      final error = DarticInternalError('bug');
      expect(error.originalException, isNull);
      expect(error.toString(), 'DarticInternalError: bug');
      expect(error.toString(), isNot(contains('caused by:')));
    });

    test('DarticInternalError extends Error (not DarticError)', () {
      final error = DarticInternalError('bug');
      expect(error, isA<Error>());
      expect(error, isNot(isA<DarticError>()));
    });

    test('FuelExhaustedError extends DarticError', () {
      final error = FuelExhaustedError(100, 50);
      expect(error, isA<DarticError>());
      expect(error.totalConsumed, 100);
      expect(error.limit, 50);
      expect(error.message, contains('Fuel exhausted'));
      expect(error.message, contains('100'));
      expect(error.message, contains('50'));
    });

    test('ExecutionTimeoutError extends DarticError', () {
      final error = ExecutionTimeoutError(
        const Duration(milliseconds: 120),
        const Duration(milliseconds: 100),
      );
      expect(error, isA<DarticError>());
      expect(error.elapsed, const Duration(milliseconds: 120));
      expect(error.limit, const Duration(milliseconds: 100));
      expect(error.message, contains('Execution timeout'));
      expect(error.message, contains('120'));
      expect(error.message, contains('100'));
    });
  });

  group('maxTotalFuel', () {
    test('infinite loop exceeds fuel limit and throws FuelExhaustedError', () {
      // JUMP -1 at instruction 0: pc increments to 1, then += -1 → back to 0.
      final code = Uint32List.fromList([
        encodeAsBx(Op.jump, 0, -1),
      ]);
      final module = buildModule(code, valueRegCount: 1, refRegCount: 1);

      final interp = DarticInterpreter(maxTotalFuel: 100);
      expect(
        () => interp.execute(module),
        throwsA(isA<FuelExhaustedError>().having(
          (e) => e.totalConsumed,
          'totalConsumed',
          greaterThanOrEqualTo(100),
        )),
      );
    });

    test('normal program completes under maxTotalFuel', () {
      final code = Uint32List.fromList([
        encodeAx(Op.halt, 0),
      ]);
      final module = buildModule(code, valueRegCount: 1, refRegCount: 1);

      final interp = DarticInterpreter(maxTotalFuel: 100000);
      // Should not throw — HALT is reached before fuel exhaustion.
      interp.execute(module);
    });

    test('default maxTotalFuel is null (unlimited)', () {
      final code = Uint32List.fromList([
        encodeAx(Op.halt, 0),
      ]);
      final module = buildModule(code, valueRegCount: 1, refRegCount: 1);

      final interp = DarticInterpreter();
      expect(interp.maxTotalFuel, isNull);
      // Should complete without issue.
      interp.execute(module);
    });

    test('fuel limit just above consumption completes normally', () {
      // A program that HALTs after a few NOPs — should complete
      // well within the default fuelBudget.
      final code = Uint32List.fromList([
        encodeABC(Op.nop, 0, 0, 0),
        encodeABC(Op.nop, 0, 0, 0),
        encodeABC(Op.nop, 0, 0, 0),
        encodeAx(Op.halt, 0),
      ]);
      final module = buildModule(code, valueRegCount: 1, refRegCount: 1);

      // Set maxTotalFuel well above what 4 instructions need.
      final interp = DarticInterpreter(maxTotalFuel: 100000);
      interp.execute(module);
    });
  });

  group('executionTimeout', () {
    test('infinite loop exceeds timeout and throws ExecutionTimeoutError', () {
      final code = Uint32List.fromList([
        encodeAsBx(Op.jump, 0, -1),
      ]);
      final module = buildModule(code, valueRegCount: 1, refRegCount: 1);

      // Use a very short timeout. The loop must exhaust fuelBudget first
      // (since timeout is only checked at fuel boundaries), so set a small
      // fuelBudget to make fuel exhaustion happen quickly.
      final interp = DarticInterpreter(
        executionTimeout: const Duration(milliseconds: 10),
        fuelBudget: 1000,
      );
      expect(
        () => interp.execute(module),
        throwsA(isA<ExecutionTimeoutError>()),
      );
    });

    test('normal program completes within timeout', () {
      final code = Uint32List.fromList([
        encodeAx(Op.halt, 0),
      ]);
      final module = buildModule(code, valueRegCount: 1, refRegCount: 1);

      final interp = DarticInterpreter(
        executionTimeout: const Duration(seconds: 5),
      );
      interp.execute(module);
    });

    test('default executionTimeout is null (unlimited)', () {
      final interp = DarticInterpreter();
      expect(interp.executionTimeout, isNull);
    });
  });

  group('error recovery', () {
    test('interpreter reusable after FuelExhaustedError', () {
      final loopCode = Uint32List.fromList([
        encodeAsBx(Op.jump, 0, -1),
      ]);
      final loopModule =
          buildModule(loopCode, valueRegCount: 1, refRegCount: 1);

      final interp = DarticInterpreter(maxTotalFuel: 100);

      // First execution: fuel exhaustion.
      expect(
        () => interp.execute(loopModule),
        throwsA(isA<FuelExhaustedError>()),
      );

      // Verify stacks are clean after error.
      expect(interp.valueStack.sp, 0);
      expect(interp.refStack.sp, 0);
      expect(interp.callStack.depth, 0);

      // Second execution: normal program should succeed.
      final haltCode = Uint32List.fromList([
        encodeAx(Op.halt, 0),
      ]);
      final haltModule =
          buildModule(haltCode, valueRegCount: 1, refRegCount: 1);
      interp.execute(haltModule); // should not throw
    });

    test('interpreter reusable after ExecutionTimeoutError', () {
      final loopCode = Uint32List.fromList([
        encodeAsBx(Op.jump, 0, -1),
      ]);
      final loopModule =
          buildModule(loopCode, valueRegCount: 1, refRegCount: 1);

      final interp = DarticInterpreter(
        executionTimeout: const Duration(milliseconds: 10),
        fuelBudget: 1000,
      );

      // First execution: timeout.
      expect(
        () => interp.execute(loopModule),
        throwsA(isA<ExecutionTimeoutError>()),
      );

      // Second execution: normal program should succeed.
      final haltCode = Uint32List.fromList([
        encodeAx(Op.halt, 0),
      ]);
      final haltModule =
          buildModule(haltCode, valueRegCount: 1, refRegCount: 1);
      interp.execute(haltModule); // should not throw
    });

    test('stacks are properly reset after DarticError', () {
      // Use an illegal opcode to trigger DarticError.
      final badCode = Uint32List.fromList([
        encodeABC(0xB0, 0, 0, 0), // Reserved/unimplemented opcode
      ]);
      final badModule =
          buildModule(badCode, valueRegCount: 4, refRegCount: 4);

      final interp = DarticInterpreter();
      expect(
        () => interp.execute(badModule),
        throwsA(isA<DarticError>()),
      );

      // Stacks should be clean after error.
      expect(interp.valueStack.sp, 0);
      expect(interp.refStack.sp, 0);
      expect(interp.callStack.depth, 0);

      // Should be reusable.
      final haltCode = Uint32List.fromList([
        encodeAx(Op.halt, 0),
      ]);
      final haltModule =
          buildModule(haltCode, valueRegCount: 1, refRegCount: 1);
      interp.execute(haltModule);
    });
  });

  group('maxCallDepth (existing behavior)', () {
    test('deep recursion throws DarticError', () {
      // Function 0 calls itself (CALL_STATIC funcId=0), then HALTs.
      // The call depth check will trigger before HALT is ever reached.
      final code = Uint32List.fromList([
        encodeABx(Op.callStatic, 0, 0),
        encodeAx(Op.halt, 0),
      ]);
      // Need enough ref registers for the frame push.
      final module = buildModule(code, valueRegCount: 4, refRegCount: 4);

      final interp = DarticInterpreter();
      expect(
        () => interp.execute(module),
        throwsA(isA<DarticError>().having(
          (e) => e.message,
          'message',
          contains('call depth'),
        )),
      );
    });
  });

  group('combined limits', () {
    test('maxTotalFuel and executionTimeout both set — fuel hits first', () {
      final code = Uint32List.fromList([
        encodeAsBx(Op.jump, 0, -1),
      ]);
      final module = buildModule(code, valueRegCount: 1, refRegCount: 1);

      // Very low fuel limit, generous timeout.
      final interp = DarticInterpreter(
        maxTotalFuel: 100,
        executionTimeout: const Duration(seconds: 30),
      );
      expect(
        () => interp.execute(module),
        throwsA(isA<FuelExhaustedError>()),
      );
    });
  });
}
