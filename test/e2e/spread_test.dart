import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('Spread compilation', () {
    test('list spread', () async {
      final result = await compileAndRunWithHost('''
        Object main() {
          return [1, ...[2, 3], 4];
        }
      ''');
      expect(result, equals([1, 2, 3, 4]));
    });

    test('map spread', () async {
      final result = await compileAndRunWithHost('''
        Object main() {
          return {...{'a': 1}, 'b': 2};
        }
      ''');
      expect(result, equals({'a': 1, 'b': 2}));
    });

    test('collection if', () async {
      final result = await compileAndRunWithHost('''
        Object main() {
          return [1, if (true) 2, 3];
        }
      ''');
      expect(result, equals([1, 2, 3]));
    });

    test('collection for', () async {
      final result = await compileAndRunWithHost('''
        Object main() {
          return [for (var i = 0; i < 3; i++) i];
        }
      ''');
      expect(result, equals([0, 1, 2]));
    });
  });
}
