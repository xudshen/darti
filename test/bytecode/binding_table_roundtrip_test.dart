import 'dart:typed_data';

import 'package:dartic/src/bytecode/constant_pool.dart';
import 'package:dartic/src/bytecode/deserializer.dart';
import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/class_info.dart';
import 'package:dartic/src/bytecode/serializer.dart';
import 'package:test/test.dart';

DarticModule _roundtrip(DarticModule module) {
  final bytes = DarticSerializer().serialize(module);
  return DarticDeserializer().deserialize(bytes);
}

void main() {
  group('Binding table roundtrip', () {
    test('empty binding table (bindingCount=0)', () {
      final module = DarticModule(
        functions: [
          DarticFuncProto(
            funcId: 0,
            bytecode: Uint32List.fromList([encodeAx(Op.halt, 0)]),
            valueRegCount: 1,
            refRegCount: 0,
            paramCount: 0,
          ),
        ],
        constantPool: ConstantPool(),
        entryFuncId: 0,
        bindingNames: [],
      );

      final result = _roundtrip(module);
      expect(result.bindingNames, isEmpty);
    });

    test('single entry binding table', () {
      final module = DarticModule(
        functions: [
          DarticFuncProto(
            funcId: 0,
            bytecode: Uint32List.fromList([encodeAx(Op.halt, 0)]),
            valueRegCount: 1,
            refRegCount: 0,
            paramCount: 0,
          ),
        ],
        constantPool: ConstantPool(),
        entryFuncId: 0,
        bindingNames: [
          BindingEntry(name: 'dart:core::::print#1', argCount: 1),
        ],
      );

      final result = _roundtrip(module);
      expect(result.bindingNames.length, equals(1));
      expect(result.bindingNames[0].name, equals('dart:core::::print#1'));
      expect(result.bindingNames[0].argCount, equals(1));
    });

    test('multiple entry binding table', () {
      final module = DarticModule(
        functions: [
          DarticFuncProto(
            funcId: 0,
            bytecode: Uint32List.fromList([encodeAx(Op.halt, 0)]),
            valueRegCount: 1,
            refRegCount: 0,
            paramCount: 0,
          ),
        ],
        constantPool: ConstantPool(),
        entryFuncId: 0,
        bindingNames: [
          BindingEntry(name: 'dart:core::::print#1', argCount: 1),
          BindingEntry(name: 'dart:core::int::toString#0', argCount: 1),
          BindingEntry(name: 'dart:core::String::length#0', argCount: 1),
        ],
      );

      final result = _roundtrip(module);
      expect(result.bindingNames.length, equals(3));
      expect(result.bindingNames[0].name, equals('dart:core::::print#1'));
      expect(result.bindingNames[0].argCount, equals(1));
      expect(
          result.bindingNames[1].name, equals('dart:core::int::toString#0'));
      expect(result.bindingNames[1].argCount, equals(1));
      expect(
          result.bindingNames[2].name, equals('dart:core::String::length#0'));
      expect(result.bindingNames[2].argCount, equals(1));
    });

    test('symbol names with special characters (:: and #)', () {
      final module = DarticModule(
        functions: [
          DarticFuncProto(
            funcId: 0,
            bytecode: Uint32List.fromList([encodeAx(Op.halt, 0)]),
            valueRegCount: 1,
            refRegCount: 0,
            paramCount: 0,
          ),
        ],
        constantPool: ConstantPool(),
        entryFuncId: 0,
        bindingNames: [
          BindingEntry(
              name: 'dart:core::List::add#1', argCount: 2),
          BindingEntry(
              name: 'dart:core::Map::[]=::operator#2', argCount: 3),
        ],
      );

      final result = _roundtrip(module);
      expect(result.bindingNames.length, equals(2));
      expect(
          result.bindingNames[0].name, equals('dart:core::List::add#1'));
      expect(result.bindingNames[0].argCount, equals(2));
      expect(result.bindingNames[1].name,
          equals('dart:core::Map::[]=::operator#2'));
      expect(result.bindingNames[1].argCount, equals(3));
    });

    test('full module roundtrip with bindings + functions + constants + classes',
        () {
      final pool = ConstantPool();
      pool.addRef('hello');
      pool.addInt(42);
      pool.addName('test');

      final module = DarticModule(
        functions: [
          DarticFuncProto(
            funcId: 0,
            name: 'main',
            bytecode: Uint32List.fromList([
              encodeABx(Op.callHost, 0, 0),
              encodeABC(Op.halt, 0, StackKind.ref.index + 1, 0),
            ]),
            valueRegCount: 2,
            refRegCount: 2,
            paramCount: 0,
          ),
        ],
        constantPool: pool,
        entryFuncId: 0,
        bindingNames: [
          BindingEntry(name: 'dart:core::::print#1', argCount: 1),
          BindingEntry(name: 'dart:core::Object::toString#0', argCount: 1),
        ],
      );

      final result = _roundtrip(module);

      // Verify binding table survived roundtrip.
      expect(result.bindingNames.length, equals(2));
      expect(result.bindingNames[0].name, equals('dart:core::::print#1'));
      expect(result.bindingNames[0].argCount, equals(1));
      expect(result.bindingNames[1].name,
          equals('dart:core::Object::toString#0'));
      expect(result.bindingNames[1].argCount, equals(1));

      // Verify other sections also survived.
      expect(result.functions.length, equals(1));
      expect(result.functions[0].name, equals('main'));
      expect(result.constantPool.refs.length, equals(1));
      expect(result.constantPool.ints.length, equals(1));
      expect(result.entryFuncId, equals(0));
    });
  });
}
