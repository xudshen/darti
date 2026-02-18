import 'dart:typed_data';

import 'package:dartic/src/bytecode/format.dart';
import 'package:test/test.dart';

void main() {
  group('DarticBFormat constants', () {
    test('magic constant is 0xDAB71B00', () {
      expect(DarticBFormat.magic, 0xDAB71B00);
    });

    test('version number is 1', () {
      expect(DarticBFormat.version, 1);
    });

    test('header size is 12 bytes (magic + version + checksum)', () {
      // magic: 4 bytes, version: 4 bytes, checksum: 4 bytes
      expect(DarticBFormat.headerSize, 12);
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
      final buf = ByteData(4)..setUint32(0, DarticBFormat.magic, Endian.little);
      final bytes = buf.buffer.asUint8List();

      // 0xDAB71B00 in LE: [0x00, 0x1B, 0xB7, 0xDA]
      expect(bytes[0], 0x00);
      expect(bytes[1], 0x1B);
      expect(bytes[2], 0xB7);
      expect(bytes[3], 0xDA);
    });

    test('version encodes correctly in little-endian', () {
      final buf = ByteData(4)
        ..setUint32(0, DarticBFormat.version, Endian.little);
      final bytes = buf.buffer.asUint8List();

      // version 1 in LE: [0x01, 0x00, 0x00, 0x00]
      expect(bytes[0], 0x01);
      expect(bytes[1], 0x00);
      expect(bytes[2], 0x00);
      expect(bytes[3], 0x00);
    });
  });
}
