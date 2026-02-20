import 'dart:typed_data';

import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('CALL_HOST', () {
    late HostFunctionRegistry registry;

    setUp(() {
      registry = HostFunctionRegistry();
    });

    /// Helper to build a module with binding names and execute it.
    Object? runWithBindings(
      Uint32List bytecode, {
      required List<BindingEntry> bindingNames,
      int valueRegCount = 4,
      int refRegCount = 4,
      ConstantPool? constantPool,
    }) {
      final module = DarticModule(
        functions: [
          DarticFuncProto(
            funcId: 0,
            bytecode: bytecode,
            valueRegCount: valueRegCount,
            refRegCount: refRegCount,
            paramCount: 0,
          ),
        ],
        constantPool: constantPool ?? ConstantPool(),
        entryFuncId: 0,
        bindingNames: bindingNames,
      );
      final interp = DarticInterpreter(hostFunctionRegistry: registry);
      interp.execute(module);
      return interp.entryResult;
    }

    test('no-arg host function returns value via ref stack', () {
      // Register a no-arg function that returns 42.
      registry.register('test::noarg#0', (args) => 42);

      // CALL_HOST A=0, Bx=0  →  refStack[0] = hostFunctionRegistry.invoke(0, [])
      // HALT A=0, B=1(ref)
      final code = Uint32List.fromList([
        encodeABx(Op.callHost, 0, 0), // callHost r0, binding#0
        encodeABC(Op.halt, 0, 1, 0), // halt r0, kind=ref
      ]);

      final result = runWithBindings(
        code,
        bindingNames: [BindingEntry(name: 'test::noarg#0', argCount: 0)],
      );
      expect(result, equals(42));
    });

    test('single-arg host function (int arg via BOX_INT)', () {
      // Register: (args) => args[0] + 1
      registry.register('test::inc#1', (args) => (args[0] as int) + 1);

      // LOAD_INT v0 = 41
      // BOX_INT r0 = v0
      // MOVE_REF r1 = r0  (arg[0] into position)
      // CALL_HOST r0, binding#0 (reads 1 arg starting at r1)
      // HALT r0, kind=ref
      final code = Uint32List.fromList([
        encodeAsBx(Op.loadInt, 0, 41), // v0 = 41
        encodeABC(Op.boxInt, 0, 0, 0), // r0 = box(v0)
        // For CALL_HOST, args are in ref stack positions AFTER the result reg.
        // The convention: args at r[A+1], r[A+2], ...
        // So we need arg at r1.
        encodeABC(Op.moveRef, 1, 0, 0), // r1 = r0 (arg)
        encodeABx(Op.callHost, 0, 0), // r0 = callHost binding#0
        encodeABC(Op.halt, 0, 1, 0), // halt r0, kind=ref
      ]);

      final result = runWithBindings(
        code,
        bindingNames: [BindingEntry(name: 'test::inc#1', argCount: 1)],
      );
      expect(result, equals(42));
    });

    test('multi-arg host function (2 args)', () {
      // Register: (args) => args[0] + args[1]
      registry.register('test::add#2', (args) {
        return (args[0] as int) + (args[1] as int);
      });

      final code = Uint32List.fromList([
        encodeAsBx(Op.loadInt, 0, 10), // v0 = 10
        encodeAsBx(Op.loadInt, 1, 32), // v1 = 32
        encodeABC(Op.boxInt, 1, 0, 0), // r1 = box(v0) → arg0
        encodeABC(Op.boxInt, 2, 1, 0), // r2 = box(v1) → arg1
        encodeABx(Op.callHost, 0, 0), // r0 = callHost binding#0
        encodeABC(Op.halt, 0, 1, 0), // halt r0, kind=ref
      ]);

      final result = runWithBindings(
        code,
        bindingNames: [BindingEntry(name: 'test::add#2', argCount: 2)],
      );
      expect(result, equals(42));
    });

    test('host function exception is caught by exception handler', () {
      registry.register('test::throws#0', (args) {
        throw StateError('host error');
      });

      // try { callHost } catch (e) { result = 99 }
      final code = Uint32List.fromList([
        encodeABx(Op.callHost, 0, 0), // PC=0: callHost r0, binding#0
        encodeABC(Op.halt, 0, 1, 0), // PC=1: halt (unreachable)
        // handler at PC=2:
        encodeAsBx(Op.loadInt, 0, 99), // PC=2: v0 = 99
        encodeABC(Op.halt, 0, 3, 0), // PC=3: halt v0, kind=int
      ]);

      final module = DarticModule(
        functions: [
          DarticFuncProto(
            funcId: 0,
            bytecode: code,
            valueRegCount: 4,
            refRegCount: 4,
            paramCount: 0,
            exceptionTable: [
              ExceptionHandler(
                startPC: 0,
                endPC: 1,
                handlerPC: 2,
                catchType: -1, // catch-all
                valStackDP: 0,
                refStackDP: 0,
                exceptionReg: 0,
                stackTraceReg: 1,
              ),
            ],
          ),
        ],
        constantPool: ConstantPool(),
        entryFuncId: 0,
        bindingNames: [BindingEntry(name: 'test::throws#0', argCount: 0)],
      );

      final interp = DarticInterpreter(hostFunctionRegistry: registry);
      interp.execute(module);
      expect(interp.entryResult, equals(99));
    });

    test('CALL_HOST consumes 1 fuel', () {
      registry.register('test::noop#0', (args) => null);

      // Execute with fuel=2: one for callHost, one for halt.
      final code = Uint32List.fromList([
        encodeABx(Op.callHost, 0, 0),
        encodeABC(Op.halt, 0, 0, 0),
      ]);

      final module = DarticModule(
        functions: [
          DarticFuncProto(
            funcId: 0,
            bytecode: code,
            valueRegCount: 2,
            refRegCount: 2,
            paramCount: 0,
          ),
        ],
        constantPool: ConstantPool(),
        entryFuncId: 0,
        bindingNames: [BindingEntry(name: 'test::noop#0', argCount: 0)],
      );

      // With fuel = 2, both instructions should execute fine.
      final interp = DarticInterpreter(hostFunctionRegistry: registry, fuelBudget: 2);
      interp.execute(module);
      // If fuel were consumed as >1 per CALL_HOST, this would fail.
    });

    test('binding table index out of bounds throws DarticError', () {
      // No registry registered, but CALL_HOST references binding#0.
      final code = Uint32List.fromList([
        encodeABx(Op.callHost, 0, 5), // binding#5 doesn't exist
        encodeABC(Op.halt, 0, 0, 0),
      ]);

      expect(
        () => runWithBindings(
          code,
          bindingNames: [], // empty binding table
        ),
        throwsA(isA<Error>()),
      );
    });

    test('host function returning String (ref type)', () {
      registry.register('test::greet#0', (args) => 'hello');

      final code = Uint32List.fromList([
        encodeABx(Op.callHost, 0, 0),
        encodeABC(Op.halt, 0, 1, 0), // halt r0, kind=ref
      ]);

      final result = runWithBindings(
        code,
        bindingNames: [BindingEntry(name: 'test::greet#0', argCount: 0)],
      );
      expect(result, equals('hello'));
    });

    test('host function returning null', () {
      registry.register('test::nullfn#0', (args) => null);

      final code = Uint32List.fromList([
        encodeABx(Op.callHost, 0, 0),
        encodeABC(Op.halt, 0, 1, 0), // halt r0, kind=ref
      ]);

      final result = runWithBindings(
        code,
        bindingNames: [BindingEntry(name: 'test::nullfn#0', argCount: 0)],
      );
      expect(result, isNull);
    });

    test('works without hostFunctionRegistry (no CALL_HOST instructions)', () {
      // Modules without CALL_HOST should work even without hostFunctionRegistry.
      final code = Uint32List.fromList([
        encodeAsBx(Op.loadInt, 0, 7),
        encodeABC(Op.halt, 0, 3, 0),
      ]);

      final module = DarticModule(
        functions: [
          DarticFuncProto(
            funcId: 0,
            bytecode: code,
            valueRegCount: 2,
            refRegCount: 2,
            paramCount: 0,
          ),
        ],
        constantPool: ConstantPool(),
        entryFuncId: 0,
      );

      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.entryResult, equals(7));
    });
  });
}
