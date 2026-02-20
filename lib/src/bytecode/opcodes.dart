/// Opcode int constants for the dartic bytecode ISA.
///
/// Compile-time constants for use in switch/case dispatch and instruction
/// encoding. All opcodes occupy 8 bits (0x00-0xFF).
///
/// See: docs/design/01-bytecode-isa.md
library;

abstract final class Op {
  // ── Load/Store (0x00-0x0B) ──
  static const nop = 0x00;
  static const loadConst = 0x01;
  static const loadNull = 0x02;
  static const loadTrue = 0x03;
  static const loadFalse = 0x04;
  static const loadInt = 0x05;
  static const loadConstInt = 0x06;
  static const loadConstDbl = 0x07;
  static const moveRef = 0x08;
  static const moveVal = 0x09;
  static const loadUpvalue = 0x0A;
  static const storeUpvalue = 0x0B;

  // ── Integer Arithmetic (0x10-0x1F) ──
  static const addInt = 0x10;
  static const subInt = 0x11;
  static const mulInt = 0x12;
  static const divInt = 0x13;
  static const modInt = 0x14;
  static const negInt = 0x15;
  static const bitAnd = 0x16;
  static const bitOr = 0x17;
  static const bitXor = 0x18;
  static const bitNot = 0x19;
  static const shl = 0x1A;
  static const shr = 0x1B;
  static const ushr = 0x1C;
  static const addIntImm = 0x1D;

  // ── Float Arithmetic (0x20-0x24) ──
  static const addDbl = 0x20;
  static const subDbl = 0x21;
  static const mulDbl = 0x22;
  static const divDbl = 0x23;
  static const negDbl = 0x24;

  // ── Type Conversion & Boxing (0x25-0x2D) ──
  static const intToDbl = 0x25;
  static const dblToInt = 0x26;
  static const boxInt = 0x27;
  static const boxDouble = 0x28;
  static const boxBool = 0x29;
  static const unboxInt = 0x2A;
  static const unboxDouble = 0x2B;
  static const unboxBool = 0x2C;
  static const notBool = 0x2D;

  // ── Comparison (0x30-0x3F) ──
  static const ltInt = 0x30;
  static const leInt = 0x31;
  static const gtInt = 0x32;
  static const geInt = 0x33;
  static const eqInt = 0x34;
  static const ltDbl = 0x35;
  static const leDbl = 0x36;
  static const gtDbl = 0x37;
  static const geDbl = 0x38;
  static const eqDbl = 0x39;
  static const eqRef = 0x3A;
  static const eqGeneric = 0x3B;

  // ── Control Flow (0x40-0x4F) ──
  static const jump = 0x40;
  static const jumpIfTrue = 0x41;
  static const jumpIfFalse = 0x42;
  static const jumpIfNull = 0x43;
  static const jumpIfNnull = 0x44;
  static const jumpAx = 0x45;

  // ── Call & Return (0x50-0x5F) ──
  static const call = 0x50;
  static const callStatic = 0x51;
  static const callHost = 0x52;
  static const callVirtual = 0x53;
  static const callSuper = 0x54;
  static const returnRef = 0x55;
  static const returnVal = 0x56;
  static const returnNull = 0x57;

  // ── Object Operations (0x60-0x6F) ──
  static const getFieldRef = 0x60;
  static const setFieldRef = 0x61;
  static const getFieldVal = 0x62;
  static const setFieldVal = 0x63;
  static const newInstance = 0x64;
  static const instanceOf = 0x65;
  static const cast = 0x66;
  static const getFieldDyn = 0x67;
  static const setFieldDyn = 0x68;

  // ── Closure (0x70-0x77) ──
  static const closure = 0x70;
  static const closeUpvalue = 0x71;

  // ── Generics & Types (0x78-0x7F) ──
  static const pushIta = 0x78;
  static const pushFta = 0x79;
  static const loadTypeArg = 0x7A;
  static const instantiateType = 0x7B;
  static const createTypeArgs = 0x7C;
  static const allocGeneric = 0x7D;
  static const checkCovariant = 0x7E;

  // ── Async & Generators (0x80-0x8F) ──
  static const initAsync = 0x80;
  static const await_ = 0x81;
  static const asyncReturn = 0x82;
  static const asyncThrow = 0x83;
  static const initAsyncStar = 0x84;
  static const yield_ = 0x85;
  static const yieldStar = 0x86;
  static const initSyncStar = 0x87;
  static const awaitStreamNext = 0x88;

  // ── Collection (0x90-0x97) ──
  static const createList = 0x90;
  static const createMap = 0x91;
  static const createSet = 0x92;
  static const createRecord = 0x93;

  // ── String & Dynamic (0x98-0x9F) ──
  static const stringInterp = 0x98;
  static const addGeneric = 0x99;
  static const invokeDyn = 0x9A;

  // ── Global Variables (0xA0-0xA3) ──
  static const loadGlobal = 0xA0;
  static const storeGlobal = 0xA1;

  // ── Exception & Assert (0xA4-0xA7) ──
  static const throw_ = 0xA4;
  static const rethrow_ = 0xA5;
  static const assert_ = 0xA6;
  static const nullCheck = 0xA7;

  // ── System (0xFE-0xFF) ──
  static const wide = 0xFE;
  static const halt = 0xFF;
}
