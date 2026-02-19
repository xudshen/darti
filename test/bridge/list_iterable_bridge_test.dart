import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_bindings.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

Future<Object?> _run(String source) async {
  final module = await compileDart(source);
  final bindings = HostBindings();
  CoreBindings.registerAll(bindings);
  final interp = DarticInterpreter(hostBindings: bindings);
  interp.execute(module);
  return interp.entryResult;
}

void main() {
  group('List bridge', () {
    test('[1,2,3].length', () async {
      final result = await _run('''
int main() {
  List<int> list = [1, 2, 3];
  return list.length;
}
''');
      expect(result, 3);
    });

    test('[].isEmpty', () async {
      final result = await _run('''
bool main() {
  List<int> list = [];
  return list.isEmpty;
}
''');
      expect(result, true);
    });

    test('[10,20,30][1]', () async {
      final result = await _run('''
int main() {
  List<int> list = [10, 20, 30];
  return list[1];
}
''');
      expect(result, 20);
    });

    test('list[0] = 99', () async {
      final result = await _run('''
int main() {
  List<int> list = [10, 20, 30];
  list[0] = 99;
  return list[0];
}
''');
      expect(result, 99);
    });

    test('list.add and list.length', () async {
      final result = await _run('''
int main() {
  List<int> list = [1, 2];
  list.add(3);
  return list.length;
}
''');
      expect(result, 3);
    });

    test('list.contains(2)', () async {
      final result = await _run('''
bool main() {
  List<int> list = [1, 2, 3];
  return list.contains(2);
}
''');
      expect(result, true);
    });

    test('list.indexOf(2)', () async {
      final result = await _run('''
int main() {
  List<int> list = [1, 2, 3];
  return list.indexOf(2);
}
''');
      expect(result, 1);
    });

    test('[1,2,3].join(",")', () async {
      final result = await _run('''
String main() {
  List<int> list = [1, 2, 3];
  return list.join(',');
}
''');
      expect(result, '1,2,3');
    });

    test('[1,2].first', () async {
      final result = await _run('''
int main() {
  List<int> list = [1, 2];
  return list.first;
}
''');
      expect(result, 1);
    });

    test('[1,2].last', () async {
      final result = await _run('''
int main() {
  List<int> list = [1, 2];
  return list.last;
}
''');
      expect(result, 2);
    });

    test('list.removeAt(0)', () async {
      final result = await _run('''
int main() {
  List<int> list = [10, 20, 30];
  list.removeAt(0);
  return list[0];
}
''');
      expect(result, 20);
    });

    test('list.removeLast()', () async {
      final result = await _run('''
int main() {
  List<int> list = [10, 20, 30];
  list.removeLast();
  return list.length;
}
''');
      expect(result, 2);
    });

    test('List.filled(3, 0)', () async {
      final result = await _run('''
int main() {
  List<int> list = List.filled(3, 0);
  return list.length;
}
''');
      expect(result, 3);
    });
  });
}
