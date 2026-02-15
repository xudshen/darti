import 'dart:async';
import 'dart:typed_data';
import 'package:darti/src/runtime/opcodes.dart';
import 'package:darti/src/runtime/types.dart';
import 'package:darti/src/runtime/host_bindings.dart';
import 'package:darti/src/runtime/dispatch_loop.dart';
import 'package:test/test.dart';

void main() {
  group('DispatchLoop', () {
    test('executes LOAD_INT + ADD_INT + RETURN_VAL', () async {
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
      final result = await runtime.execute(module);
      expect(result, equals(10));
    });

    test('executes for loop counting to 10', () async {
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
      final result = await runtime.execute(module);
      expect(result, equals(10));
    });

    test('NEW_INSTANCE + GET/SET_FIELD_VAL', () async {
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
      final result = await runtime.execute(module);
      expect(result, equals(42));
    });

    test('CALL_STATIC uses iterative dispatch (no Dart recursion)', () async {
      // func 0 (main): calls func 1 (add) with args 3, 7; returns result
      // func 1 (add): returns param0 + param1
      //
      // Main layout:
      //   ref regs: 0=result, 1=arg0(boxed 3), 2=arg1(boxed 7)
      //   val regs: 0=scratch(3), 1=scratch(7)
      final mainCode = Uint32List.fromList([
        Instr.encodeAsBx(OpCode.loadInt, 0, 3),        // val[0] = 3
        Instr.encodeABC(OpCode.boxInt, 1, 0, 0),       // ref[1] = box(val[0]) = 3
        Instr.encodeAsBx(OpCode.loadInt, 1, 7),        // val[1] = 7
        Instr.encodeABC(OpCode.boxInt, 2, 1, 0),       // ref[2] = box(val[1]) = 7
        Instr.encodeABx(OpCode.callStatic, 0, 1),      // ref[0] = call func[1](ref[1], ref[2])
        Instr.encodeABC(OpCode.returnRef, 0, 0, 0),    // return ref[0]
      ]);
      // Add (func 1): paramCount=2, ref[0]=a, ref[1]=b
      //   val regs: 0=unboxed a, 1=unboxed b, 2=sum
      final addCode = Uint32List.fromList([
        Instr.encodeABC(OpCode.unboxInt, 0, 0, 0),     // val[0] = unbox(ref[0])
        Instr.encodeABC(OpCode.unboxInt, 1, 1, 0),     // val[1] = unbox(ref[1])
        Instr.encodeABC(OpCode.addInt, 2, 0, 1),       // val[2] = val[0] + val[1]
        Instr.encodeABC(OpCode.returnVal, 2, 0, 0),    // return val[2] (boxed as Object)
      ]);

      final mainFunc = FuncProto(
        name: 'main', paramCount: 0,
        refRegCount: 4, valRegCount: 4, bytecode: mainCode,
      );
      final addFunc = FuncProto(
        name: 'add', paramCount: 2,
        refRegCount: 4, valRegCount: 4, bytecode: addCode,
      );
      final module = DartiModule(
        functions: [mainFunc, addFunc], classes: [], constPool: [], entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: HostBindings());
      final result = await runtime.execute(module);
      expect(result, equals(10));
    });

    test('CALL_STATIC with nested calls', () async {
      // func 0 (main): calls func 1(5) which calls func 2(5)
      // func 1 (double): returns func2(n) * 2
      // func 2 (addOne): returns n + 1
      // Expected: addOne(5)=6, double(5)=addOne(5)*2=12

      // Main: ref[0]=result, ref[1]=arg (boxed 5), val[0]=5
      final mainCode = Uint32List.fromList([
        Instr.encodeAsBx(OpCode.loadInt, 0, 5),        // val[0] = 5
        Instr.encodeABC(OpCode.boxInt, 1, 0, 0),       // ref[1] = box(5)
        Instr.encodeABx(OpCode.callStatic, 0, 1),      // ref[0] = call double(ref[1])
        Instr.encodeABC(OpCode.returnRef, 0, 0, 0),    // return ref[0]
      ]);

      // Double (func 1): paramCount=1, ref[0]=n
      //   ref[1]=arg to addOne, ref[2]=result from addOne
      //   val[0]=unboxed result, val[1]=2, val[2]=product
      final doubleCode = Uint32List.fromList([
        Instr.encodeABC(OpCode.moveRef, 3, 0, 0),      // ref[3] = ref[0] (save n)
        Instr.encodeABC(OpCode.moveRef, 1, 0, 0),      // ref[1] = ref[0] (arg for addOne)
        Instr.encodeABx(OpCode.callStatic, 0, 2),      // ref[0] = call addOne(ref[1])
        Instr.encodeABC(OpCode.unboxInt, 0, 0, 0),     // val[0] = unbox(ref[0])
        Instr.encodeAsBx(OpCode.loadInt, 1, 2),        // val[1] = 2
        Instr.encodeABC(OpCode.mulInt, 2, 0, 1),       // val[2] = val[0] * 2
        Instr.encodeABC(OpCode.returnVal, 2, 0, 0),    // return val[2]
      ]);

      // AddOne (func 2): paramCount=1, ref[0]=n
      //   val[0]=unboxed n, val[1]=result
      final addOneCode = Uint32List.fromList([
        Instr.encodeABC(OpCode.unboxInt, 0, 0, 0),     // val[0] = unbox(ref[0])
        Instr.encodeABC(OpCode.addIntImm, 1, 0, 1),    // val[1] = val[0] + 1
        Instr.encodeABC(OpCode.returnVal, 1, 0, 0),    // return val[1]
      ]);

      final mainFunc = FuncProto(
        name: 'main', paramCount: 0,
        refRegCount: 4, valRegCount: 4, bytecode: mainCode,
      );
      final doubleFunc = FuncProto(
        name: 'double', paramCount: 1,
        refRegCount: 4, valRegCount: 4, bytecode: doubleCode,
      );
      final addOneFunc = FuncProto(
        name: 'addOne', paramCount: 1,
        refRegCount: 4, valRegCount: 4, bytecode: addOneCode,
      );
      final module = DartiModule(
        functions: [mainFunc, doubleFunc, addOneFunc],
        classes: [], constPool: [], entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: HostBindings());
      final result = await runtime.execute(module);
      expect(result, equals(12));
    });

    test('CALL_HOST invokes print binding', () async {
      final printLog = <Object?>[];
      final bindings = HostBindings();
      bindings.register('print', (args) {
        printLog.add(args[0]);
        return null;
      });

      // load "hello" from constPool[0], call print
      final code = Uint32List.fromList([
        Instr.encodeABx(OpCode.loadConst, 0, 0),   // ref[0] = constPool[0]
        Instr.encodeABC(OpCode.callHost, 0, 1, 0), // hostBindings[0](ref[0]), argCount=1
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
      await runtime.execute(module);
      expect(printLog, equals(['hello']));
    });
  });

  group('Fuel-based scheduling', () {
    test('simple program completes with default fuel budget', () async {
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
      final result = await runtime.execute(module);
      expect(result, equals(10));
    });

    test('fuel exhaustion triggers Timer.run and resumes correctly', () async {
      // Program: i=0; while(i<10) i++; return i
      // This loop has ~7 instructions per iteration * 10 = 70+ instructions.
      // With fuelBudget=5, this forces many Timer.run rounds.
      final code = Uint32List.fromList([
        Instr.encodeAsBx(OpCode.loadInt, 0, 0),     // v[0] = i = 0
        Instr.encodeAsBx(OpCode.loadInt, 1, 10),    // v[1] = 10
        // LOOP (pc=2):
        Instr.encodeABC(OpCode.ltInt, 2, 0, 1),     // v[2] = (i < 10)
        Instr.encodeAsBx(OpCode.jumpIfFalse, 2, 2), // if false: skip to RETURN
        Instr.encodeABC(OpCode.addIntImm, 0, 0, 1), // i += 1
        Instr.encodeAsBx(OpCode.jump, 0, -4),       // back to LOOP
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

      // Small fuel budget forces multiple Timer.run rounds
      final runtime = DartiRuntime(
        hostBindings: HostBindings(),
        fuelBudget: 5,
      );
      final result = await runtime.execute(module);
      expect(result, equals(10));
    });

    test('fuel exhaustion works with CALL_STATIC across frames', () async {
      // func 0 (main): calls func 1 (add) with args 3, 7; returns result
      // func 1 (add): returns param0 + param1
      final mainCode = Uint32List.fromList([
        Instr.encodeAsBx(OpCode.loadInt, 0, 3),
        Instr.encodeABC(OpCode.boxInt, 1, 0, 0),
        Instr.encodeAsBx(OpCode.loadInt, 1, 7),
        Instr.encodeABC(OpCode.boxInt, 2, 1, 0),
        Instr.encodeABx(OpCode.callStatic, 0, 1),
        Instr.encodeABC(OpCode.returnRef, 0, 0, 0),
      ]);
      final addCode = Uint32List.fromList([
        Instr.encodeABC(OpCode.unboxInt, 0, 0, 0),
        Instr.encodeABC(OpCode.unboxInt, 1, 1, 0),
        Instr.encodeABC(OpCode.addInt, 2, 0, 1),
        Instr.encodeABC(OpCode.returnVal, 2, 0, 0),
      ]);

      final mainFunc = FuncProto(
        name: 'main', paramCount: 0,
        refRegCount: 4, valRegCount: 4, bytecode: mainCode,
      );
      final addFunc = FuncProto(
        name: 'add', paramCount: 2,
        refRegCount: 4, valRegCount: 4, bytecode: addCode,
      );
      final module = DartiModule(
        functions: [mainFunc, addFunc], classes: [], constPool: [],
        entryPoint: 0,
      );

      // With fuelBudget=3, we'll exhaust fuel mid-execution
      final runtime = DartiRuntime(
        hostBindings: HostBindings(),
        fuelBudget: 3,
      );
      final result = await runtime.execute(module);
      expect(result, equals(10));
    });

    test('executeFunc returns Future with fuel scheduling', () async {
      // Simple function: return arg + 1
      final code = Uint32List.fromList([
        Instr.encodeABC(OpCode.unboxInt, 0, 0, 0),
        Instr.encodeABC(OpCode.addIntImm, 1, 0, 1),
        Instr.encodeABC(OpCode.returnVal, 1, 0, 0),
      ]);
      final func = FuncProto(
        name: 'addOne', paramCount: 1,
        refRegCount: 4, valRegCount: 4, bytecode: code,
      );
      final module = DartiModule(
        functions: [func], classes: [], constPool: [], entryPoint: 0,
      );

      final runtime = DartiRuntime(
        hostBindings: HostBindings(),
        fuelBudget: 2,
      );
      final result = await runtime.executeFunc(module, 0, [42], 0, 0);
      expect(result, equals(43));
    });

    test('HALT completes with null under fuel scheduling', () async {
      final code = Uint32List.fromList([
        Instr.encodeABC(OpCode.halt, 0, 0, 0),
      ]);
      final func = FuncProto(
        name: 'test', paramCount: 0,
        refRegCount: 4, valRegCount: 4, bytecode: code,
      );
      final module = DartiModule(
        functions: [func], classes: [], constPool: [], entryPoint: 0,
      );

      final runtime = DartiRuntime(
        hostBindings: HostBindings(),
        fuelBudget: 5,
      );
      final result = await runtime.execute(module);
      expect(result, isNull);
    });

    test('yieldCount tracks Timer.run rounds', () async {
      // With fuel=3 and ~52 instructions (loop counting to 10),
      // we expect multiple Timer.run yields.
      final code = Uint32List.fromList([
        Instr.encodeAsBx(OpCode.loadInt, 0, 0),     // v[0] = i = 0
        Instr.encodeAsBx(OpCode.loadInt, 1, 10),    // v[1] = 10
        // LOOP (pc=2):
        Instr.encodeABC(OpCode.ltInt, 2, 0, 1),     // v[2] = (i < 10)
        Instr.encodeAsBx(OpCode.jumpIfFalse, 2, 2), // if false: skip to RETURN
        Instr.encodeABC(OpCode.addIntImm, 0, 0, 1), // i += 1
        Instr.encodeAsBx(OpCode.jump, 0, -4),       // back to LOOP
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

      final runtime = DartiRuntime(
        hostBindings: HostBindings(),
        fuelBudget: 3,
      );
      final result = await runtime.execute(module);
      expect(result, equals(10));
      // With fuel=3 and ~52 total instructions, must yield many times
      expect(runtime.yieldCount, greaterThan(0));
    });

    test('multiple Timer.run rounds with nested calls and loops', () async {
      // func 0 (main): calls func 1(5) which calls func 2(5)
      // func 1 (double): returns func2(n) * 2
      // func 2 (addOne): returns n + 1
      // Expected: addOne(5)=6, double(5)=12
      final mainCode = Uint32List.fromList([
        Instr.encodeAsBx(OpCode.loadInt, 0, 5),
        Instr.encodeABC(OpCode.boxInt, 1, 0, 0),
        Instr.encodeABx(OpCode.callStatic, 0, 1),
        Instr.encodeABC(OpCode.returnRef, 0, 0, 0),
      ]);
      final doubleCode = Uint32List.fromList([
        Instr.encodeABC(OpCode.moveRef, 3, 0, 0),
        Instr.encodeABC(OpCode.moveRef, 1, 0, 0),
        Instr.encodeABx(OpCode.callStatic, 0, 2),
        Instr.encodeABC(OpCode.unboxInt, 0, 0, 0),
        Instr.encodeAsBx(OpCode.loadInt, 1, 2),
        Instr.encodeABC(OpCode.mulInt, 2, 0, 1),
        Instr.encodeABC(OpCode.returnVal, 2, 0, 0),
      ]);
      final addOneCode = Uint32List.fromList([
        Instr.encodeABC(OpCode.unboxInt, 0, 0, 0),
        Instr.encodeABC(OpCode.addIntImm, 1, 0, 1),
        Instr.encodeABC(OpCode.returnVal, 1, 0, 0),
      ]);

      final mainFunc = FuncProto(
        name: 'main', paramCount: 0,
        refRegCount: 4, valRegCount: 4, bytecode: mainCode,
      );
      final doubleFunc = FuncProto(
        name: 'double', paramCount: 1,
        refRegCount: 4, valRegCount: 4, bytecode: doubleCode,
      );
      final addOneFunc = FuncProto(
        name: 'addOne', paramCount: 1,
        refRegCount: 4, valRegCount: 4, bytecode: addOneCode,
      );
      final module = DartiModule(
        functions: [mainFunc, doubleFunc, addOneFunc],
        classes: [], constPool: [], entryPoint: 0,
      );

      // Very small fuel to force many rounds
      final runtime = DartiRuntime(
        hostBindings: HostBindings(),
        fuelBudget: 2,
      );
      final result = await runtime.execute(module);
      expect(result, equals(12));
    });
  });

  group('Async instructions', () {
    test('AWAIT non-Future value takes fast path', () async {
      // async int compute() async {
      //   var x = await 42;  // 42 is not a Future, fast path
      //   return x;
      // }
      //
      // Layout:
      //   ref[0] = completer (from INIT_ASYNC)
      //   ref[1] = value to await (42, loaded from constPool)
      //
      // Bytecode:
      //   INIT_ASYNC   ref[0]               ; create completer, future goes to caller
      //   LOAD_CONST   ref[1], constPool[0]  ; ref[1] = 42
      //   AWAIT        ref[1], resumePC=4    ; await ref[1] — not a Future, fast path
      //   ASYNC_RETURN ref[1]               ; completer.complete(ref[1])
      final code = Uint32List.fromList([
        Instr.encodeABx(OpCode.initAsync, 0, 0),    // ref[0] = completer
        Instr.encodeABx(OpCode.loadConst, 1, 0),    // ref[1] = constPool[0] = 42
        Instr.encodeABx(OpCode.await_, 1, 4),        // await ref[1], resumePC=4
        // pc=3: This should be skipped (AWAIT fast path jumps to pc=4)
        // Actually AWAIT fast path: value is not a Future, so we just continue
        // to the next instruction normally. Bx is the resume PC for the
        // suspend case. For fast path, we just fall through.
        Instr.encodeABC(OpCode.asyncReturn, 1, 0, 0), // completer.complete(42)
      ]);

      final func = FuncProto(
        name: 'compute',
        paramCount: 0,
        refRegCount: 4,
        valRegCount: 4,
        bytecode: code,
      );
      final module = DartiModule(
        functions: [func],
        classes: [],
        constPool: [42],
        entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: HostBindings());
      final result = await runtime.execute(module);
      // execute returns Future<Object?> which is asyncCompleter.future
      // that resolves to 42
      expect(result, equals(42));
    });

    test('AWAIT already-completed Future takes fast path via .then()', () async {
      // async int compute() async {
      //   var x = await Future.value(99);
      //   return x;
      // }
      //
      // We use CALL_HOST to create Future.value(99), result in ref[1]
      // Then AWAIT ref[1] — the Future is already completed, but we still
      // go through suspend/resume since Dart Futures are always async.
      //
      // Layout:
      //   ref[0] = completer (from INIT_ASYNC)
      //   ref[1] = the Future / awaited result
      //   ref[2] = arg to host function (99)
      final bindings = HostBindings();
      final futureValueId = bindings.register('Future.value', (args) {
        return Future.value(args[0]);
      });

      final code = Uint32List.fromList([
        Instr.encodeABx(OpCode.initAsync, 0, 0),         // ref[0] = completer
        Instr.encodeABx(OpCode.loadConst, 1, 0),         // ref[1] = 99
        Instr.encodeABC(OpCode.callHost, 1, 1, futureValueId), // ref[1] = Future.value(99)
        Instr.encodeABx(OpCode.await_, 1, 4),             // await ref[1], resumePC=4
        Instr.encodeABC(OpCode.asyncReturn, 1, 0, 0),    // completer.complete(ref[1])
      ]);

      final func = FuncProto(
        name: 'compute',
        paramCount: 0,
        refRegCount: 4,
        valRegCount: 4,
        bytecode: code,
      );
      final module = DartiModule(
        functions: [func],
        classes: [],
        constPool: [99],
        entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: bindings);
      final result = await runtime.execute(module);
      expect(result, equals(99));
    });

    test('AWAIT delayed Future suspends and resumes correctly', () async {
      // async int compute() async {
      //   var x = await Future.delayed(Duration(milliseconds: 10), () => 42);
      //   return x;
      // }
      //
      // Layout:
      //   ref[0] = completer (from INIT_ASYNC)
      //   ref[1] = the Future / awaited result
      final bindings = HostBindings();
      final delayedFutureId = bindings.register('Future.delayed', (args) {
        return Future.delayed(
          Duration(milliseconds: 10),
          () => 42,
        );
      });

      final code = Uint32List.fromList([
        Instr.encodeABx(OpCode.initAsync, 0, 0),              // ref[0] = completer
        Instr.encodeABC(OpCode.callHost, 1, 0, delayedFutureId), // ref[1] = Future.delayed(...)
        Instr.encodeABx(OpCode.await_, 1, 3),                  // await ref[1], resumePC=3
        Instr.encodeABC(OpCode.asyncReturn, 1, 0, 0),         // completer.complete(ref[1])
      ]);

      final func = FuncProto(
        name: 'compute',
        paramCount: 0,
        refRegCount: 4,
        valRegCount: 4,
        bytecode: code,
      );
      final module = DartiModule(
        functions: [func],
        classes: [],
        constPool: [],
        entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: bindings);
      final result = await runtime.execute(module);
      expect(result, equals(42));
    });

    test('AWAIT with computation after resume', () async {
      // async int compute() async {
      //   var x = await Future.delayed(Duration(ms: 10), () => 10);
      //   var y = x + 5;  // computation after await
      //   return y;       // should be 15
      // }
      //
      // Layout:
      //   ref[0] = completer (from INIT_ASYNC)
      //   ref[1] = the Future / awaited result
      //   val[0] = unboxed result
      //   val[1] = 5
      //   val[2] = sum
      final bindings = HostBindings();
      final delayedFutureId = bindings.register('Future.delayed', (args) {
        return Future.delayed(
          Duration(milliseconds: 10),
          () => 10,
        );
      });

      final code = Uint32List.fromList([
        Instr.encodeABx(OpCode.initAsync, 0, 0),               // ref[0] = completer
        Instr.encodeABC(OpCode.callHost, 1, 0, delayedFutureId), // ref[1] = Future.delayed(...)
        Instr.encodeABx(OpCode.await_, 1, 3),                   // await ref[1], resumePC=3
        // --- resume here (pc=3) after Future completes, ref[1] = 10 ---
        Instr.encodeABC(OpCode.unboxInt, 0, 1, 0),              // val[0] = unbox(ref[1]) = 10
        Instr.encodeABC(OpCode.addIntImm, 1, 0, 5),             // val[1] = val[0] + 5 = 15
        Instr.encodeABC(OpCode.boxInt, 1, 1, 0),                // ref[1] = box(val[1]) = 15
        Instr.encodeABC(OpCode.asyncReturn, 1, 0, 0),           // completer.complete(15)
      ]);

      final func = FuncProto(
        name: 'compute',
        paramCount: 0,
        refRegCount: 4,
        valRegCount: 4,
        bytecode: code,
      );
      final module = DartiModule(
        functions: [func],
        classes: [],
        constPool: [],
        entryPoint: 0,
      );

      final runtime = DartiRuntime(hostBindings: bindings);
      final result = await runtime.execute(module);
      expect(result, equals(15));
    });
  });
}
