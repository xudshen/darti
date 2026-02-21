import 'dart:typed_data';

import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/bytecode/serializer.dart';
import 'package:dartic/src/runtime/error.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:dartic/src/sandbox/load_error.dart';
import 'package:test/test.dart';

import '../helpers/module_helper.dart';

void main() {
  group('loadAndVerify pipeline', () {
    group('format error rejection', () {
      test('wrong magic bytes throws DarticLoadError', () {
        // Construct bytes with wrong magic (0xDEADBEEF instead of 0x44415242).
        final bytes = Uint8List(12);
        final view = ByteData.view(bytes.buffer);
        view.setUint32(0, 0xDEADBEEF, Endian.little);
        view.setUint32(4, 1, Endian.little); // version
        view.setUint32(8, 0, Endian.little); // checksum (irrelevant)

        final interp = DarticInterpreter();
        expect(
          () => interp.loadAndVerify(bytes),
          throwsA(isA<DarticLoadError>()),
        );
      });

      test('truncated file throws DarticLoadError', () {
        final bytes = Uint8List(4); // Too short for header
        final interp = DarticInterpreter();
        expect(
          () => interp.loadAndVerify(bytes),
          throwsA(isA<DarticLoadError>()),
        );
      });
    });

    group('checksum tampering detection', () {
      test('modified payload byte triggers CRC mismatch', () {
        // Build a valid module, serialize it, then tamper with the payload.
        final code = Uint32List.fromList([
          encodeAx(Op.halt, 0),
        ]);
        final module = buildModule(code, valueRegCount: 1, refRegCount: 1);
        final validBytes = DarticSerializer().serialize(module);

        // Tamper: flip a bit in the payload area (after 12-byte header).
        final tampered = Uint8List.fromList(validBytes);
        if (tampered.length > 12) {
          tampered[12] ^= 0xFF;
        }

        final interp = DarticInterpreter();
        expect(
          () => interp.loadAndVerify(tampered),
          throwsA(isA<DarticLoadError>()),
        );
      });
    });

    group('structural verification', () {
      test('illegal opcode rejected', () {
        // Build a module with a reserved opcode (0xB0), serialize, load.
        // 0xFF is halt (valid), so use 0xB0 which is in the undefined gap.
        final code = Uint32List.fromList([
          encodeABC(0xB0, 0, 0, 0),
        ]);
        final module = buildModule(code, valueRegCount: 1, refRegCount: 1);
        final bytes = DarticSerializer().serialize(module);

        final interp = DarticInterpreter();
        expect(
          () => interp.loadAndVerify(bytes),
          throwsA(isA<DarticLoadError>().having(
            (e) => e.errors.any((msg) => msg.contains('opcode')),
            'has opcode error',
            isTrue,
          )),
        );
      });

      test('out-of-bounds jump rejected', () {
        // JUMP with offset that goes past code length.
        final code = Uint32List.fromList([
          encodeAsBx(Op.jump, 0, 999), // jumps way past end
        ]);
        final module = buildModule(code, valueRegCount: 1, refRegCount: 1);
        final bytes = DarticSerializer().serialize(module);

        final interp = DarticInterpreter();
        expect(
          () => interp.loadAndVerify(bytes),
          throwsA(isA<DarticLoadError>().having(
            (e) => e.errors.any((msg) => msg.toLowerCase().contains('jump')),
            'has jump error',
            isTrue,
          )),
        );
      });
    });

    group('bridge dependency checking', () {
      test('module with unregistered binding throws DarticLoadError', () {
        // Build a module that declares a binding not in the registry.
        final code = Uint32List.fromList([
          encodeAx(Op.halt, 0),
        ]);
        final proto = DarticFuncProto(
          funcId: 0,
          bytecode: code,
          valueRegCount: 1,
          refRegCount: 1,
          paramCount: 0,
        );
        final module = DarticModule(
          functions: [proto],
          constantPool: ConstantPool(),
          entryFuncId: 0,
          bindingNames: [
            BindingEntry(name: 'dart:core::::nonExistent#0', argCount: 0),
          ],
        );
        final bytes = DarticSerializer().serialize(module);

        // Interpreter with an empty registry (no bindings registered).
        final registry = HostFunctionRegistry();
        final interp = DarticInterpreter(hostFunctionRegistry: registry);
        expect(
          () => interp.loadAndVerify(bytes),
          throwsA(isA<DarticLoadError>().having(
            (e) => e.errors.any(
                (msg) => msg.contains('dart:core::::nonExistent#0')),
            'reports missing binding name',
            isTrue,
          )),
        );
      });

      test('module with no bindings passes bridge check', () {
        final code = Uint32List.fromList([
          encodeAx(Op.halt, 0),
        ]);
        final module = buildModule(code, valueRegCount: 1, refRegCount: 1);
        final bytes = DarticSerializer().serialize(module);

        final interp = DarticInterpreter();
        // Should not throw — no bindings to check.
        final verified = interp.loadAndVerify(bytes);
        expect(verified, isA<DarticModule>());
      });

      test('module with all bindings registered passes', () {
        final code = Uint32List.fromList([
          encodeAx(Op.halt, 0),
        ]);
        final proto = DarticFuncProto(
          funcId: 0,
          bytecode: code,
          valueRegCount: 1,
          refRegCount: 1,
          paramCount: 0,
        );
        final module = DarticModule(
          functions: [proto],
          constantPool: ConstantPool(),
          entryFuncId: 0,
          bindingNames: [
            BindingEntry(name: 'dart:core::::myFunc#1', argCount: 1),
          ],
        );
        final bytes = DarticSerializer().serialize(module);

        final registry = HostFunctionRegistry();
        registry.register('dart:core::::myFunc#1', (args) => null);
        final interp = DarticInterpreter(hostFunctionRegistry: registry);

        final verified = interp.loadAndVerify(bytes);
        expect(verified, isA<DarticModule>());
      });

      test('module with bindings but no registry throws DarticLoadError', () {
        final code = Uint32List.fromList([
          encodeAx(Op.halt, 0),
        ]);
        final proto = DarticFuncProto(
          funcId: 0,
          bytecode: code,
          valueRegCount: 1,
          refRegCount: 1,
          paramCount: 0,
        );
        final module = DarticModule(
          functions: [proto],
          constantPool: ConstantPool(),
          entryFuncId: 0,
          bindingNames: [
            BindingEntry(name: 'dart:core::::print#1', argCount: 1),
          ],
        );
        final bytes = DarticSerializer().serialize(module);

        // No registry provided.
        final interp = DarticInterpreter();
        expect(
          () => interp.loadAndVerify(bytes),
          throwsA(isA<DarticLoadError>().having(
            (e) => e.errors.any((msg) => msg.contains('HostFunctionRegistry')),
            'reports missing registry',
            isTrue,
          )),
        );
      });
    });

    group('resource limits end-to-end', () {
      test('infinite loop terminates via maxTotalFuel', () {
        final code = Uint32List.fromList([
          encodeAsBx(Op.jump, 0, -1),
        ]);
        final module = buildModule(code, valueRegCount: 1, refRegCount: 1);
        final bytes = DarticSerializer().serialize(module);

        final interp = DarticInterpreter(maxTotalFuel: 200);
        final verified = interp.loadAndVerify(bytes);
        expect(
          () => interp.execute(verified),
          throwsA(isA<FuelExhaustedError>()),
        );
      });

      test('infinite recursion terminates via call depth', () {
        // Function 0 calls itself.
        final code = Uint32List.fromList([
          encodeABx(Op.callStatic, 0, 0),
          encodeAx(Op.halt, 0),
        ]);
        final module = buildModule(code, valueRegCount: 4, refRegCount: 4);
        final bytes = DarticSerializer().serialize(module);

        final interp = DarticInterpreter();
        final verified = interp.loadAndVerify(bytes);
        expect(
          () => interp.execute(verified),
          throwsA(isA<DarticError>().having(
            (e) => e.message,
            'message',
            contains('call depth'),
          )),
        );
      });
    });

    group('normal end-to-end', () {
      test('valid module: load → verify → execute → correct result', () {
        // Simple program: LOAD_INT r0=42 → HALT r0 (int result).
        // HALT ABC: A=resultReg, B=StackKind.intDefault+1=3, C=0.
        final code = Uint32List.fromList([
          encodeAsBx(Op.loadInt, 0, 42),
          encodeABC(Op.halt, 0, 3, 0),
        ]);
        final module = buildModule(code, valueRegCount: 1, refRegCount: 1);
        final bytes = DarticSerializer().serialize(module);

        final interp = DarticInterpreter();
        final verified = interp.loadAndVerify(bytes);
        interp.execute(verified);
        expect(interp.entryResult, 42);
      });
    });

    group('error recovery', () {
      test('interpreter reusable after load error', () {
        // First: load bad bytes → DarticLoadError.
        final badBytes = Uint8List(4);
        final interp = DarticInterpreter();
        expect(
          () => interp.loadAndVerify(badBytes),
          throwsA(isA<DarticLoadError>()),
        );

        // Second: load and execute a valid module → success.
        final code = Uint32List.fromList([
          encodeAsBx(Op.loadInt, 0, 99),
          encodeABC(Op.halt, 0, 3, 0),
        ]);
        final module = buildModule(code, valueRegCount: 1, refRegCount: 1);
        final bytes = DarticSerializer().serialize(module);
        final verified = interp.loadAndVerify(bytes);
        interp.execute(verified);
        expect(interp.entryResult, 99);
      });

      test('interpreter reusable after execution error', () {
        // Load a valid infinite loop, execute with fuel limit → error.
        final loopCode = Uint32List.fromList([
          encodeAsBx(Op.jump, 0, -1),
        ]);
        final loopModule =
            buildModule(loopCode, valueRegCount: 1, refRegCount: 1);
        final loopBytes = DarticSerializer().serialize(loopModule);

        final interp = DarticInterpreter(maxTotalFuel: 100);
        final verified1 = interp.loadAndVerify(loopBytes);
        expect(
          () => interp.execute(verified1),
          throwsA(isA<FuelExhaustedError>()),
        );

        // Load and execute a normal module → success.
        final haltCode = Uint32List.fromList([
          encodeAsBx(Op.loadInt, 0, 7),
          encodeABC(Op.halt, 0, 3, 0),
        ]);
        final haltModule =
            buildModule(haltCode, valueRegCount: 1, refRegCount: 1);
        final haltBytes = DarticSerializer().serialize(haltModule);
        final verified2 = interp.loadAndVerify(haltBytes);
        interp.execute(verified2);
        expect(interp.entryResult, 7);
      });
    });
  });
}
