import 'dart:typed_data';

import 'package:dartic/src/bridge/callback_proxy.dart';
import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/class_info.dart';
import 'package:dartic/src/runtime/closure.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

/// The standard entry function: a single HALT instruction.
final _entryProto = DarticFuncProto(
  funcId: 0,
  bytecode: Uint32List.fromList([encodeABC(Op.halt, 0, 0, 0)]),
  valueRegCount: 0,
  refRegCount: 1,
  paramCount: 0,
);

/// Builds a module containing [_entryProto] and the given [closureProto],
/// executes it, and returns the interpreter (ready for invokeClosure calls).
DarticInterpreter _initInterpreter(
  DarticFuncProto closureProto, {
  ConstantPool? constantPool,
}) {
  final module = DarticModule(
    functions: [_entryProto, closureProto],
    constantPool: constantPool ?? ConstantPool(),
    entryFuncId: 0,
  );
  final interp = DarticInterpreter();
  interp.execute(module);
  return interp;
}

/// Builds a 1-arg identity closure: MOVE_REF 0, 2 -> RETURN_REF 0.
DarticFuncProto _identityProto({String name = 'identity'}) {
  return DarticFuncProto(
    funcId: 1,
    name: name,
    bytecode: Uint32List.fromList([
      encodeABC(Op.moveRef, 0, 2, 0), // refStack[0] = refStack[2] (arg0)
      encodeABC(Op.returnRef, 0, 0, 0),
    ]),
    valueRegCount: 0,
    refRegCount: 3, // ITA, FTA, arg0
    paramCount: 1,
  );
}

