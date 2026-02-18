import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('Global variable compilation', () {
    test('var x = 42 — module has globalCount > 0', () async {
      final module = await compileDart('''
var x = 42;
int main() => x;
''');
      expect(module.globalCount, greaterThan(0));
      expect(module.globalInitializerIds.length, module.globalCount);
    });

    test('StaticGet generates LOAD_GLOBAL', () async {
      final module = await compileDart('''
var x = 42;
int main() => x;
''');
      final main = findFunc(module, 'main');
      final code = main.bytecode;
      expect(findOp(code, Op.loadGlobal), isNot(-1),
          reason: 'LOAD_GLOBAL not found for top-level var access');
    });

    test('StaticSet generates STORE_GLOBAL', () async {
      final module = await compileDart('''
var x = 0;
void setX() { x = 1; }
int main() => 0;
''');
      final setX = findFunc(module, 'setX');
      final code = setX.bytecode;
      expect(findOp(code, Op.storeGlobal), isNot(-1),
          reason: 'STORE_GLOBAL not found for top-level var assignment');
    });

    test('int global round-trip: BOX + STORE then LOAD + UNBOX', () async {
      final module = await compileDart('''
var x = 42;
int main() => x;
''');
      final main = findFunc(module, 'main');
      final code = main.bytecode;
      // Should have LOAD_GLOBAL followed by UNBOX_INT
      final loadIdx = findOp(code, Op.loadGlobal);
      expect(loadIdx, isNot(-1));
      final unboxIdx = findOp(code, Op.unboxInt, start: loadIdx + 1);
      expect(unboxIdx, isNot(-1),
          reason: 'UNBOX_INT should follow LOAD_GLOBAL for int field');
    });

    test('initializer compiled as separate function', () async {
      final module = await compileDart('''
var x = 42;
int main() => x;
''');
      // The initializer should be a separate function
      final initFuncId = module.globalInitializerIds[0];
      expect(initFuncId, greaterThanOrEqualTo(0));
      // The initializer function should contain STORE_GLOBAL
      final initFunc = module.functions[initFuncId];
      expect(findOp(initFunc.bytecode, Op.storeGlobal), isNot(-1),
          reason: 'Initializer should contain STORE_GLOBAL');
    });
  });

  group('Global variable end-to-end execution', () {
    test('var x = 42; main() => x', () async {
      final module = await compileDart('''
var x = 42;
int main() => x;
''');
      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 42);
    });

    test('var x = 0; setX sets x = 1; main reads x', () async {
      final module = await compileDart('''
var x = 0;
void setX() { x = 1; }
int main() { setX(); return x; }
''');
      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 1);
    });

    test('int compute() => 42; var x = compute(); main() => x', () async {
      final module = await compileDart('''
int compute() => 42;
var x = compute();
int main() => x;
''');
      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 42);
    });

    test('multiple globals', () async {
      final module = await compileDart('''
var a = 10;
var b = 20;
int add(int x, int y) => x + y;
int main() => add(a, b);
''');
      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.valueStack.readInt(0), 30);
    });

    test('string global', () async {
      final module = await compileDart('''
var greeting = 'hello';
String main() => greeting;
''');
      final interp = DarticInterpreter();
      interp.execute(module);
      expect(interp.refStack.read(0), 'hello');
    });
  });
}
