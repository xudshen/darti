import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

/// Runtime tests for exception dispatch using hand-crafted bytecode.
///
/// Tests the interpreter's THROW/RETHROW opcodes and exception handler table
/// matching + stack unwinding.
void main() {
  group('THROW dispatch', () {
    test('THROW matches catch-all handler and jumps to handlerPC', () {
      // Bytecode:
      //   0: LOAD_CONST r0, "error"    ; exception object
      //   1: THROW r0                  ; throw
      //   2: HALT                      ; unreachable
      //   3: LOAD_INT v0, 42           ; handler: set result = 42
      //   4: HALT                      ; exit
      final cp = ConstantPool();
      final errIdx = cp.addRef('error');

      final code = Uint32List.fromList([
        encodeABx(Op.loadConst, 0, errIdx), // 0: load "error" → r0
        encodeABC(Op.throw_, 0, 0, 0), // 1: throw r0
        encodeAx(Op.halt, 0), // 2: unreachable
        encodeAsBx(Op.loadInt, 0, 42), // 3: handler → v0 = 42
        encodeAx(Op.halt, 0), // 4: exit
      ]);

      final func = DarticFuncProto(
        funcId: 0,
        bytecode: code,
        valueRegCount: 1,
        refRegCount: 1,
        paramCount: 0,
        exceptionTable: [
          ExceptionHandler(
            startPC: 0,
            endPC: 2,
            handlerPC: 3,
            catchType: -1, // catch-all
            exceptionReg: 0, // write exception to r0
            stackTraceReg: -1, // no stackTrace binding
          ),
        ],
      );

      final module = DarticModule(
        functions: [func],
        constantPool: cp,
        entryFuncId: 0,
      );

      final interp = DarticInterpreter();
      interp.execute(module);

      // Handler set v0 = 42.
      expect(interp.valueStack.readInt(0), 42);
    });

    test('THROW with no matching handler propagates to top level', () {
      // No exception table → THROW should throw a DarticError.
      final cp = ConstantPool();
      final errIdx = cp.addRef('unhandled');

      final code = Uint32List.fromList([
        encodeABx(Op.loadConst, 0, errIdx),
        encodeABC(Op.throw_, 0, 0, 0),
        encodeAx(Op.halt, 0),
      ]);

      final func = DarticFuncProto(
        funcId: 0,
        bytecode: code,
        valueRegCount: 0,
        refRegCount: 1,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [func],
        constantPool: cp,
        entryFuncId: 0,
      );

      final interp = DarticInterpreter();
      expect(() => interp.execute(module), throwsA(isA<String>()));
    });

    test('catch exception variable binding', () {
      // Throw "hello" → catch stores in exceptionReg r0 →
      // handler reads r0 and returns it.
      final cp = ConstantPool();
      final errIdx = cp.addRef('hello');

      final code = Uint32List.fromList([
        encodeABx(Op.loadConst, 0, errIdx), // 0: load "hello" → r0
        encodeABC(Op.throw_, 0, 0, 0), // 1: throw r0
        encodeAx(Op.halt, 0), // 2: unreachable
        // Handler: exception is in r0 (exceptionReg), just HALT.
        encodeAx(Op.halt, 0), // 3: handler exit
      ]);

      final func = DarticFuncProto(
        funcId: 0,
        bytecode: code,
        valueRegCount: 0,
        refRegCount: 1,
        paramCount: 0,
        exceptionTable: [
          ExceptionHandler(
            startPC: 0,
            endPC: 2,
            handlerPC: 3,
            catchType: -1,
            exceptionReg: 0,
            stackTraceReg: -1,
          ),
        ],
      );

      final module = DarticModule(
        functions: [func],
        constantPool: cp,
        entryFuncId: 0,
      );

      final interp = DarticInterpreter();
      interp.execute(module);

      // The exception 'hello' should be in refStack r0.
      expect(interp.refStack.read(0), 'hello');
    });

    test('stack depth restored on exception', () {
      // Push extra ref values, then throw. Handler should restore stack depth.
      final cp = ConstantPool();
      final errIdx = cp.addRef('error');

      final code = Uint32List.fromList([
        encodeABx(Op.loadConst, 0, errIdx), // 0: load error → r0
        encodeABx(Op.loadConst, 1, errIdx), // 1: load into r1 (extra ref)
        encodeABC(Op.throw_, 0, 0, 0), // 2: throw r0
        encodeAx(Op.halt, 0), // 3: unreachable
        encodeAsBx(Op.loadInt, 0, 99), // 4: handler → v0 = 99
        encodeAx(Op.halt, 0), // 5: exit
      ]);

      final func = DarticFuncProto(
        funcId: 0,
        bytecode: code,
        valueRegCount: 1,
        refRegCount: 2,
        paramCount: 0,
        exceptionTable: [
          ExceptionHandler(
            startPC: 0,
            endPC: 3,
            handlerPC: 4,
            catchType: -1,
            valStackDP: 0,
            refStackDP: 0,
            exceptionReg: 0,
            stackTraceReg: -1,
          ),
        ],
      );

      final module = DarticModule(
        functions: [func],
        constantPool: cp,
        entryFuncId: 0,
      );

      final interp = DarticInterpreter();
      interp.execute(module);

      expect(interp.valueStack.readInt(0), 99);
    });
  });
}
