/// Instruction encoding/decoding for the dartic 32-bit fixed-width ISA.
///
/// Five formats are supported:
/// - ABC:  [op:8][A:8][B:8][C:8]
/// - ABx:  [op:8][A:8][Bx:16]
/// - AsBx: [op:8][A:8][sBx:16]  (excess-K, K = 0x7FFF)
/// - Ax:   [op:8][Ax:24]
/// - sAx:  [op:8][sAx:24]       (excess-K, K = 0x7FFFFF)
///
/// See: docs/design/01-bytecode-isa.md
library;

// ── Encoding ──

/// Encodes an ABC-format instruction.
int encodeABC(int op, int a, int b, int c) =>
    op | (a << 8) | (b << 16) | (c << 24);

/// Encodes an ABx-format instruction (unsigned 16-bit Bx).
int encodeABx(int op, int a, int bx) => op | (a << 8) | (bx << 16);

/// Encodes an AsBx-format instruction (signed 16-bit sBx, excess-K).
///
/// Valid range: -32767 to +32768.
int encodeAsBx(int op, int a, int sbx) =>
    op | (a << 8) | ((sbx + 0x7FFF) << 16);

/// Encodes an Ax-format instruction (unsigned 24-bit Ax).
int encodeAx(int op, int ax) => op | (ax << 8);

/// Encodes an sAx-format instruction (signed 24-bit sAx, excess-K).
///
/// Valid range: -8388607 to +8388608.
int encodesAx(int op, int sax) => op | ((sax + 0x7FFFFF) << 8);

// ── Decoding ──

/// Extracts the 8-bit opcode from an instruction word.
int decodeOp(int instr) => instr & 0xFF;

/// Extracts the 8-bit A operand.
int decodeA(int instr) => (instr >> 8) & 0xFF;

/// Extracts the 8-bit B operand (ABC format).
int decodeB(int instr) => (instr >> 16) & 0xFF;

/// Extracts the 8-bit C operand (ABC format).
int decodeC(int instr) => (instr >> 24) & 0xFF;

/// Extracts the unsigned 16-bit Bx operand (ABx format).
int decodeBx(int instr) => (instr >> 16) & 0xFFFF;

/// Decodes the signed 16-bit sBx operand (AsBx format, excess-K).
///
/// Returns a value in the range -32767 to +32768.
int decodesBx(int instr) => decodeBx(instr) - 0x7FFF;

/// Extracts the unsigned 24-bit Ax operand.
int decodeAx(int instr) => (instr >> 8) & 0xFFFFFF;

/// Decodes the signed 24-bit sAx operand (sAx format, excess-K).
///
/// Returns a value in the range -8388607 to +8388608.
int decodesAx(int instr) => decodeAx(instr) - 0x7FFFFF;

// ── WIDE Prefix Encoding ──
//
// WIDE (0xFE) expands operand widths using a 3-word sequence:
//   word[0]: WIDE prefix   [0xFE][padding:24]
//   word[1]: extension word [high-order bits, layout varies by format]
//   word[2]: original instr [op:8][low-order operands:24]

const int _widePrefix = 0xFE;

/// Encodes a WIDE ABC instruction. Returns 3 words.
///
/// Extension word layout: `[_:8][extA:8][extB:8][extC:8]`
/// Combined: A = (extA << 8) | lowA, B = (extB << 8) | lowB, C = (extC << 8) | lowC.
/// Each operand extends from 8 bits to 16 bits (range 0-65535).
List<int> encodeWideABC(int op, int a, int b, int c) {
  final extWord = ((a >> 8) & 0xFF) << 8 |
      ((b >> 8) & 0xFF) << 16 |
      ((c >> 8) & 0xFF) << 24;
  final origWord = encodeABC(op, a & 0xFF, b & 0xFF, c & 0xFF);
  return [_widePrefix, extWord, origWord];
}

/// Decodes a WIDE ABC instruction from extension and original words.
///
/// Returns `(A, B, C)` with 16-bit ranges.
(int, int, int) decodeWideABC(int extWord, int origWord) {
  final a = ((extWord >> 8) & 0xFF) << 8 | decodeA(origWord);
  final b = ((extWord >> 16) & 0xFF) << 8 | decodeB(origWord);
  final c = ((extWord >> 24) & 0xFF) << 8 | decodeC(origWord);
  return (a, b, c);
}

