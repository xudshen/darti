/// Binary format constants and checksum for `.darticb` files.
///
/// Defines the file magic, version, and CRC32 checksum
/// used by the dartic bytecode serializer/deserializer.
///
/// See: docs/design/01-bytecode-isa.md
library;

import 'dart:typed_data';

/// Binary format constants for `.darticb` files.
abstract final class DarticBFormat {
  /// File magic: 0xDAB71B00.
  ///
  /// Chosen as a memorable mnemonic (loosely "DART1B00") that is unlikely
  /// to collide with other binary formats.
  static const int magic = 0xDAB71B00;

  /// Current format version.
  static const int version = 1;

  /// File header size in bytes (magic + version + checksum = 12).
  static const int headerSize = 12;

}

/// CRC32 lookup table (IEEE 802.3 polynomial 0xEDB88320, reflected).
///
/// Uses [Uint32List] for type safety (immutable length) and faster
/// typed-data access compared to generic `List<int>`.
final Uint32List _crc32Table = _buildTable();

Uint32List _buildTable() {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var crc = i;
    for (var j = 0; j < 8; j++) {
      if (crc & 1 != 0) {
        crc = (crc >>> 1) ^ 0xEDB88320;
      } else {
        crc = crc >>> 1;
      }
    }
    table[i] = crc;
  }
  return table;
}

/// CRC32 checksum computation (IEEE 802.3 polynomial).
///
/// Uses the standard reflected polynomial 0xEDB88320 with a 256-entry
/// lookup table for efficient computation.
///
/// Used to verify `.darticb` file integrity.
int crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = _crc32Table[(crc ^ byte) & 0xFF] ^ (crc >>> 8);
  }
  return crc ^ 0xFFFFFFFF;
}