void main() {
  group('invokeClosure', () {
    test('invokes a closure that returns a constant string', () {
      final closureProto = DarticFuncProto(
        funcId: 1,
        name: 'closure',
        bytecode: Uint32List.fromList([
          encodeABx(Op.loadConst, 0, 0),
          encodeABC(Op.returnRef, 0, 0, 0),
        ]),
        valueRegCount: 0,
        refRegCount: 3,
        paramCount: 0,
      );

      final cp = ConstantPool();
      cp.addRef('hello');

      final interp = _initInterpreter(closureProto, constantPool: cp);
      final closure = DarticClosure(funcProto: closureProto, upvalues: []);
      expect(interp.invokeClosure(closure, []), equals('hello'));
    });

    test('invokes a closure that reads its argument and returns it', () {
      final proto = _identityProto();
      final interp = _initInterpreter(proto);
      final closure = DarticClosure(funcProto: proto, upvalues: []);

      expect(interp.invokeClosure(closure, ['world']), equals('world'));
      expect(interp.invokeClosure(closure, [42]), equals(42));
      expect(interp.invokeClosure(closure, [null]), isNull);
    });

    test('passes a List from host and returns it (same reference)', () {
      final proto = _identityProto();
      final interp = _initInterpreter(proto);
      final closure = DarticClosure(funcProto: proto, upvalues: []);

      final hostList = [1, 'two', 3.0, true, null];
      final result = interp.invokeClosure(closure, [hostList]);
      expect(identical(result, hostList), isTrue,
          reason: 'should be the same List reference, not a copy');
      expect(result, equals([1, 'two', 3.0, true, null]));
    });

    test('passes a Map from host and returns it (same reference)', () {
      final proto = _identityProto();
      final interp = _initInterpreter(proto);
      final closure = DarticClosure(funcProto: proto, upvalues: []);

      final hostMap = {'key': 42, 'nested': [1, 2]};
      final result = interp.invokeClosure(closure, [hostMap]);
      expect(identical(result, hostMap), isTrue);
    });

    test('passes a custom host object and returns it', () {
      final proto = _identityProto();
      final interp = _initInterpreter(proto);
      final closure = DarticClosure(funcProto: proto, upvalues: []);

      final hostObj = Uri.parse('https://example.com');
      final result = interp.invokeClosure(closure, [hostObj]);
      expect(identical(result, hostObj), isTrue);
    });

    test('invokes a closure that returns an int via RETURN_VAL', () {
      final closureProto = DarticFuncProto(
        funcId: 1,
        name: 'intReturn',
        bytecode: Uint32List.fromList([
          encodeABx(Op.loadInt, 0, 99 + 0x7FFF),
          encodeABC(Op.returnVal, 0, 0, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 2,
        paramCount: 0,
      );

      final interp = _initInterpreter(closureProto);
      final closure = DarticClosure(funcProto: closureProto, upvalues: []);
      expect(interp.invokeClosure(closure, []), equals(99));
    });

    test('invokes a closure that returns a double via RETURN_VAL', () {
      final cp = ConstantPool();
      cp.addDouble(3.14);

      final closureProto = DarticFuncProto(
        funcId: 1,
        name: 'dblReturn',
        bytecode: Uint32List.fromList([
          encodeABx(Op.loadConstDbl, 0, 0),
          encodeABC(Op.returnVal, 0, 0, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 2,
        paramCount: 0,
        returnKind: StackKind.doubleVal.index,
      );

      final interp = _initInterpreter(closureProto, constantPool: cp);
      final closure = DarticClosure(funcProto: closureProto, upvalues: []);
      final result = interp.invokeClosure(closure, []);
      expect(result, isA<double>());
      expect(result, closeTo(3.14, 0.001));
    });

    test('invokes a closure that returns a bool via RETURN_VAL', () {
      final closureProto = DarticFuncProto(
        funcId: 1,
        name: 'boolReturn',
        bytecode: Uint32List.fromList([
          encodeABx(Op.loadInt, 0, 1 + 0x7FFF),
          encodeABC(Op.returnVal, 0, 0, 0),
        ]),
        valueRegCount: 1,
        refRegCount: 2,
        paramCount: 0,
        returnKind: StackKind.boolVal.index,
      );

      final interp = _initInterpreter(closureProto);
      final closure = DarticClosure(funcProto: closureProto, upvalues: []);
      final result = interp.invokeClosure(closure, []);
      expect(result, isA<bool>());
      expect(result, true);
    });

    test('invokes a closure that returns null via RETURN_NULL', () {
      final closureProto = DarticFuncProto(
        funcId: 1,
        name: 'nullReturn',
        bytecode: Uint32List.fromList([
          encodeABC(Op.returnNull, 0, 0, 0),
        ]),
        valueRegCount: 0,
        refRegCount: 2,
        paramCount: 0,
      );

      final interp = _initInterpreter(closureProto);
      final closure = DarticClosure(funcProto: closureProto, upvalues: []);
      expect(interp.invokeClosure(closure, []), isNull);
    });
  });

  group('DarticCallbackProxy', () {
    late DarticInterpreter interp;
    late DarticClosure identityClosure;

    setUp(() {
      final proto = _identityProto();
      interp = _initInterpreter(proto);
      identityClosure = DarticClosure(funcProto: proto, upvalues: []);
    });

    test('proxy1 creates a callable one-argument function', () {
      final proxy = DarticCallbackProxy(interp, identityClosure);
      final fn = proxy.proxy1();
      expect(fn('test'), equals('test'));
      expect(fn(42), equals(42));
    });

    test('proxy0 creates a callable zero-argument function', () {
      final closureProto = DarticFuncProto(
        funcId: 1,
        name: 'nullFn',
        bytecode: Uint32List.fromList([
          encodeABC(Op.returnNull, 0, 0, 0),
        ]),
        valueRegCount: 0,
        refRegCount: 2,
        paramCount: 0,
      );

      final closure = DarticClosure(funcProto: closureProto, upvalues: []);
      final proxy = DarticCallbackProxy(interp, closure);
      final fn = proxy.proxy0();
      expect(fn(), isNull);
    });

    test('proxy2 creates a callable two-argument function', () {
      final closureProto = DarticFuncProto(
        funcId: 1,
        name: 'second',
        bytecode: Uint32List.fromList([
          encodeABC(Op.moveRef, 0, 3, 0), // refStack[0] = refStack[3] (arg1)
          encodeABC(Op.returnRef, 0, 0, 0),
        ]),
        valueRegCount: 0,
        refRegCount: 4, // ITA, FTA, arg0, arg1
        paramCount: 2,
      );

      final closure = DarticClosure(funcProto: closureProto, upvalues: []);
      final proxy = DarticCallbackProxy(interp, closure);
      final fn = proxy.proxy2();
      expect(fn('first', 'second'), equals('second'));
    });
  });
}
