library;

import 'dart:convert';
import 'dart:typed_data';

import 'constant_pool.dart';
import 'format.dart';
import 'module.dart';

/// Serializes a [DarticModule] to the `.darb` binary format.
///
/// Binary layout:
/// - Header (12 bytes): magic (UInt32) + version (UInt32) + CRC32 checksum (UInt32)
/// - Binding name table: count (UInt16) + entries (symbolName + argCount)
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
    final w = _ByteWriter();

    // Write all section data.
    _writeBindingTable(w, module.bindingNames);
    _writeConstantPool(w, module.constantPool);
    _writeFunctionTable(w, module.functions);
    w.writeUint32(module.entryFuncId);

    // Build payload and compute checksum.
    final payload = w.toBytes();
    final checksum = crc32(payload);

    // Build final output: header (12 bytes) + payload.
    final result = Uint8List(DarbFormat.headerSize + payload.length);
    final header = ByteData.sublistView(result);
    header.setUint32(0, DarbFormat.magic, Endian.little);
    header.setUint32(4, DarbFormat.version, Endian.little);
    header.setUint32(8, checksum, Endian.little);
    result.setAll(DarbFormat.headerSize, payload);
    return result;
  }

  // ── Binding Name Table ──

  void _writeBindingTable(_ByteWriter w, List<BindingEntry> bindings) {
    w.writeUint16(bindings.length);
    for (final entry in bindings) {
      w.writeString(entry.name);
      w.addByte(entry.argCount);
    }
  }

  // ── Constant Pool ──

  void _writeConstantPool(_ByteWriter w, ConstantPool pool) {
    // refs partition
    final refs = pool.refs;
    w.writeUint32(refs.length);
    for (final ref in refs) {
      if (ref == null) {
        w.addByte(0);
      } else if (ref is String) {
        w.addByte(1);
        w.writeString(ref);
      } else {
        throw StateError('Unsupported ref type: ${ref.runtimeType}');
      }
    }

    // ints partition
    final ints = pool.ints;
    w.writeUint32(ints.length);
    for (final value in ints) {
      w.writeInt64(value);
    }

    // doubles partition
    final doubles = pool.doubles;
    w.writeUint32(doubles.length);
    for (final value in doubles) {
      w.writeFloat64(value);
    }

    // names partition
    final names = pool.names;
    w.writeUint32(names.length);
    for (final name in names) {
      w.writeString(name);
    }
  }

  // ── Function Table ──

  void _writeFunctionTable(_ByteWriter w, List<DarticFuncProto> functions) {
    w.writeUint32(functions.length);
    for (final func in functions) {
      _writeFunction(w, func);
    }
  }

  void _writeFunction(_ByteWriter w, DarticFuncProto func) {
    w.writeString(func.name);
    w.writeUint32(func.funcId);
    w.writeUint32(func.paramCount);
    w.writeUint32(func.valueRegCount);
    w.writeUint32(func.refRegCount);

    // bytecode
    w.writeUint32(func.bytecode.length);
    for (final instr in func.bytecode) {
      w.writeUint32(instr);
    }

    // exception table
    w.writeUint32(func.exceptionTable.length);
    for (final handler in func.exceptionTable) {
      w.writeUint32(handler.startPC);
      w.writeUint32(handler.endPC);
      w.writeUint32(handler.handlerPC);
      w.writeInt32(handler.catchType);
      w.writeUint32(handler.valStackDP);
      w.writeUint32(handler.refStackDP);
      w.writeUint32(handler.exceptionReg);
      w.writeUint32(handler.stackTraceReg);
    }

    // IC table -- methodNameIndex + argCount persisted; runtime state resets
    w.writeUint32(func.icTable.length);
    for (final entry in func.icTable) {
      w.writeUint32(entry.methodNameIndex);
      w.writeUint32(entry.argCount);
    }

    // upvalue descriptors
    w.writeUint32(func.upvalueDescriptors.length);
    for (final desc in func.upvalueDescriptors) {
      w.addByte(desc.isLocal ? 1 : 0);
      w.writeUint32(desc.index);
    }
  }
}

/// A growable byte buffer with typed write methods for building binary output.
///
/// All multi-byte writes use little-endian byte order.
class _ByteWriter {
  final _builder = BytesBuilder(copy: false);

  void addByte(int byte) {
    _builder.addByte(byte);
  }

  void writeUint16(int value) {
    _builder.addByte(value & 0xFF);
    _builder.addByte((value >> 8) & 0xFF);
  }

  void writeUint32(int value) {
    _builder.addByte(value & 0xFF);
    _builder.addByte((value >> 8) & 0xFF);
    _builder.addByte((value >> 16) & 0xFF);
    _builder.addByte((value >> 24) & 0xFF);
  }

  void writeInt32(int value) {
    final bd = ByteData(4)..setInt32(0, value, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  void writeInt64(int value) {
    final bd = ByteData(8)..setInt64(0, value, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  void writeFloat64(double value) {
    final bd = ByteData(8)..setFloat64(0, value, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  void writeString(String value) {
    final encoded = utf8.encode(value);
    writeUint32(encoded.length);
    _builder.add(encoded);
  }

  Uint8List toBytes() => _builder.toBytes();
}
