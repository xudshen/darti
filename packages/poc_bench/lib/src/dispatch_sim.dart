import 'dart:typed_data';
import 'value_stack.dart';

// Minimal opcode subset for fibonacci
abstract class Op {
  static const int nop = 0x00;
  static const int loadInt = 0x05;
  static const int moveVal = 0x09;
  static const int addInt = 0x10;
  static const int subInt = 0x11;
  static const int ltInt = 0x30;
  static const int leInt = 0x31;
  static const int jump = 0x40;
  static const int jumpIfFalse = 0x42;
  static const int halt = 0xFF;
}

int encodeABC(int op, int a, int b, int c) =>
    op | (a << 8) | (b << 16) | (c << 24);

int encodeAsBx(int op, int a, int sbx) =>
    op | (a << 8) | ((sbx + 0x7FFF) << 16);

/// Generate bytecode for iterative fib(n).
///
/// Jump offset formula: to jump from instruction at pc=N to pc=M,
/// offset = M - N - 1 (because dispatch loop does pc++ before switch).
///
/// Registers: r0=n, r1=a, r2=b(result), r3=const(1), r4=cmp, r5=tmp
Uint32List fibBytecode(int n) {
  final code = <int>[
    encodeAsBx(Op.loadInt, 0, n), //  pc=0:  r0 = n
    encodeAsBx(Op.loadInt, 3, 1), //  pc=1:  r3 = constant 1
    encodeABC(Op.leInt, 4, 0, 3), //  pc=2:  r4 = (n <= 1)
    encodeAsBx(Op.jumpIfFalse, 4, 2), // pc=3: if n>1, goto LOOP_INIT(6)
    encodeABC(Op.moveVal, 2, 0, 0), // pc=4:  r2 = n (result for n<=1)
    encodeAsBx(Op.jump, 0, 8), //  pc=5:  goto HALT(14)
    // LOOP_INIT:
    encodeAsBx(Op.loadInt, 1, 0), //  pc=6:  r1 = a = 0
    encodeAsBx(Op.loadInt, 2, 1), //  pc=7:  r2 = b = 1
    // LOOP (pc=8):
    encodeABC(Op.subInt, 0, 0, 3), // pc=8:  r0 = r0 - 1
    encodeABC(Op.addInt, 5, 1, 2), // pc=9:  r5 = a + b
    encodeABC(Op.moveVal, 1, 2, 0), // pc=10: r1 = r2 (a = b)
    encodeABC(Op.moveVal, 2, 5, 0), // pc=11: r2 = r5 (b = a+b)
    encodeABC(Op.leInt, 4, 0, 3), //  pc=12: r4 = (r0 <= 1)
    encodeAsBx(Op.jumpIfFalse, 4, -6), // pc=13: if r0>1, goto LOOP(8)
    // EXIT (pc=14):
    Op.halt, //  pc=14: return r2
  ];
  return Uint32List.fromList(code);
}

/// Dispatch loop interpreter
int executeDispatch(Uint32List code, ValueStack vs) {
  int pc = 0;

  while (true) {
    final instr = code[pc++];
    final op = instr & 0xFF;

    switch (op) {
      case Op.nop:
        break;
      case Op.loadInt:
        vs.intView[(instr >> 8) & 0xFF] = ((instr >> 16) & 0xFFFF) - 0x7FFF;
      case Op.addInt:
        final a = (instr >> 8) & 0xFF;
        vs.intView[a] =
            vs.intView[(instr >> 16) & 0xFF] + vs.intView[(instr >> 24) & 0xFF];
      case Op.subInt:
        final a = (instr >> 8) & 0xFF;
        vs.intView[a] =
            vs.intView[(instr >> 16) & 0xFF] - vs.intView[(instr >> 24) & 0xFF];
      case Op.ltInt:
        final a = (instr >> 8) & 0xFF;
        vs.intView[a] =
            vs.intView[(instr >> 16) & 0xFF] < vs.intView[(instr >> 24) & 0xFF]
                ? 1
                : 0;
      case Op.leInt:
        final a = (instr >> 8) & 0xFF;
        vs.intView[a] =
            vs.intView[(instr >> 16) & 0xFF] <=
                    vs.intView[(instr >> 24) & 0xFF]
                ? 1
                : 0;
      case Op.moveVal:
        vs.intView[(instr >> 8) & 0xFF] = vs.intView[(instr >> 16) & 0xFF];
      case Op.jump:
        pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
      case Op.jumpIfFalse:
        if (vs.intView[(instr >> 8) & 0xFF] == 0) {
          pc += ((instr >> 16) & 0xFFFF) - 0x7FFF;
        }
      case Op.halt:
        return vs.intView[2]; // result in r2 for fib
      default:
        throw StateError('Unknown opcode: 0x${op.toRadixString(16)}');
    }
  }
}

int nativeFibonacci(int n) {
  if (n <= 1) return n;
  int a = 0, b = 1;
  for (int i = 2; i <= n; i++) {
    final tmp = a + b;
    a = b;
    b = tmp;
  }
  return b;
}
