import 'dart:io';

import 'package:test/test.dart';

// Import the tool source directly (not a package import — tool/ is outside lib/).
// ignore: avoid_relative_lib_imports
import '../../tool/co19_runner.dart';

void main() {
  // Create a temporary directory tree that mimics the co19 layout for testing.
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('co19_discovery_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Helper: create a file at [relativePath] within [tempDir].
  void createFile(String relativePath) {
    final file = File('${tempDir.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('// test file\n');
  }

  group('TestDiscovery', () {
    group('basic pattern matching', () {
      test('matches files ending with _tNN.dart', () {
        createFile('Variables/constant_variable_t01.dart');
        createFile('Variables/constant_variable_t02.dart');
        createFile('Variables/constant_variable_t10.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(3));
        expect(
          entries.map((e) => e.path),
          everyElement(endsWith('.dart')),
        );
      });

      test('matches multi-digit test numbers (t01 through t99)', () {
        createFile('Variables/foo_t01.dart');
        createFile('Variables/foo_t42.dart');
        createFile('Variables/foo_t99.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(3));
      });

      test('matches definition_A01_t01 pattern (co19 common naming)', () {
        createFile('Expressions/Additive/definition_A01_t01.dart');
        createFile('Expressions/Additive/definition_A02_t03.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(2));
      });
    });

    group('exclusion rules', () {
      test('excludes non-.dart files (README.md, etc.)', () {
        createFile('Variables/README.md');
        createFile('Variables/constant_variable_t01.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(1));
        expect(entries.first.path, endsWith('constant_variable_t01.dart'));
      });

      test('excludes _lib.dart helper files', () {
        createFile('Expressions/foo_t01.dart');
        createFile('Expressions/foo_t01_lib.dart');
        createFile('Expressions/some_lib.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(1));
        expect(entries.first.path, endsWith('foo_t01.dart'));
      });

      test('excludes lib.dart files', () {
        createFile('Expressions/lib.dart');
        createFile('Expressions/foo_t01.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(1));
        expect(entries.first.path, endsWith('foo_t01.dart'));
      });

      test('excludes .dart files that do not match _tNN pattern', () {
        createFile('Variables/constant_variable.dart');
        createFile('Variables/helper.dart');
        createFile('Variables/constant_variable_t01.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(1));
        expect(entries.first.path, endsWith('constant_variable_t01.dart'));
      });

      test('excludes files with _t but no 2-3 digit suffix', () {
        // _t1.dart (1 digit — not a match)
        createFile('Variables/foo_t1.dart');
        // _t1234.dart (4 digits — not a match)
        createFile('Variables/foo_t1234.dart');
        // _t.dart (no digits — not a match)
        createFile('Variables/foo_t.dart');
        // _tab.dart (letters — not a match)
        createFile('Variables/foo_tab.dart');
        // Valid 2-digit match
        createFile('Variables/foo_t01.dart');
        // Valid 3-digit match
        createFile('Variables/foo_t123.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(2));
        expect(
          entries.map((e) => e.path.split('/').last).toSet(),
          equals({'foo_t01.dart', 'foo_t123.dart'}),
        );
      });

      test('matches 3-digit test numbers (t100 through t999)', () {
        createFile('Variables/foo_t100.dart');
        createFile('Variables/foo_t200.dart');
        createFile('Variables/foo_t999.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(3));
      });
    });

    group('directory recursion', () {
      test('recurses into nested subdirectories', () {
        createFile('Expressions/Additive/syntax_t01.dart');
        createFile(
          'Expressions/Assignment/Compound_Assignment/null_aware_t01.dart',
        );
        createFile('Variables/foo_t01.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(3));
      });

      test('empty directory returns empty list', () {
        // tempDir exists but has no files
        final entries = discoverTests([tempDir.path]);

        expect(entries, isEmpty);
      });

      test('directory with only non-test files returns empty list', () {
        createFile('Variables/README.md');
        createFile('Variables/helper_lib.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, isEmpty);
      });
    });

    group('multiple root directories', () {
      test('supports specifying multiple root directories', () {
        // Create two separate root directories
        final root1 = Directory('${tempDir.path}/root1')..createSync();
        final root2 = Directory('${tempDir.path}/root2')..createSync();

        createFile('root1/Variables/foo_t01.dart');
        createFile('root1/Variables/foo_t02.dart');
        createFile('root2/Statements/bar_t01.dart');

        final entries = discoverTests([root1.path, root2.path]);

        expect(entries, hasLength(3));
      });

      test('handles empty roots gracefully among non-empty ones', () {
        final root1 = Directory('${tempDir.path}/root1')..createSync();
        final root2 = Directory('${tempDir.path}/root2')..createSync();

        createFile('root1/Variables/foo_t01.dart');
        // root2 is empty

        final entries = discoverTests([root1.path, root2.path]);

        expect(entries, hasLength(1));
      });
    });

    group('TestEntry classification', () {
      test('extracts category from first-level directory', () {
        createFile('Variables/foo_t01.dart');
        createFile('Expressions/bar_t01.dart');
        createFile('Statements/baz_t01.dart');

        final entries = discoverTests([tempDir.path]);

        final categories = entries.map((e) => e.category).toSet();
        expect(categories, containsAll(['Variables', 'Expressions', 'Statements']));
      });

      test('extracts subcategory from second-level directory', () {
        createFile('Expressions/Additive_Expressions/syntax_t01.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(1));
        expect(entries.first.category, 'Expressions');
        expect(entries.first.subcategory, 'Additive_Expressions');
      });

      test('subcategory is empty when test is directly in category dir', () {
        createFile('Variables/constant_variable_t01.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(1));
        expect(entries.first.category, 'Variables');
        expect(entries.first.subcategory, '');
      });

      test('path contains the full absolute path to the file', () {
        createFile('Variables/foo_t01.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(1));
        expect(entries.first.path, '${tempDir.path}/Variables/foo_t01.dart');
      });

      test('deeply nested test uses first two levels for classification', () {
        createFile(
          'Expressions/Assignment/Compound_Assignment/null_aware_t01.dart',
        );

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(1));
        expect(entries.first.category, 'Expressions');
        expect(entries.first.subcategory, 'Assignment');
      });
    });

    group('result ordering', () {
      test('results are sorted by path for deterministic output', () {
        createFile('Variables/z_t01.dart');
        createFile('Variables/a_t01.dart');
        createFile('Expressions/m_t01.dart');

        final entries = discoverTests([tempDir.path]);

        expect(entries, hasLength(3));
        // Verify sorted by path
        for (var i = 0; i < entries.length - 1; i++) {
          expect(
            entries[i].path.compareTo(entries[i + 1].path),
            lessThan(0),
            reason: 'entries[$i].path should come before entries[${i + 1}].path',
          );
        }
      });
    });

    group('integration with real co19 (smoke test)', () {
      // This test verifies against the actual co19 vendor directory, if present.
      // Use Language/ as root so that Variables, Expressions, etc. are categories.
      final co19LangDir = Directory(
        '${Directory.current.path}/vendor/co19/Language',
      );

      test(
        'discovers tests across co19 Language directory',
        () {
          final entries = discoverTests([co19LangDir.path]);

          // There should be many test files across all categories.
          expect(entries.length, greaterThan(500));

          // All entries should match the test file pattern.
          for (final entry in entries) {
            expect(
              entry.path,
              matches(RegExp(r'_t\d{2,3}\.dart$')),
              reason: '${entry.path} should match _tNN(N).dart pattern',
            );
          }

          // Should contain Variables, Expressions, Statements categories.
          final categories = entries.map((e) => e.category).toSet();
          expect(categories, contains('Variables'));
          expect(categories, contains('Expressions'));
          expect(categories, contains('Statements'));

          // Variables should have ~111 test files.
          final variableTests =
              entries.where((e) => e.category == 'Variables');
          expect(variableTests.length, greaterThan(50));

          // Some should have subcategories.
          final withSubcategory =
              entries.where((e) => e.subcategory.isNotEmpty);
          expect(withSubcategory, isNotEmpty);
        },
        skip: !co19LangDir.existsSync()
            ? 'co19 vendor directory not available'
            : null,
      );
    });
  });

  group('TestEntry', () {
    test('toString provides human-readable representation', () {
      final entry = TestEntry(
        path: '/some/path/Variables/foo_t01.dart',
        category: 'Variables',
        subcategory: '',
      );
      final str = entry.toString();
      expect(str, contains('Variables'));
      expect(str, contains('foo_t01.dart'));
    });

    test('equality based on path', () {
      final a = TestEntry(
        path: '/path/foo_t01.dart',
        category: 'Variables',
        subcategory: '',
      );
      final b = TestEntry(
        path: '/path/foo_t01.dart',
        category: 'Variables',
        subcategory: '',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
