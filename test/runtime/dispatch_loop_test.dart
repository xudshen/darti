import 'dart:typed_data';
import 'package:darti/src/runtime/opcodes.dart';
import 'package:darti/src/runtime/types.dart';
import 'package:darti/src/runtime/host_bindings.dart';
import 'package:darti/src/runtime/dispatch_loop.dart';
import 'package:test/test.dart';

void main() {
  group('DispatchLoop', () {
    test('executes LOAD_INT + ADD_INT + RETURN_VAL', () {
      // Program: return 3 + 7
      final code = Uint32List.fromList([
        Instr.encodeAsBx(OpCode.loadInt, 0, 3),
        Instr.encodeAsBx(OpCode.loadInt, 1, 7),
        Instr.encodeABC(OpCode.addInt, 2, 0, 1),
        Instr.encodeABC(OpCode.returnVal, 2, 0, 0),
      ]);
      final func = FuncProto(
        name: 'test', paramCount: 0,
        refRegCount: 4, valRegCount: 4, bytecode: code,
      );
      final module = DartiModule(
        functions: [func], classes: [], constPool: [], entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: HostBindings());
      final result = runtime.execute(module);
      expect(result, equals(10));
    });

    test('executes for loop counting to 10', () {
      // Program: i=0; while(i<10) i++; return i
      final code = Uint32List.fromList([
        Instr.encodeAsBx(OpCode.loadInt, 0, 0),     // v[0] = i = 0
        Instr.encodeAsBx(OpCode.loadInt, 1, 10),    // v[1] = 10
        // LOOP (pc=2):
        Instr.encodeABC(OpCode.ltInt, 2, 0, 1),     // v[2] = (i < 10)
        Instr.encodeAsBx(OpCode.jumpIfFalse, 2, 2), // if false: skip to RETURN
        Instr.encodeABC(OpCode.addIntImm, 0, 0, 1), // i += 1
        Instr.encodeAsBx(OpCode.jump, 0, -4),       // back to LOOP(pc=2): offset = 2 - 5 - 1 = -4
        // RETURN (pc=6):
        Instr.encodeABC(OpCode.returnVal, 0, 0, 0), // return i
      ]);
      final func = FuncProto(
        name: 'test', paramCount: 0,
        refRegCount: 4, valRegCount: 4, bytecode: code,
      );
      final module = DartiModule(
        functions: [func], classes: [], constPool: [], entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: HostBindings());
      final result = runtime.execute(module);
      expect(result, equals(10));
    });

    test('NEW_INSTANCE + GET/SET_FIELD_VAL', () {
      final cls = ClassInfo(
        classId: 0, name: 'Foo',
        refFieldCount: 0, valueFieldCount: 1,
        fieldOffsets: {'x': 0}, fieldIsValue: {'x': true},
        methodTable: {},
      );
      final code = Uint32List.fromList([
        Instr.encodeABx(OpCode.newInstance, 0, 0),     // ref[0] = new Foo
        Instr.encodeAsBx(OpCode.loadInt, 0, 42),       // val[0] = 42
        Instr.encodeABC(OpCode.setFieldVal, 0, 0, 0),  // ref[0].valueFields[0] = val[0]
        Instr.encodeABC(OpCode.getFieldVal, 1, 0, 0),  // val[1] = ref[0].valueFields[0]
        Instr.encodeABC(OpCode.returnVal, 1, 0, 0),    // return val[1]
      ]);
      final func = FuncProto(
        name: 'test', paramCount: 0,
        refRegCount: 4, valRegCount: 4, bytecode: code,
      );
      final module = DartiModule(
        functions: [func], classes: [cls], constPool: [], entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: HostBindings());
      final result = runtime.execute(module);
      expect(result, equals(42));
    });

    test('CALL_HOST invokes print binding', () {
      final printLog = <Object?>[];
      final bindings = HostBindings();
      bindings.register('print', (args) {
        printLog.add(args[0]);
      });

      // load "hello" from constPool[0], call print
      final code = Uint32List.fromList([
        Instr.encodeABx(OpCode.loadConst, 0, 0),   // ref[0] = constPool[0]
        Instr.encodeABx(OpCode.callHost, 0, 0),    // hostBindings[0](ref[0])
        Instr.encodeABC(OpCode.returnNull, 0, 0, 0),
      ]);
      final func = FuncProto(
        name: 'test', paramCount: 0,
        refRegCount: 4, valRegCount: 4, bytecode: code,
      );
      final module = DartiModule(
        functions: [func], classes: [], constPool: ['hello'], entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: bindings);
      runtime.execute(module);
      expect(printLog, equals(['hello']));
    });
  });
}
