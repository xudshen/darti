import 'dart:typed_data';

import 'package:dartic/src/bytecode/format.dart';
import 'package:test/test.dart';

void main() {
  group('DarbFormat constants', () {
    test('magic constant is ASCII "DARB" (0x44415242)', () {
      expect(DarbFormat.magic, 0x44415242);
    });

    test('version number is 1', () {
      expect(DarbFormat.version, 1);
    });

    test('header size is 12 bytes (magic + version + checksum)', () {
      // magic: 4 bytes, version: 4 bytes, checksum: 4 bytes
      expect(DarbFormat.headerSize, 12);
    });

  });

  group('crc32', () {
    test('empty input yields 0x00000000', () {
      expect(crc32(Uint8List(0)), 0x00000000);
    });

    test('known test vector: "123456789" yields 0xCBF43926', () {
      // The canonical CRC32 check value for ASCII "123456789".
      final data = '123456789'.codeUnits;
      expect(crc32(data), 0xCBF43926);
    });

    test('single byte 0x00', () {
      expect(crc32([0x00]), 0xD202EF8D);
    });

    test('single byte 0xFF', () {
      expect(crc32([0xFF]), 0xFF000000);
    });

    test('all zeros (4 bytes)', () {
      expect(crc32([0, 0, 0, 0]), 0x2144DF1C);
    });

    test('all 0xFF (4 bytes)', () {
      expect(crc32([0xFF, 0xFF, 0xFF, 0xFF]), 0xFFFFFFFF);
    });

    test('accepts Uint8List input', () {
      final data = Uint8List.fromList('123456789'.codeUnits);
      expect(crc32(data), 0xCBF43926);
    });

    test('deterministic: same input always produces same output', () {
      final data = [1, 2, 3, 4, 5];
      final result1 = crc32(data);
      final result2 = crc32(data);
      expect(result1, result2);
    });
  });

  group('little-endian UInt32 encoding', () {
    test('magic encodes correctly in little-endian', () {
      // Verify that magic fits in a UInt32 and encodes correctly as LE.
      final buf = ByteData(4)..setUint32(0, DarbFormat.magic, Endian.little);
      final bytes = buf.buffer.asUint8List();

      // 0x44415242 ("DARB") in LE: [0x42, 0x52, 0x41, 0x44]
      expect(bytes[0], 0x42); // 'B'
      expect(bytes[1], 0x52); // 'R'
      expect(bytes[2], 0x41); // 'A'
      expect(bytes[3], 0x44); // 'D'
    });

    test('version encodes correctly in little-endian', () {
      final buf = ByteData(4)
        ..setUint32(0, DarbFormat.version, Endian.little);
      final bytes = buf.buffer.asUint8List();

      // version 1 in LE: [0x01, 0x00, 0x00, 0x00]
      expect(bytes[0], 0x01);
      expect(bytes[1], 0x00);
      expect(bytes[2], 0x00);
      expect(bytes[3], 0x00);
    });
  });
}
