import 'package:dartic/src/bytecode/encoding.dart';
import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/compiler/register_allocator.dart';
import 'package:dartic/src/compiler/scope.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('Scope', () {
    late RegisterAllocator valAlloc;
    late RegisterAllocator refAlloc;

    setUp(() {
      valAlloc = RegisterAllocator();
      refAlloc = RegisterAllocator(initialOffset: 3);
    });

    test('lookup finds variable in current scope', () {
      final scope = Scope(valueAlloc: valAlloc, refAlloc: refAlloc);
      final decl = makeDummyVarDecl('x');
      scope.declare(decl, StackKind.intVal);
      final binding = scope.lookup(decl);
      expect(binding, isNotNull);
      expect(binding!.kind, StackKind.intVal);
    });

    test('lookup finds variable in parent scope', () {
      final parent = Scope(valueAlloc: valAlloc, refAlloc: refAlloc);
      final decl = makeDummyVarDecl('x');
      parent.declare(decl, StackKind.intVal);

      final child = Scope(
        valueAlloc: valAlloc,
        refAlloc: refAlloc,
        parent: parent,
      );
      final binding = child.lookup(decl);
      expect(binding, isNotNull);
    });

    test('lookup returns null for undeclared variable', () {
      final scope = Scope(valueAlloc: valAlloc, refAlloc: refAlloc);
      final decl = makeDummyVarDecl('x');
      expect(scope.lookup(decl), isNull);
    });

    test('release returns registers to allocator', () {
      final scope = Scope(valueAlloc: valAlloc, refAlloc: refAlloc);
      final decl1 = makeDummyVarDecl('x');
      final decl2 = makeDummyVarDecl('y');
      final b1 = scope.declare(decl1, StackKind.intVal);
      final b2 = scope.declare(decl2, StackKind.intVal);
      scope.release();

      // After release, the next alloc should reuse a freed register.
      final next = valAlloc.alloc();
      expect({b1.reg, b2.reg}, contains(next));
    });

    test('ref variable allocates from ref allocator', () {
      final scope = Scope(valueAlloc: valAlloc, refAlloc: refAlloc);
      final decl = makeDummyVarDecl('s');
      final binding = scope.declare(decl, StackKind.ref);
      // Ref allocator starts at 3 (ITA/FTA/this reservation).
      expect(binding.reg, 3);
      expect(binding.kind, StackKind.ref);
    });

    test('declareWithReg does not track register for release', () {
      final scope = Scope(valueAlloc: valAlloc, refAlloc: refAlloc);
      final decl = makeDummyVarDecl('param');
      scope.declareWithReg(decl, StackKind.intVal, 42);
      scope.release();
      // Since declareWithReg doesn't track, releasing shouldn't affect
      // the allocator — next alloc should be 0 (nothing freed).
      expect(valAlloc.alloc(), 0);
    });
  });

  group('function compilation with scope', () {
    test('no-param function: refRegCount=3 (ITA+FTA+this)', () async {
      final module = await compileDart('''
int f() => 42;
void main() {}
''');
      final f = findFunc(module, 'f');
      expect(f.refRegCount, 3, reason: 'ITA+FTA+this reserved');
    });

    test('int params go to value stack', () async {
      final module = await compileDart('''
int add(int a, int b) => a + b;
void main() {}
''');
      final f = findFunc(module, 'add');
      // 2 params (value) + 1 result (ADD_INT) = at least 3 value regs.
      expect(f.valueRegCount, greaterThanOrEqualTo(3));
      expect(f.paramCount, 2);
    });

    test('string param goes to ref stack', () async {
      final module = await compileDart('''
String f(String s) => s;
void main() {}
''');
      final f = findFunc(module, 'f');
      // ITA + FTA + this + s = at least 4 ref regs.
      expect(f.refRegCount, greaterThanOrEqualTo(4));
      expect(f.paramCount, 1);
    });

    test('mixed params allocate to correct stacks', () async {
      final module = await compileDart('''
int f(int a, String s, int b) => a + b;
void main() {}
''');
      final f = findFunc(module, 'f');
      // int a, int b → value stack (at least 2 params + 1 ADD_INT result = 3)
      expect(f.valueRegCount, greaterThanOrEqualTo(3));
      // String s → ref stack (3 reserved + 1 param = at least 4)
      expect(f.refRegCount, greaterThanOrEqualTo(4));
      expect(f.paramCount, 3);
    });

    test('local variables increase register count', () async {
      final module = await compileDart('''
int f() {
  int x = 1;
  int y = 2;
  int z = 3;
  return x + y + z;
}
void main() {}
''');
      final f = findFunc(module, 'f');
      // x, y, z locals + temporaries for addition.
      expect(f.valueRegCount, greaterThanOrEqualTo(3));
    });

    test('funcId and name are correct', () async {
      final module = await compileDart('''
int add(int a, int b) => a + b;
int mul(int a, int b) => a * b;
void main() {}
''');
      final add = findFunc(module, 'add');
      final mul = findFunc(module, 'mul');
      expect(add.name, 'add');
      expect(mul.name, 'mul');
      expect(add.funcId, isNot(mul.funcId));
    });

    test('entry function bytecode ends with HALT', () async {
      final module = await compileDart('''
void main() {}
''');
      final f = findFunc(module, 'main');
      final code = f.bytecode;
      // Last instruction should be HALT.
      expect(decodeOp(code.last), Op.halt);
    });

    test('non-entry function bytecode ends with RETURN_NULL safety net',
        () async {
      final module = await compileDart('''
void f() {}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;
      expect(decodeOp(code.last), Op.returnNull);
    });
  });
}
