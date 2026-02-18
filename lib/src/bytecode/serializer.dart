import 'dart:convert';
import 'dart:typed_data';

import 'constant_pool.dart';
import 'format.dart';
import 'module.dart';

/// Serializes a [DarticModule] to the `.darticb` binary format.
///
/// Binary layout:
/// - Header (12 bytes): magic (UInt32) + version (UInt32) + CRC32 checksum (UInt32)
/// - Constant pool: refs, ints, doubles, names
/// - Function table: count + each function's metadata, bytecode, tables
/// - Entry point: funcId (UInt32)
///
/// All multi-byte values are little-endian.
///
/// See: docs/design/01-bytecode-isa.md "编译产物格式"
class DarticSerializer {
  /// Serializes [module] to a `Uint8List`.
  Uint8List serialize(DarticModule module) {
    final writer = _ByteWriter();

    // Write all section data (constant pool, function table, entry point).
    _writeConstantPool(writer, module.constantPool);
    _writeFunctionTable(writer, module.functions);
    _writeUint32(writer, module.entryFuncId);

    // Build payload and compute checksum.
    final payload = writer.toBytes();
    final checksum = crc32(payload);

    // Build final output: header + payload.
    final header = _ByteWriter();
    _writeUint32(header, DarticBFormat.magic);
    _writeUint32(header, DarticBFormat.version);
    _writeUint32(header, checksum);

    final headerBytes = header.toBytes();
    final result = Uint8List(headerBytes.length + payload.length);
    result.setAll(0, headerBytes);
    result.setAll(headerBytes.length, payload);
    return result;
  }

  // ── Constant Pool ──

  void _writeConstantPool(_ByteWriter w, ConstantPool pool) {
    // refs partition
    final refs = pool.refs;
    _writeUint32(w, refs.length);
    for (final ref in refs) {
      if (ref == null) {
        // Tag 0 for null.
        w.addByte(0);
      } else if (ref is String) {
        // Tag 1 for string.
        w.addByte(1);
        _writeString(w, ref);
      } else {
        // Phase 1: only null and String are expected in refs.
        throw StateError('Unsupported ref type: ${ref.runtimeType}');
      }
    }

    // ints partition
    final ints = pool.ints;
    _writeUint32(w, ints.length);
    for (var i = 0; i < ints.length; i++) {
      _writeInt64(w, ints[i]);
    }

    // doubles partition
    final doubles = pool.doubles;
    _writeUint32(w, doubles.length);
    for (var i = 0; i < doubles.length; i++) {
      _writeFloat64(w, doubles[i]);
    }

    // names partition
    final names = pool.names;
    _writeUint32(w, names.length);
    for (final name in names) {
      _writeString(w, name);
    }
  }

  // ── Function Table ──

  void _writeFunctionTable(_ByteWriter w, List<DarticFuncProto> functions) {
    _writeUint32(w, functions.length);
    for (final func in functions) {
      _writeFunction(w, func);
    }
  }

  void _writeFunction(_ByteWriter w, DarticFuncProto func) {
    // name
    _writeString(w, func.name);
    // funcId
    _writeUint32(w, func.funcId);
    // paramCount
    _writeUint32(w, func.paramCount);
    // valueRegCount
    _writeUint32(w, func.valueRegCount);
    // refRegCount
    _writeUint32(w, func.refRegCount);

    // bytecode
    _writeUint32(w, func.bytecode.length);
    for (var i = 0; i < func.bytecode.length; i++) {
      _writeUint32(w, func.bytecode[i]);
    }

    // exception table
    _writeUint32(w, func.exceptionTable.length);
    for (final handler in func.exceptionTable) {
      _writeUint32(w, handler.startPC);
      _writeUint32(w, handler.endPC);
      _writeUint32(w, handler.handlerPC);
      _writeInt32(w, handler.catchType);
      _writeUint32(w, handler.valStackDP);
      _writeUint32(w, handler.refStackDP);
      _writeUint32(w, handler.exceptionReg);
      _writeUint32(w, handler.stackTraceReg);
    }

    // IC table — only serialize methodNameIndex (runtime state is not persisted)
    _writeUint32(w, func.icTable.length);
    for (final entry in func.icTable) {
      _writeUint32(w, entry.methodNameIndex);
    }

    // upvalue descriptors
    _writeUint32(w, func.upvalueDescriptors.length);
    for (final desc in func.upvalueDescriptors) {
      w.addByte(desc.isLocal ? 1 : 0);
      _writeUint32(w, desc.index);
    }
  }

  // ── Primitive writers ──

  void _writeUint32(_ByteWriter w, int value) {
    w.addByte(value & 0xFF);
    w.addByte((value >> 8) & 0xFF);
    w.addByte((value >> 16) & 0xFF);
    w.addByte((value >> 24) & 0xFF);
  }

  void _writeInt32(_ByteWriter w, int value) {
    // Reinterpret as unsigned for byte extraction.
    final unsigned = value & 0xFFFFFFFF;
    _writeUint32(w, unsigned);
  }

  void _writeInt64(_ByteWriter w, int value) {
    final bd = ByteData(8)..setInt64(0, value, Endian.little);
    for (var i = 0; i < 8; i++) {
      w.addByte(bd.getUint8(i));
    }
  }

  void _writeFloat64(_ByteWriter w, double value) {
    final bd = ByteData(8)..setFloat64(0, value, Endian.little);
    for (var i = 0; i < 8; i++) {
      w.addByte(bd.getUint8(i));
    }
  }

  void _writeString(_ByteWriter w, String value) {
    final encoded = utf8.encode(value);
    _writeUint32(w, encoded.length);
    for (final byte in encoded) {
      w.addByte(byte);
    }
  }
}

/// A growable byte buffer for building binary output.
class _ByteWriter {
  final _builder = BytesBuilder(copy: false);

  void addByte(int byte) {
    _builder.addByte(byte);
  }

  Uint8List toBytes() => _builder.toBytes();
}
