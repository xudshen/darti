import 'dart:typed_data';
import 'package:darti/src/runtime/opcodes.dart';
import 'package:darti/src/runtime/types.dart';
import 'package:darti/src/runtime/host_bindings.dart';
import 'package:darti/src/runtime/dispatch_loop.dart';
import 'package:test/test.dart';

void main() {
  test('hand-written Counter program outputs 10 and 4', () async {
    final printLog = <Object?>[];
    final bindings = HostBindings();
    bindings.register('print', (args) {
      printLog.add(args[0]);
      return null;
    });
    final listAddId = bindings.register('List.add', (args) {
      (args[0] as List).add(args[1]);
      return null;
    });
    final listLengthId = bindings.register('List.length', (args) {
      return (args[0] as List).length;
    });

    // Class 0: Counter { int _count (valueField 0) }
    final counterClass = ClassInfo(
      classId: 0, name: 'Counter',
      refFieldCount: 0, valueFieldCount: 1,
      fieldOffsets: {'_count': 0}, fieldIsValue: {'_count': true},
      methodTable: {'increment': 1, 'count': 2},
    );

    // Func 1: Counter.increment(this)
    // ref[0] = this (passed as arg)
    final incrementCode = Uint32List.fromList([
      Instr.encodeABC(OpCode.getFieldVal, 0, 0, 0),   // val[0] = this.valueFields[0]
      Instr.encodeABC(OpCode.addIntImm, 0, 0, 1),     // val[0] += 1
      Instr.encodeABC(OpCode.setFieldVal, 0, 0, 0),   // this.valueFields[0] = val[0]
      Instr.encodeABC(OpCode.returnNull, 0, 0, 0),
    ]);

    // Func 2: Counter.count(this) → int
    final countCode = Uint32List.fromList([
      Instr.encodeABC(OpCode.getFieldVal, 0, 0, 0),   // val[0] = this.valueFields[0]
      Instr.encodeABC(OpCode.returnVal, 0, 0, 0),     // return val[0]
    ]);

    final incrementFunc = FuncProto(
      name: 'Counter.increment', paramCount: 1,
      refRegCount: 4, valRegCount: 4, bytecode: incrementCode,
    );
    final countFunc = FuncProto(
      name: 'Counter.count', paramCount: 1,
      refRegCount: 4, valRegCount: 4, bytecode: countCode,
    );

    final runtime = DartiRuntime(hostBindings: bindings);
    final module = DartiModule(
      functions: [
        FuncProto(name: 'main', paramCount: 0,
          refRegCount: 8, valRegCount: 8,
          bytecode: Uint32List(0)), // unused — we call methods manually
        incrementFunc,
        countFunc,
      ],
      classes: [counterClass],
      constPool: [],
      entryPoint: 0,
    );

    // Create Counter
    final counter = InterpreterObject(
        classId: 0, refFieldCount: 0, valueFieldCount: 1);
    counter.valueFields![0] = 0;

    // Call increment 10 times
    for (int i = 0; i < 10; i++) {
      await runtime.executeFunc(module, 1, [counter], 0, 0);
    }

    // Call count getter
    final count = await runtime.executeFunc(module, 2, [counter], 0, 0);
    printLog.add(count);

    // List operations via host bindings
    final list = <int>[1, 2, 3];
    bindings.invoke(listAddId, [list, 4]);
    final len = bindings.invoke(listLengthId, [list]);
    printLog.add(len);

    expect(printLog, equals([10, 4]));
  });
}