/// Encodes a WIDE ABx instruction. Returns 3 words.
///
/// Extension word layout: `[_:8][extA:8][extBx:16]`
/// Combined: A = (extA << 8) | lowA (16 bits), Bx = (extBx << 16) | lowBx (32 bits).
List<int> encodeWideABx(int op, int a, int bx) {
  final extWord = ((a >> 8) & 0xFF) << 8 | ((bx >> 16) & 0xFFFF) << 16;
  final origWord = encodeABx(op, a & 0xFF, bx & 0xFFFF);
  return [_widePrefix, extWord, origWord];
}

/// Decodes a WIDE ABx instruction from extension and original words.
///
/// Returns `(A, Bx)` with A: 16-bit, Bx: 32-bit unsigned.
(int, int) decodeWideABx(int extWord, int origWord) {
  final a = ((extWord >> 8) & 0xFF) << 8 | decodeA(origWord);
  final bx = ((extWord >> 16) & 0xFFFF) << 16 | decodeBx(origWord);
  return (a, bx);
}

/// Encodes a WIDE AsBx instruction. Returns 3 words.
///
/// Extension word layout: `[_:8][extA:8][extSBx:16]`
/// Combined: A 16-bit, sBx 32-bit signed (excess-K, K = 0x7FFFFFFF).
List<int> encodeWideAsBx(int op, int a, int sbx) {
  final unsigned = sbx + 0x7FFFFFFF;
  final extWord = ((a >> 8) & 0xFF) << 8 | ((unsigned >> 16) & 0xFFFF) << 16;
  final origWord = encodeABx(op, a & 0xFF, unsigned & 0xFFFF);
  return [_widePrefix, extWord, origWord];
}

/// Decodes a WIDE AsBx instruction from extension and original words.
///
/// Returns `(A, sBx)` with A: 16-bit, sBx: signed 32-bit.
(int, int) decodeWideAsBx(int extWord, int origWord) {
  final a = ((extWord >> 8) & 0xFF) << 8 | decodeA(origWord);
  final unsigned = ((extWord >> 16) & 0xFFFF) << 16 | decodeBx(origWord);
  final sbx = unsigned - 0x7FFFFFFF;
  return (a, sbx);
}

/// Encodes a WIDE Ax instruction. Returns 3 words.
///
/// Extension word layout: `[_:8][extAx:24]`
/// Combined: Ax = (extAx << 24) | lowAx (48 bits unsigned).
List<int> encodeWideAx(int op, int ax) {
  final extWord = ((ax >> 24) & 0xFFFFFF) << 8;
  final origWord = encodeAx(op, ax & 0xFFFFFF);
  return [_widePrefix, extWord, origWord];
}

/// Decodes a WIDE Ax instruction from extension and original words.
///
/// Returns the unsigned 48-bit Ax value.
int decodeWideAx(int extWord, int origWord) {
  return ((extWord >> 8) & 0xFFFFFF) << 24 | decodeAx(origWord);
}

/// Encodes a WIDE sAx instruction. Returns 3 words.
///
/// Extension word layout: `[_:8][extAx:24]`
/// Combined: sAx 48-bit signed (excess-K, K = 0x7FFFFFFFFFFF).
List<int> encodeWidesAx(int op, int sax) {
  final unsigned = sax + 0x7FFFFFFFFFFF;
  final extWord = ((unsigned >> 24) & 0xFFFFFF) << 8;
  final origWord = encodeAx(op, unsigned & 0xFFFFFF);
  return [_widePrefix, extWord, origWord];
}

/// Decodes a WIDE sAx instruction from extension and original words.
///
/// Returns the signed 48-bit sAx value.
int decodeWidesAx(int extWord, int origWord) {
  final unsigned = ((extWord >> 8) & 0xFFFFFF) << 24 | decodeAx(origWord);
  return unsigned - 0x7FFFFFFFFFFF;
}
