import 'opcodes.dart';
import 'types.dart';
import 'value_stack.dart';
import 'ref_stack.dart';
import 'host_bindings.dart';

class DartiRuntime {
  final HostBindings hostBindings;
  final ValueStack _vs;
  final RefStack _rs;

  DartiRuntime({required this.hostBindings, int stackSize = 4096})
      : _vs = ValueStack(stackSize),
        _rs = RefStack(stackSize);

  Object? execute(DartiModule module) {
    return executeFunc(module, module.entryPoint, [], 0, 0);
  }

  Object? executeFunc(
    DartiModule module,
    int funcId,
    List<Object?> refArgs,
    int baseV,
    int baseR,
  ) {
    final func = module.functions[funcId];
    final code = func.bytecode;
    final vBase = baseV;
    final rBase = baseR;
    var pc = 0;

    // Copy ref args into ref stack
    for (int i = 0; i < refArgs.length; i++) {
      _rs.slots[rBase + i] = refArgs[i];
    }

    while (true) {
      final instr = code[pc++];
      final op = instr & 0xFF;

      switch (op) {
        case OpCode.nop:
          break;

        case OpCode.loadInt:
          _vs.intView[vBase + Instr.decodeA(instr)] = Instr.decodesBx(instr);

        case OpCode.loadConst:
          final a = Instr.decodeA(instr);
          final bx = Instr.decodeBx(instr);
          _rs.slots[rBase + a] = module.constPool[bx];

        case OpCode.loadNull:
          _rs.slots[rBase + Instr.decodeA(instr)] = null;

        case OpCode.loadTrue:
          _vs.intView[vBase + Instr.decodeA(instr)] = 1;

        case OpCode.loadFalse:
          _vs.intView[vBase + Instr.decodeA(instr)] = 0;

        case OpCode.moveRef:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          _rs.slots[rBase + a] = _rs.slots[rBase + b];

        case OpCode.moveVal:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          _vs.intView[vBase + a] = _vs.intView[vBase + b];

        case OpCode.addInt:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          _vs.intView[vBase + a] =
              _vs.intView[vBase + b] + _vs.intView[vBase + c];

        case OpCode.subInt:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          _vs.intView[vBase + a] =
              _vs.intView[vBase + b] - _vs.intView[vBase + c];

        case OpCode.mulInt:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          _vs.intView[vBase + a] =
              _vs.intView[vBase + b] * _vs.intView[vBase + c];

        case OpCode.addIntImm:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          _vs.intView[vBase + a] = _vs.intView[vBase + b] + c;

        case OpCode.ltInt:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          _vs.intView[vBase + a] =
              _vs.intView[vBase + b] < _vs.intView[vBase + c] ? 1 : 0;

        case OpCode.leInt:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          _vs.intView[vBase + a] =
              _vs.intView[vBase + b] <= _vs.intView[vBase + c] ? 1 : 0;

        case OpCode.eqInt:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          _vs.intView[vBase + a] =
              _vs.intView[vBase + b] == _vs.intView[vBase + c] ? 1 : 0;

        case OpCode.jump:
          pc += Instr.decodesBx(instr);

        case OpCode.jumpIfFalse:
          if (_vs.intView[vBase + Instr.decodeA(instr)] == 0) {
            pc += Instr.decodesBx(instr);
          }

        case OpCode.callStatic:
          final a = Instr.decodeA(instr);
          final bx = Instr.decodeBx(instr);
          final targetFunc = module.functions[bx];

          // Collect args from ref[a+1..a+paramCount]
          final args = <Object?>[];
          for (int i = 0; i < targetFunc.paramCount; i++) {
            args.add(_rs.slots[rBase + a + 1 + i]);
          }

          final newBaseV = vBase + func.valRegCount;
          final newBaseR = rBase + func.refRegCount;
          final result = executeFunc(module, bx, args, newBaseV, newBaseR);
          _rs.slots[rBase + a] = result;

        case OpCode.callHost:
          final a = Instr.decodeA(instr);
          final bx = Instr.decodeBx(instr);
          final arg = _rs.slots[rBase + a];
          final result = hostBindings.invoke(bx, [arg]);
          _rs.slots[rBase + a] = result;

        case OpCode.returnRef:
          final a = Instr.decodeA(instr);
          final retVal = _rs.slots[rBase + a];
          _rs.clear(rBase, rBase + func.refRegCount);
          return retVal;

        case OpCode.returnVal:
          final a = Instr.decodeA(instr);
          final retVal = _vs.intView[vBase + a];
          _rs.clear(rBase, rBase + func.refRegCount);
          return retVal;

        case OpCode.returnNull:
          _rs.clear(rBase, rBase + func.refRegCount);
          return null;

        case OpCode.newInstance:
          final a = Instr.decodeA(instr);
          final bx = Instr.decodeBx(instr);
          final cls = module.classes[bx];
          _rs.slots[rBase + a] = InterpreterObject(
            classId: cls.classId,
            refFieldCount: cls.refFieldCount,
            valueFieldCount: cls.valueFieldCount,
          );

        case OpCode.getFieldRef:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          final obj = _rs.slots[rBase + b] as InterpreterObject;
          _rs.slots[rBase + a] = obj.refFields[c];

        case OpCode.setFieldRef:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          final obj = _rs.slots[rBase + a] as InterpreterObject;
          obj.refFields[c] = _rs.slots[rBase + b];

        case OpCode.getFieldVal:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          final obj = _rs.slots[rBase + b] as InterpreterObject;
          _vs.intView[vBase + a] = obj.valueFields![c];

        case OpCode.setFieldVal:
          final a = Instr.decodeA(instr);
          final b = Instr.decodeB(instr);
          final c = Instr.decodeC(instr);
          final obj = _rs.slots[rBase + a] as InterpreterObject;
          obj.valueFields![c] = _vs.intView[vBase + b];

        case OpCode.halt:
          return null;

        default:
          throw StateError(
              'Unknown opcode: 0x${op.toRadixString(16)} at pc=${pc - 1}');
      }
    }
  }
}
