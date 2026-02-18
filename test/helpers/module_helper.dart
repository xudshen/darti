import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/deserializer.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/bytecode/serializer.dart';

/// Builds a single-function [DarticModule] from bytecode.
///
/// Shared helper used across runtime tests.
DarticModule buildModule(
  Uint32List bytecode, {
  int valueRegCount = 0,
  int refRegCount = 0,
  int paramCount = 0,
  ConstantPool? constantPool,
}) {
  final proto = DarticFuncProto(
    funcId: 0,
    bytecode: bytecode,
    valueRegCount: valueRegCount,
    refRegCount: refRegCount,
    paramCount: paramCount,
  );
  return DarticModule(
    functions: [proto],
    constantPool: constantPool ?? ConstantPool(),
    entryFuncId: 0,
  );
}

/// Creates a [DarticModule] from explicit function list and constant pool.
///
/// Used by serialization and roundtrip tests.
DarticModule buildModuleFrom({
  List<DarticFuncProto>? functions,
  ConstantPool? pool,
  int entryFuncId = 0,
}) {
  return DarticModule(
    functions: functions ?? [],
    constantPool: pool ?? ConstantPool(),
    entryFuncId: entryFuncId,
  );
}

/// Serialize then deserialize a module (roundtrip).
DarticModule roundtripModule(DarticModule module) {
  final bytes = DarticSerializer().serialize(module);
  return DarticDeserializer().deserialize(bytes);
}

/// Creates a minimal [DarticFuncProto] with a single HALT instruction.
DarticFuncProto buildFuncProto({
  int funcId = 0,
  String name = 'test',
  int valueRegCount = 1,
  int refRegCount = 0,
  int paramCount = 0,
  Uint32List? bytecode,
  List<ICEntry> icTable = const [],
  List<ExceptionHandler> exceptionTable = const [],
  List<UpvalueDescriptor> upvalueDescriptors = const [],
}) {
  return DarticFuncProto(
    funcId: funcId,
    name: name,
    bytecode: bytecode ?? Uint32List.fromList([encodeAx(Op.halt, 0)]),
    valueRegCount: valueRegCount,
    refRegCount: refRegCount,
    paramCount: paramCount,
    icTable: icTable,
    exceptionTable: exceptionTable,
    upvalueDescriptors: upvalueDescriptors,
  );
}
