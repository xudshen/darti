import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/error.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('NULL_CHECK opcode', () {
    test('non-null ref falls through normally', () {
      // Program:
      //   LOAD_CONST r0, 0   (load 'hello' from constant pool)
      //   NULL_CHECK r0      (should pass — 'hello' is non-null)
      //   HALT
      final cp = ConstantPool();
      final strIdx = cp.addRef('hello');

      final bytecode = Uint32List.fromList([
        encodeABx(Op.loadConst, 0, strIdx),
        encodeABC(Op.nullCheck, 0, 0, 0),
        encodeAx(Op.halt, 0),
      ]);

      final func = DarticFuncProto(
        funcId: 0,
        bytecode: bytecode,
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
      interp.execute(module);
      // Should complete without error.
      expect(interp.refStack.read(0), 'hello');
    });

    test('null ref throws DarticError', () {
      // Program:
      //   LOAD_NULL r0
      //   NULL_CHECK r0      (should throw — null!)
      //   HALT
      final bytecode = Uint32List.fromList([
        encodeABC(Op.loadNull, 0, 0, 0),
        encodeABC(Op.nullCheck, 0, 0, 0),
        encodeAx(Op.halt, 0),
      ]);

      final func = DarticFuncProto(
        funcId: 0,
        bytecode: bytecode,
        valueRegCount: 0,
        refRegCount: 1,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [func],
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

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

    test('null check on integer boxed value passes', () {
      // Program:
      //   LOAD_INT v0, 42
      //   BOX_INT r0, v0     (box int → ref)
      //   NULL_CHECK r0      (should pass — boxed 42 is non-null)
      //   HALT
      final bytecode = Uint32List.fromList([
        encodeAsBx(Op.loadInt, 0, 42),
        encodeABC(Op.boxInt, 0, 0, 0),
        encodeABC(Op.nullCheck, 0, 0, 0),
        encodeAx(Op.halt, 0),
      ]);

      final func = DarticFuncProto(
        funcId: 0,
        bytecode: bytecode,
        valueRegCount: 1,
        refRegCount: 1,
        paramCount: 0,
      );

      final module = DarticModule(
        functions: [func],
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

      final interp = DarticInterpreter();
      interp.execute(module);
      // Should complete without error.
    });
  });
}
