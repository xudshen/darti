import 'dart:io';
import 'dart:typed_data';

import 'package:dartic/src/compiler/bytecode_emitter.dart';
import 'package:dartic/src/compiler/compiler.dart';
import 'package:kernel/ast.dart' as ir;
import 'package:kernel/binary/ast_from_binary.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeEmitter', () {
    test('starts with PC at 0', () {
      final emitter = BytecodeEmitter();
      expect(emitter.currentPC, 0);
    });

    test('emit adds instruction and advances PC', () {
      final emitter = BytecodeEmitter();
      emitter.emit(0xDEADBEEF);
      expect(emitter.currentPC, 1);
      emitter.emit(0xCAFEBABE);
      expect(emitter.currentPC, 2);
    });

    test('toUint32List returns emitted instructions in order', () {
      final emitter = BytecodeEmitter();
      emitter.emit(0x01);
      emitter.emit(0x02);
      emitter.emit(0x03);
      final result = emitter.toUint32List();
      expect(result, isA<Uint32List>());
      expect(result, [0x01, 0x02, 0x03]);
    });

    test('patchJump modifies instruction at given offset', () {
      final emitter = BytecodeEmitter();
      emitter.emit(0x01);
      emitter.emit(0x02); // will be patched
      emitter.emit(0x03);
      emitter.patchJump(1, 0xFF);
      final result = emitter.toUint32List();
      expect(result[0], 0x01);
      expect(result[1], 0xFF);
      expect(result[2], 0x03);
    });

    test('emitPlaceholder reserves slot and returns offset', () {
      final emitter = BytecodeEmitter();
      emitter.emit(0x01);
      final offset = emitter.emitPlaceholder();
      expect(offset, 1);
      emitter.emit(0x03);
      expect(emitter.currentPC, 3);
      // Patch the placeholder
      emitter.patchJump(offset, 0xAA);
      expect(emitter.toUint32List()[1], 0xAA);
    });

    test('empty emitter produces empty Uint32List', () {
      final emitter = BytecodeEmitter();
      expect(emitter.toUint32List(), isEmpty);
    });
  });

  group('DarticCompiler skeleton', () {
    late Directory tempDir;
    late ir.Component component;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('dartic_test_');
      final dartFile = File('${tempDir.path}/test_main.dart');
      await dartFile.writeAsString('void main() {}\n');

      final dillPath = '${tempDir.path}/test_main.dill';
      final result = await Process.run(
        'fvm',
        ['dart', 'compile', 'kernel', dartFile.path, '-o', dillPath],
      );
      if (result.exitCode != 0) {
        fail('Failed to compile .dill: ${result.stderr}');
      }

      final bytes = File(dillPath).readAsBytesSync();
      component = ir.Component();
      BinaryBuilder(bytes).readComponent(component);
    });

    tearDownAll(() async {
      await tempDir.delete(recursive: true);
    });

    test('Component contains user library with main procedure', () {
      final userLibs = component.libraries
          .where((lib) => !lib.importUri.isScheme('dart'))
          .toList();
      expect(userLibs, isNotEmpty);

      final mainProcs = userLibs.first.procedures
          .where((p) => p.name.text == 'main')
          .toList();
      expect(mainProcs, hasLength(1));
      expect(mainProcs.first.function, isNotNull);
    });

    test('Component.mainMethod points to main', () {
      expect(component.mainMethod, isNotNull);
      expect(component.mainMethod!.name.text, 'main');
    });

    test('compile produces DarticModule with correct structure', () {
      final compiler = DarticCompiler(component);
      final module = compiler.compile();

      // Module should have at least one function (main).
      expect(module.functions, isNotEmpty);

      // Entry point funcId should be valid.
      expect(module.entryFuncId, greaterThanOrEqualTo(0));
      expect(module.entryFuncId, lessThan(module.functions.length));

      // The entry function should have paramCount=0 for void main().
      final entryFunc = module.functions[module.entryFuncId];
      expect(entryFunc.paramCount, 0);
    });

    test('compile with add function finds multiple user procedures', () async {
      // Compile a file with two functions.
      final dartFile = File('${tempDir.path}/test_add.dart');
      await dartFile.writeAsString('''
int add(int a, int b) => a + b;
int main() => add(1, 2);
''');

      final dillPath = '${tempDir.path}/test_add.dill';
      final result = await Process.run(
        'fvm',
        ['dart', 'compile', 'kernel', dartFile.path, '-o', dillPath],
      );
      if (result.exitCode != 0) {
        fail('Failed to compile .dill: ${result.stderr}');
      }

      final bytes = File(dillPath).readAsBytesSync();
      final comp = ir.Component();
      BinaryBuilder(bytes).readComponent(comp);

      final compiler = DarticCompiler(comp);
      final module = compiler.compile();

      // Should have at least 2 functions (add + main).
      expect(module.functions.length, greaterThanOrEqualTo(2));

      // Entry function should exist and be valid.
      expect(module.entryFuncId, greaterThanOrEqualTo(0));
      expect(module.entryFuncId, lessThan(module.functions.length));
    });
  });
}
