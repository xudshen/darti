import 'dart:typed_data';

import 'package:dartic/src/bytecode/deserializer.dart';
import 'package:dartic/src/bytecode/format.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/serializer.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// End-to-end roundtrip tests: Dart source → Kernel → compile → serialize →
/// deserialize → execute.
///
/// This is the Phase 1 final milestone. A passing roundtrip proves that
/// the entire pipeline (ISA + object model + compiler + module format +
/// execution engine) is closed and self-consistent.
void main() {
  group('module roundtrip', () {
    test('add(1, 2) returns 3 after roundtrip', () async {
      final result = await _compileSerializeDeserializeRun('''
int add(int a, int b) => a + b;
int main() => add(1, 2);
''');
      expect(result, 3);
    });

    test('nested calls survive roundtrip', () async {
      final result = await _compileSerializeDeserializeRun('''
int add(int a, int b) => a + b;
int square(int x) => x * x;
int main() => add(square(2), square(3));
''');
      expect(result, 13);
    });

    test('constant pool contents match after roundtrip', () async {
      final original = await compileDart('''
int add(int a, int b) => a + b;
int main() => add(1, 2);
''');
      final restored = _roundtrip(original);

      // Ints partition.
      expect(restored.constantPool.ints, original.constantPool.ints);

      // Doubles partition.
      expect(restored.constantPool.doubles, original.constantPool.doubles);

      // Names partition.
      expect(restored.constantPool.names, original.constantPool.names);

      // Refs partition.
      expect(restored.constantPool.refs, original.constantPool.refs);
    });

    test('bytecode is byte-for-byte identical after roundtrip', () async {
      final original = await compileDart('''
int add(int a, int b) => a + b;
int square(int x) => x * x;
int main() => add(square(2), square(3));
''');
      final restored = _roundtrip(original);

      expect(restored.functions.length, original.functions.length);
      for (var i = 0; i < original.functions.length; i++) {
        final origFunc = original.functions[i];
        final restFunc = restored.functions[i];
        expect(restFunc.name, origFunc.name);
        expect(restFunc.funcId, origFunc.funcId);
        expect(restFunc.valueRegCount, origFunc.valueRegCount);
        expect(restFunc.refRegCount, origFunc.refRegCount);
        expect(restFunc.paramCount, origFunc.paramCount);
        expect(restFunc.bytecode, origFunc.bytecode,
            reason: 'bytecode mismatch for ${origFunc.name}');
      }
    });

    test('entry point is preserved after roundtrip', () async {
      final original = await compileDart('''
int f() => 42;
int main() => f();
''');
      final restored = _roundtrip(original);
      expect(restored.entryFuncId, original.entryFuncId);
    });

    test('tampered serialized data is detected by checksum', () async {
      final module = await compileDart('''
int main() => 42;
''');
      final bytes = DarticSerializer().serialize(module);

      // Tamper with a byte in the payload (after the 12-byte header).
      final tampered = Uint8List.fromList(bytes);
      tampered[DarbFormat.headerSize + 1] ^= 0xFF;

      expect(
        () => DarticDeserializer().deserialize(tampered),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('checksum'),
        )),
      );
    });
  });
}

/// Full pipeline: Dart source → .dill → compile → serialize → deserialize →
/// execute → return main's int result.
Future<int> _compileSerializeDeserializeRun(String source) async {
  final module = await compileDart(source);
  final restored = _roundtrip(module);
  return _executeAndReadResult(restored);
}

/// Serialize then deserialize a module.
DarticModule _roundtrip(DarticModule module) {
  final bytes = DarticSerializer().serialize(module);
  return DarticDeserializer().deserialize(bytes);
}

/// Executes a module and reads the int result from the root frame.
int _executeAndReadResult(DarticModule module) {
  final interp = DarticInterpreter();
  interp.execute(module);
  return interp.valueStack.readInt(0);
}
