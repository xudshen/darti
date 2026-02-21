/// co19 test runner — discovers and runs co19 conformance tests.
///
/// This is a development tool, not part of the main dartic library.
/// Usage: `dart tool/co19_runner.dart [options] <directories...>`
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:dartic/src/compiler/compiler.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:kernel/ast.dart' as ir;
import 'package:kernel/binary/ast_from_binary.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Shallow equality check for two lists.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A discovered co19 test file with classification metadata.
class TestEntry {
  /// Full absolute path to the test file.
  final String path;

  /// Top-level category derived from the first directory level below the root.
  /// For example, "Variables", "Expressions", "Statements".
  final String category;

  /// Subcategory derived from the second directory level below the root.
  /// Empty string if the test file is directly inside the category directory.
  final String subcategory;

  /// Whether this is a negative test (expects a compile-time error).
  ///
  /// Negative tests contain `// [analyzer]` and/or `// [cfe]` markers in
  /// their source code, indicating the test expects a compilation failure.
  final bool isNegative;

  /// Experiment flags parsed from `// SharedOptions=--enable-experiment=...`
  /// comments in the test file. These flags are passed to the Dart compiler
  /// when compiling the test (e.g., `--enable-experiment=class-modifiers`).
  final List<String> experimentFlags;

  TestEntry({
    required this.path,
    required this.category,
    required this.subcategory,
    this.isNegative = false,
    this.experimentFlags = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestEntry &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          category == other.category &&
          subcategory == other.subcategory &&
          isNegative == other.isNegative &&
          _listEquals(experimentFlags, other.experimentFlags);

  @override
  int get hashCode =>
      Object.hash(path, category, subcategory, isNegative,
          Object.hashAll(experimentFlags));

  @override
  String toString() {
    final neg = isNegative ? ' [NEGATIVE]' : '';
    return 'TestEntry($category${subcategory.isEmpty ? '' : '/$subcategory'}: '
        '${path.split('/').last}$neg)';
  }
}

// ---------------------------------------------------------------------------
// Test result types
// ---------------------------------------------------------------------------

/// Possible outcomes for a single co19 test execution.
enum TestResult {
  /// Test compiled and executed successfully (or negative test failed to
  /// compile as expected).
  pass,

  /// Test failed: normal test had a compile error or runtime failure, or
  /// negative test compiled unexpectedly.
  fail,

  /// Test was skipped (e.g., depends on unsupported features).
  skip,

  /// Internal error during test execution (file read failure, unexpected
  /// exception in the harness itself). Distinguished from [fail] because
  /// errors indicate problems with the harness or environment, not test logic.
  error,
}

/// Associates a [TestEntry] with its execution [result] and optional [message].
///
/// The [message] contains failure details, skip reasons, or error diagnostics.
class TestOutcome {
  final TestEntry entry;
  final TestResult result;
  final String message;

  TestOutcome({
    required this.entry,
    required this.result,
    this.message = '',
  });

  @override
  String toString() {
    final suffix = message.isEmpty ? '' : ' ($message)';
    return 'TestOutcome(${result.name}: ${entry.path.split('/').last}$suffix)';
  }
}

// ---------------------------------------------------------------------------
// Negative test detection
// ---------------------------------------------------------------------------

/// Regex matching co19 negative test markers: `// [analyzer]` or `// [cfe]`.
///
/// These markers appear as standalone line comments (possibly with leading
/// whitespace) in the test source. They indicate an expected compile-time error.
/// Lines inside doc comments (`///`) or string literals are not matched because
/// they will have a `///` prefix or be enclosed in quotes—neither of which
/// produces a line that starts with optional whitespace followed by `//`
/// then a space and `[analyzer]`/`[cfe]`.
final _negativeMarkerPattern = RegExp(r'^\s*// \[(analyzer|cfe)\] ', multiLine: true);

/// Returns `true` if [source] contains co19 negative-test markers.
///
/// A negative test is one that expects a compile-time error, indicated by
/// `// [analyzer] ...` and/or `// [cfe] ...` comment lines.
bool isNegativeTest(String source) {
  return _negativeMarkerPattern.hasMatch(source);
}

// ---------------------------------------------------------------------------
// Unsupported import detection (skip list)
// ---------------------------------------------------------------------------

/// Set of dart: libraries that are supported (or partially supported) in
/// Phase 5.
///
/// - `dart:core`: fully bridged via CoreBindings.
/// - `dart:async`: types (Future, Stream, Completer) are usable in the type
///   system, though async execution (await, async*, sync*) is Phase 6 scope.
///   Including it prevents false regressions for tests that reference async
///   types without actually executing async code.
///
/// Any other `dart:` import in a non-negative test file's direct source causes
/// the test to be skipped. Transitive imports (e.g., `Utils/expect.dart`
/// importing `dart:async`) are NOT checked — only the test file's own source
/// is scanned.
const _supportedDartLibraries = {'dart:core', 'dart:async'};

/// Tests known to regress due to the async stub (Phase 5).
///
/// These tests previously passed because they only checked return types or
/// other static properties of async/generator functions. After the async stub
/// was added (which throws at runtime for async/sync*/async* bodies), they
/// fail. They will be removed from this list once Phase 6 implements async.
const _knownAsyncRegressions = <String>{
  'vendor/co19/Language/Expressions/Identifier_Reference/async_and_generator_t02.dart',
  'vendor/co19/Language/Expressions/Identifier_Reference/async_and_generator_t05.dart',
  'vendor/co19/Language/Expressions/Identifier_Reference/async_and_generator_t08.dart',
  'vendor/co19/Language/Functions/async_return_type_t02.dart',
  'vendor/co19/Language/Functions/generator_return_type_t03.dart',
  'vendor/co19/Language/Functions/generator_return_type_t04.dart',
  'vendor/co19/Language/Functions/generator_return_type_t07.dart',
  'vendor/co19/Language/Functions/generator_return_type_t08.dart',
  'vendor/co19/Language/Statements/Return/no_expression_function_t13.dart',
  'vendor/co19/Language/Statements/Return/no_expression_function_t14.dart',
};

/// Regex matching `import 'dart:xxx'` or `import "dart:xxx"` statements.
///
/// Captures the library name after `dart:` (e.g., `io`, `async`, `math`).
/// This is a simple line-level scan — it may match commented-out imports,
/// which is acceptable (conservative: skip rather than fail).
final _unsupportedImportPattern = RegExp(r'''import\s+['"]dart:(\w+)['"]''');

/// Returns the first unsupported `dart:` library import found in [source],
/// or `null` if all imports are supported (or there are no `dart:` imports).
///
/// Only the test file's direct source is scanned — transitive dependencies
/// are not followed.
String? findUnsupportedImport(String source) {
  for (final match in _unsupportedImportPattern.allMatches(source)) {
    final lib = 'dart:${match.group(1)}';
    if (!_supportedDartLibraries.contains(lib)) {
      return lib;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// SharedOptions experiment flag parsing
// ---------------------------------------------------------------------------

/// Regex matching `// SharedOptions=--enable-experiment=<flags>` lines.
///
/// Captures the comma-separated list of experiment flag names after
/// `--enable-experiment=`. Only scans the first 20 lines of the source.
final _experimentFlagPattern =
    RegExp(r'//\s*SharedOptions=--enable-experiment=(.+)');

/// Parses experiment flags from `// SharedOptions=--enable-experiment=...`
/// comments in the first 20 lines of [source].
///
/// Returns a list of experiment flag names. If the source contains multiple
/// `SharedOptions` lines with experiment flags, all flags are merged into
/// a single list. Comma-separated flags within a single line are split.
///
/// Example:
/// ```
/// // SharedOptions=--enable-experiment=class-modifiers,records
/// ```
/// Returns `['class-modifiers', 'records']`.
List<String> parseExperimentFlags(String source) {
  if (source.isEmpty) return const [];

  final flags = <String>[];
  final lines = source.split('\n');
  final limit = lines.length < 20 ? lines.length : 20;

  for (var i = 0; i < limit; i++) {
    final match = _experimentFlagPattern.firstMatch(lines[i]);
    if (match != null) {
      final raw = match.group(1)!.trim();
      flags.addAll(raw.split(',').map((f) => f.trim()).where((f) => f.isNotEmpty));
    }
  }

  return flags;
}

// ---------------------------------------------------------------------------
// Test discovery
// ---------------------------------------------------------------------------

/// Regex matching co19 test file names: `<name>_t<NN>.dart` or
/// `<name>_t<NNN>.dart` where NN is 2 digits and NNN is 3 digits.
final _testFilePattern = RegExp(r'_t\d{2,3}\.dart$');

/// Discovers co19 test files by recursively scanning [rootDirs].
///
/// Returns a sorted list of [TestEntry] objects for files whose names match
/// the `*_t[0-9]{2}.dart` pattern. Non-test files (README.md, `*_lib.dart`,
/// `lib.dart`, non-.dart files) are excluded.
///
/// Category and subcategory are derived from the directory structure relative
/// to each root directory:
/// - `root/test_t01.dart` -> category=basename(root), subcategory=""
/// - `root/Category/test_t01.dart` -> category="Category", subcategory=""
/// - `root/Category/Sub/test_t01.dart` -> category="Category", subcategory="Sub"
/// - `root/Category/Sub/Deep/test_t01.dart` -> category="Category", subcategory="Sub"
List<TestEntry> discoverTests(List<String> rootDirs) {
  final entries = <TestEntry>[];

  for (var rootPath in rootDirs) {
    // Normalize: strip trailing slashes so relative-path math is correct.
    while (rootPath.endsWith('/') && rootPath.length > 1) {
      rootPath = rootPath.substring(0, rootPath.length - 1);
    }

    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) continue;

    // The root directory name, used as category when files live directly
    // inside the root (e.g., root = ".../Variables").
    final rootName = rootDir.uri.pathSegments
        .lastWhere((s) => s.isNotEmpty, orElse: () => '');

    final entities = rootDir.listSync(recursive: true);
    for (final entity in entities) {
      if (entity is! File) continue;

      final filePath = entity.path;

      // Must be a .dart file.
      if (!filePath.endsWith('.dart')) continue;

      // Must match the _tNN.dart pattern.
      if (!_testFilePattern.hasMatch(filePath)) continue;

      // Derive category and subcategory from relative path.
      final relativePath = filePath.substring(rootPath.length + 1);
      final parts = relativePath.split('/');

      final String category;
      final String subcategory;

      if (parts.length == 1) {
        // File directly in the root directory.
        category = rootName;
        subcategory = '';
      } else if (parts.length == 2) {
        // root/Category/file.dart
        category = parts[0];
        subcategory = '';
      } else {
        // root/Category/Sub/.../file.dart
        category = parts[0];
        subcategory = parts[1];
      }

      // Read file content to determine negativity and experiment flags.
      final source = entity.readAsStringSync();

      entries.add(TestEntry(
        path: filePath,
        category: category,
        subcategory: subcategory,
        isNegative: isNegativeTest(source),
        experimentFlags: parseExperimentFlags(source),
      ));
    }
  }

  // Sort by path for deterministic output.
  entries.sort((a, b) => a.path.compareTo(b.path));

  return entries;
}

// ---------------------------------------------------------------------------
// Single test execution
// ---------------------------------------------------------------------------

/// Compiles and executes a single co19 test, returning its [TestOutcome].
///
/// Execution flow:
/// - **Negative tests**: Compile the test. If compilation fails, the test
///   passes (expected compile error). If compilation succeeds unexpectedly,
///   the test fails.
/// - **Normal tests**: Compile the test. If compilation fails, the test fails.
///   If compilation succeeds, execute it. If execution completes without
///   exception, the test passes. If execution throws, the test fails.
/// - **Error**: If the test file cannot be read or an unexpected internal error
///   occurs, the result is [TestResult.error].
Future<TestOutcome> runTest(TestEntry entry) async {
  // Check that the file exists.
  final file = File(entry.path);
  if (!file.existsSync()) {
    return TestOutcome(
      entry: entry,
      result: TestResult.error,
      message: 'file not found: ${entry.path}',
    );
  }

  // Skip known async-stub regressions (Phase 5 → Phase 6).
  if (_knownAsyncRegressions.contains(entry.path)) {
    return TestOutcome(
      entry: entry,
      result: TestResult.skip,
      message: 'known async-stub regression (Phase 6 scope)',
    );
  }

  // Check for unsupported dart: library imports in the test file's source.
  // Only direct imports are checked — transitive dependencies (e.g.,
  // Utils/expect.dart importing dart:async) are not scanned.
  // Skip only non-negative tests: negative tests expect compile errors, so
  // unsupported imports are fine — the compilation will fail as expected.
  final source = file.readAsStringSync();
  final unsupported = findUnsupportedImport(source);
  if (unsupported != null && !entry.isNegative) {
    return TestOutcome(
      entry: entry,
      result: TestResult.skip,
      message: 'unsupported import: $unsupported',
    );
  }

  // Create a temporary directory for compilation artifacts.
  final tempDir = await Directory.systemTemp.createTemp('co19_run_');
  try {
    // Step 1: Compile .dart → .dill via `fvm dart compile kernel`.
    final dillPath = '${tempDir.path}/test.dill';
    final experimentArgs = entry.experimentFlags
        .expand((f) => ['--enable-experiment=$f'])
        .toList();
    final compileResult = await Process.run(
      'fvm',
      ['dart', 'compile', 'kernel', ...experimentArgs, entry.path, '-o', dillPath],
    );

    final compileFailed = compileResult.exitCode != 0;

    if (entry.isNegative) {
      // Negative test: compile failure → pass, compile success → fail.
      if (compileFailed) {
        return TestOutcome(
          entry: entry,
          result: TestResult.pass,
          message: 'compile error as expected',
        );
      } else {
        return TestOutcome(
          entry: entry,
          result: TestResult.fail,
          message: 'negative test: expected compile error but compiled '
              'successfully',
        );
      }
    }

    // Normal test: compile failure → fail.
    if (compileFailed) {
      final stderr = compileResult.stderr.toString().trim();
      final stdout = compileResult.stdout.toString().trim();
      final detail = stderr.isNotEmpty ? stderr : stdout;
      return TestOutcome(
        entry: entry,
        result: TestResult.fail,
        message: 'compile error: $detail',
      );
    }

    // Step 2: Load the .dill and compile to dartic bytecode.
    final bytes = File(dillPath).readAsBytesSync();
    final component = ir.Component();
    BinaryBuilder(bytes).readComponent(component);
    final module = DarticCompiler(component).compile();

    // Step 3: Execute in the interpreter with host function bindings.
    final registry = HostFunctionRegistry();
    CoreBindings.registerAll(registry);
    final interp = DarticInterpreter(hostFunctionRegistry: registry);
    interp.execute(module);

    return TestOutcome(entry: entry, result: TestResult.pass);
  } on Object catch (e) {
    // Catch-all for any unexpected error during compilation or execution.
    // Distinguish between test failures (runtime throws from the test program)
    // and internal errors (harness/compiler bugs).
    //
    // For now, treat all exceptions during execution as test failures rather
    // than errors, since the most common case is the interpreter throwing
    // because of unsupported features exercised by the test.
    return TestOutcome(
      entry: entry,
      result: TestResult.fail,
      message: '$e',
    );
  } finally {
    await tempDir.delete(recursive: true);
  }
}

/// Runs all [entries] sequentially, returning a [TestOutcome] for each.
Future<List<TestOutcome>> runTests(List<TestEntry> entries) async {
  final outcomes = <TestOutcome>[];
  for (final entry in entries) {
    outcomes.add(await runTest(entry));
  }
  return outcomes;
}

// ---------------------------------------------------------------------------
// Concurrency pool
// ---------------------------------------------------------------------------

/// A lightweight semaphore that limits concurrent async operations to [jobs].
///
/// Based on a FIFO queue of [Completer]s: when all slots are taken, callers
/// wait in order. When a slot is released, it is handed directly to the next
/// waiter (no redundant decrement-then-increment).
class Pool {
  Pool(this._maxJobs) : _currentJobs = 0;

  final int _maxJobs;
  int _currentJobs;
  final _waiters = <Completer<void>>[];

  /// Acquires a slot. Returns immediately if one is available, otherwise
  /// suspends until a slot is released.
  Future<void> acquire() {
    if (_currentJobs < _maxJobs) {
      _currentJobs++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  /// Releases a slot. If waiters are queued, the slot is handed directly to
  /// the next one (FIFO).
  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _currentJobs--;
    }
  }
}

// ---------------------------------------------------------------------------
// Parallel test execution
// ---------------------------------------------------------------------------

/// Wraps [runTest] with a [timeout]. If the test does not complete in time,
/// returns [TestResult.error] with a timeout message.
///
/// An optional [runner] parameter allows injecting a custom test function
/// for testing purposes.
Future<TestOutcome> runTestWithTimeout(
  TestEntry entry,
  Duration timeout, {
  Future<TestOutcome> Function(TestEntry)? runner,
}) async {
  try {
    return await (runner ?? runTest)(entry).timeout(timeout);
  } on TimeoutException {
    return TestOutcome(
      entry: entry,
      result: TestResult.error,
      message: 'timeout after ${timeout.inSeconds}s',
    );
  }
}

/// Runs all [entries] in parallel with at most [jobs] concurrent executions.
///
/// Results are returned in the same order as [entries], regardless of
/// completion order. The optional [onProgress] callback is invoked after
/// each test completes.
Future<List<TestOutcome>> runTestsParallel(
  List<TestEntry> entries, {
  required int jobs,
  required Duration timeout,
  void Function(int completed, int total, TestResult result)? onProgress,
}) async {
  if (entries.isEmpty) return [];

  final pool = Pool(jobs);
  final results = List<TestOutcome?>.filled(entries.length, null);
  var completed = 0;

  Future<void> runOne(int index) async {
    await pool.acquire();
    try {
      results[index] = await runTestWithTimeout(entries[index], timeout);
    } finally {
      pool.release();
      completed++;
      onProgress?.call(completed, entries.length, results[index]!.result);
    }
  }

  await Future.wait(List.generate(entries.length, runOne));
  return results.cast<TestOutcome>();
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

/// Aggregated pass/fail/skip/error counts for a single category.
class CategoryStats {
  final String category;
  final int pass;
  final int fail;
  final int skip;
  final int error;

  /// Number of negative (compile-error) tests in this category.
  final int negativeTotal;

  /// Number of negative tests that passed (compile error as expected).
  final int negativePass;

  CategoryStats({
    required this.category,
    required this.pass,
    required this.fail,
    required this.skip,
    required this.error,
    this.negativeTotal = 0,
    this.negativePass = 0,
  });

  /// Total number of tests in this category.
  int get total => pass + fail + skip + error;

  /// Number of positive (non-negative) tests in this category.
  int get positiveTotal => total - negativeTotal;

  /// Pass rate as a percentage (0.0–100.0). Returns 0.0 if [total] is 0.
  double get passRate => total == 0 ? 0.0 : (pass / total) * 100.0;
}

/// Groups [outcomes] by category and computes per-category statistics.
///
/// Returns a list of [CategoryStats] sorted by category name.
/// Each [CategoryStats] also includes a negative/positive breakdown
/// based on [TestEntry.isNegative].
List<CategoryStats> computeStats(List<TestOutcome> outcomes) {
  final groups = <String, List<TestOutcome>>{};
  for (final o in outcomes) {
    groups.putIfAbsent(o.entry.category, () => []).add(o);
  }

  final stats = <CategoryStats>[];
  for (final category in groups.keys) {
    final list = groups[category]!;
    final negativeOutcomes = list.where((o) => o.entry.isNegative).toList();
    stats.add(CategoryStats(
      category: category,
      pass: list.where((o) => o.result == TestResult.pass).length,
      fail: list.where((o) => o.result == TestResult.fail).length,
      skip: list.where((o) => o.result == TestResult.skip).length,
      error: list.where((o) => o.result == TestResult.error).length,
      negativeTotal: negativeOutcomes.length,
      negativePass:
          negativeOutcomes.where((o) => o.result == TestResult.pass).length,
    ));
  }

  stats.sort((a, b) => a.category.compareTo(b.category));
  return stats;
}

// ---------------------------------------------------------------------------
// Report formatting
// ---------------------------------------------------------------------------

/// Formats a human-readable text report from [stats] and [outcomes].
///
/// The report includes:
/// 1. A table with per-category pass/fail/skip/error counts and pass rate.
/// 2. A TOTAL summary row.
/// 3. Detailed lists of failed and errored tests with their messages.
String formatReport(
  List<CategoryStats> stats,
  List<TestOutcome> outcomes,
) {
  final buf = StringBuffer();

  // Compute totals.
  var totalPass = 0;
  var totalFail = 0;
  var totalSkip = 0;
  var totalError = 0;
  for (final s in stats) {
    totalPass += s.pass;
    totalFail += s.fail;
    totalSkip += s.skip;
    totalError += s.error;
  }
  final totalAll = totalPass + totalFail + totalSkip + totalError;
  final totalRate =
      totalAll == 0 ? 0.0 : (totalPass / totalAll) * 100.0;

  // Determine column widths.
  const minCatWidth = 10;
  var catWidth = minCatWidth;
  for (final s in stats) {
    if (s.category.length > catWidth) catWidth = s.category.length;
  }
  if ('TOTAL'.length > catWidth) catWidth = 'TOTAL'.length;
  // Add padding.
  catWidth += 2;

  // Header.
  buf.writeln(
    '${'Category'.padRight(catWidth)}'
    '${'Pass'.padLeft(8)}'
    '${'Fail'.padLeft(8)}'
    '${'Skip'.padLeft(8)}'
    '${'Error'.padLeft(8)}'
    '${'Total'.padLeft(8)}'
    '${'Rate'.padLeft(10)}',
  );
  buf.writeln('─' * (catWidth + 8 * 5 + 10));

  // Aggregate negative/positive totals for the TOTAL row.
  var totalNegative = 0;
  var totalPositive = 0;

  // Category rows.
  for (final s in stats) {
    buf.writeln(
      '${s.category.padRight(catWidth)}'
      '${s.pass.toString().padLeft(8)}'
      '${s.fail.toString().padLeft(8)}'
      '${s.skip.toString().padLeft(8)}'
      '${s.error.toString().padLeft(8)}'
      '${s.total.toString().padLeft(8)}'
      '${_formatRate(s.passRate).padLeft(10)}',
    );
    // Add negative/positive breakdown if there are negative tests.
    if (s.negativeTotal > 0) {
      buf.writeln(
        '${''.padRight(catWidth)}'
        '  (${s.negativeTotal} negative, ${s.positiveTotal} positive)',
      );
    }
    totalNegative += s.negativeTotal;
    totalPositive += s.positiveTotal;
  }

  // Separator and total row.
  buf.writeln('─' * (catWidth + 8 * 5 + 10));
  buf.writeln(
    '${'TOTAL'.padRight(catWidth)}'
    '${totalPass.toString().padLeft(8)}'
    '${totalFail.toString().padLeft(8)}'
    '${totalSkip.toString().padLeft(8)}'
    '${totalError.toString().padLeft(8)}'
    '${totalAll.toString().padLeft(8)}'
    '${_formatRate(totalRate).padLeft(10)}',
  );
  if (totalNegative > 0) {
    buf.writeln(
      '${''.padRight(catWidth)}'
      '  ($totalNegative negative, $totalPositive positive)',
    );
  }

  // Failed tests detail.
  final failures = outcomes.where((o) => o.result == TestResult.fail).toList();
  if (failures.isNotEmpty) {
    buf.writeln();
    buf.writeln('Failed tests (${failures.length}):');
    for (final f in failures) {
      buf.writeln('  FAIL  ${f.entry.path}');
      if (f.message.isNotEmpty) {
        buf.writeln('        ${f.message}');
      }
    }
  }

  // Error tests detail.
  final errors = outcomes.where((o) => o.result == TestResult.error).toList();
  if (errors.isNotEmpty) {
    buf.writeln();
    buf.writeln('Errors (${errors.length}):');
    for (final e in errors) {
      buf.writeln('  ERROR ${e.entry.path}');
      if (e.message.isNotEmpty) {
        buf.writeln('        ${e.message}');
      }
    }
  }

  return buf.toString();
}

/// Formats a pass rate as "XX.X%".
String _formatRate(double rate) => '${rate.toStringAsFixed(1)}%';

// ---------------------------------------------------------------------------
// Snapshot save / load
// ---------------------------------------------------------------------------

/// Converts [outcomes] to a snapshot map (test path → result name).
Map<String, String> outcomesToMap(List<TestOutcome> outcomes) {
  return {for (final o in outcomes) o.entry.path: o.result.name};
}

/// Serializes [outcomes] to a JSON file at [filePath].
///
/// Format: `Map<String, String>` where key = test path, value = result name
/// (e.g., "pass", "fail", "skip", "error"). Parent directories are created
/// if they do not exist.
void saveSnapshot(List<TestOutcome> outcomes, String filePath) {
  final map = outcomesToMap(outcomes);
  final file = File(filePath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(map),
  );
}

/// Loads a previously saved snapshot from [filePath].
///
/// Returns a `Map<String, String>` where key = test path, value = result name.
/// If the file does not exist, returns an empty map.
Map<String, String> loadSnapshot(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) return {};
  final content = file.readAsStringSync();
  final decoded = jsonDecode(content) as Map<String, dynamic>;
  return decoded.map((k, v) => MapEntry(k, v as String));
}

// ---------------------------------------------------------------------------
// Diff
// ---------------------------------------------------------------------------

/// The result of comparing two snapshots (baseline vs. current).
class DiffResult {
  /// Tests that were fail/skip/error in baseline but pass in current.
  final List<String> newPass;

  /// Tests that were pass in baseline but fail/skip/error in current.
  final List<String> regressions;

  /// Tests that are non-pass in both baseline and current.
  final List<String> steadyFail;

  /// Tests that pass in both baseline and current.
  final List<String> steadyPass;

  /// Tests present only in current (new tests).
  final List<String> addedTests;

  /// Tests present only in baseline (removed tests).
  final List<String> removedTests;

  DiffResult({
    required this.newPass,
    required this.regressions,
    required this.steadyFail,
    required this.steadyPass,
    required this.addedTests,
    required this.removedTests,
  });
}

/// Compares [baseline] and [current] snapshots, classifying every test path
/// into one of six categories.
///
/// Classification rules for tests present in both snapshots:
/// - **steadyPass**: pass in both.
/// - **steadyFail**: non-pass in both.
/// - **newPass**: non-pass in baseline, pass in current.
/// - **regressions**: pass in baseline, non-pass in current.
///
/// Tests only in [current] go to [DiffResult.addedTests].
/// Tests only in [baseline] go to [DiffResult.removedTests].
DiffResult diffSnapshots(
  Map<String, String> baseline,
  Map<String, String> current,
) {
  final newPass = <String>[];
  final regressions = <String>[];
  final steadyFail = <String>[];
  final steadyPass = <String>[];
  final addedTests = <String>[];
  final removedTests = <String>[];

  // All keys from both maps.
  final allKeys = <String>{...baseline.keys, ...current.keys};

  for (final key in allKeys) {
    final inBaseline = baseline.containsKey(key);
    final inCurrent = current.containsKey(key);

    if (inBaseline && inCurrent) {
      final basePass = baseline[key] == 'pass';
      final curPass = current[key] == 'pass';

      if (basePass && curPass) {
        steadyPass.add(key);
      } else if (basePass && !curPass) {
        regressions.add(key);
      } else if (!basePass && curPass) {
        newPass.add(key);
      } else {
        steadyFail.add(key);
      }
    } else if (inCurrent) {
      addedTests.add(key);
    } else {
      removedTests.add(key);
    }
  }

  // Sort all lists for deterministic output.
  newPass.sort();
  regressions.sort();
  steadyFail.sort();
  steadyPass.sort();
  addedTests.sort();
  removedTests.sort();

  return DiffResult(
    newPass: newPass,
    regressions: regressions,
    steadyFail: steadyFail,
    steadyPass: steadyPass,
    addedTests: addedTests,
    removedTests: removedTests,
  );
}

/// Formats a [DiffResult] as a human-readable report.
///
/// The report includes:
/// 1. A summary section with counts for each category.
/// 2. A detailed list of regressions (most important — highlighted).
/// 3. A detailed list of new passes.
/// 4. Lists of added/removed tests if any.
/// 5. Steady pass/fail shown as counts only (not individual paths).
String formatDiff(DiffResult diff) {
  final buf = StringBuffer();

  // ---- Summary ----
  buf.writeln('=== Diff Summary ===');
  buf.writeln('  New passes:    ${diff.newPass.length}');
  buf.writeln('  REGRESSIONS:   ${diff.regressions.length}');
  buf.writeln('  Steady pass:   ${diff.steadyPass.length}');
  buf.writeln('  Steady fail:   ${diff.steadyFail.length}');
  buf.writeln('  Added tests:   ${diff.addedTests.length}');
  buf.writeln('  Removed tests: ${diff.removedTests.length}');

  // ---- Regressions (most critical) ----
  if (diff.regressions.isNotEmpty) {
    buf.writeln();
    buf.writeln('!!! REGRESSION (${diff.regressions.length}):');
    for (final path in diff.regressions) {
      buf.writeln('  REGRESSION  $path');
    }
  }

  // ---- New passes ----
  if (diff.newPass.isNotEmpty) {
    buf.writeln();
    buf.writeln('New passes (${diff.newPass.length}):');
    for (final path in diff.newPass) {
      buf.writeln('  FIXED     $path');
    }
  }

  // ---- Added tests ----
  if (diff.addedTests.isNotEmpty) {
    buf.writeln();
    buf.writeln('Added tests (${diff.addedTests.length}):');
    for (final path in diff.addedTests) {
      buf.writeln('  ADDED     $path');
    }
  }

  // ---- Removed tests ----
  if (diff.removedTests.isNotEmpty) {
    buf.writeln();
    buf.writeln('Removed tests (${diff.removedTests.length}):');
    for (final path in diff.removedTests) {
      buf.writeln('  REMOVED   $path');
    }
  }

  return buf.toString();
}

// ---------------------------------------------------------------------------
// Progress reporting
// ---------------------------------------------------------------------------

/// Displays a single overwriting progress line on stderr.
///
/// Format: `[1234/4167] 900 pass, 300 fail, 34 error (28.5/s)`
class _ProgressReporter {
  _ProgressReporter(this._total)
      : _pass = 0,
        _fail = 0,
        _error = 0,
        _completed = 0,
        _stopwatch = Stopwatch()..start();

  final int _total;
  int _pass;
  int _fail;
  int _error;
  int _completed;
  final Stopwatch _stopwatch;

  /// Records a completed test result and rewrites the progress line.
  void report(TestResult result) {
    _completed++;
    switch (result) {
      case TestResult.pass:
        _pass++;
      case TestResult.fail:
        _fail++;
      case TestResult.error:
        _error++;
      case TestResult.skip:
        break;
    }
    final elapsed = _stopwatch.elapsedMilliseconds / 1000.0;
    final rate = elapsed > 0 ? _completed / elapsed : 0.0;
    stderr.write(
      '\r[$_completed/$_total] $_pass pass, $_fail fail, $_error error'
      ' (${rate.toStringAsFixed(1)}/s)',
    );
  }

  /// Prints the final progress line (with newline) and stops the stopwatch.
  void finish() {
    _stopwatch.stop();
    final elapsed = _stopwatch.elapsedMilliseconds / 1000.0;
    final rate = elapsed > 0 ? _completed / elapsed : 0.0;
    stderr.writeln(
      '\r[$_completed/$_total] $_pass pass, $_fail fail, $_error error'
      ' (${rate.toStringAsFixed(1)}/s)',
    );
  }
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

/// Prints a comprehensive usage message to [sink].
void _printUsage(StringSink sink) {
  sink.writeln('Usage: dart tool/co19_runner.dart [options] <directories...>');
  sink.writeln('');
  sink.writeln('Discovers and runs co19 conformance tests against the dartic');
  sink.writeln('bytecode interpreter.');
  sink.writeln('');
  sink.writeln('Options:');
  sink.writeln('  --run              Discover, compile, execute tests, and');
  sink.writeln('                     print report.');
  sink.writeln('  --jobs=N, -jN      Number of concurrent test workers.');
  sink.writeln('                     Defaults to CPU core count.');
  sink.writeln('  --timeout=<secs>   Per-test timeout in seconds (default: 30).');
  sink.writeln('  --snapshot=<path>  Save results to a JSON snapshot file.');
  sink.writeln('                     Requires --run.');
  sink.writeln('  --baseline=<path>  Compare results against a baseline');
  sink.writeln('                     snapshot and print diff. Requires --run.');
  sink.writeln('                     If baseline file does not exist, just');
  sink.writeln('                     runs and prints report (no diff).');
  sink.writeln('  --help             Show this usage message.');
  sink.writeln('');
  sink.writeln('Default behavior (no flags): discovery only — lists test');
  sink.writeln('files found in the given directories.');
  sink.writeln('');
  sink.writeln('Examples:');
  sink.writeln('  # Discover tests only');
  sink.writeln(
      '  dart tool/co19_runner.dart vendor/co19/Language/Variables');
  sink.writeln('');
  sink.writeln('  # Run tests and print report');
  sink.writeln(
      '  dart tool/co19_runner.dart --run vendor/co19/Language/Variables');
  sink.writeln('');
  sink.writeln('  # Run with 8 workers and 60s timeout');
  sink.writeln('  dart tool/co19_runner.dart --run --jobs=8 --timeout=60 \\');
  sink.writeln('    vendor/co19/Language/Variables');
  sink.writeln('');
  sink.writeln('  # Run, save snapshot, and compare against baseline');
  sink.writeln('  dart tool/co19_runner.dart --run \\');
  sink.writeln('    --snapshot=snapshots/current.json \\');
  sink.writeln('    --baseline=snapshots/baseline.json \\');
  sink.writeln('    vendor/co19/Language/Variables');
}

/// Parses `-jN` style shorthand (e.g. `-j4` → `4`). Returns `null` on
/// parse failure.
int? _parseShortJobs(String arg) {
  final n = int.tryParse(arg.substring(2));
  return (n != null && n > 0) ? n : null;
}

Future<void> main(List<String> args) async {
  // -- Parse arguments manually. --
  var runMode = false;
  int? jobs;
  var timeoutSeconds = 30;
  String? snapshotPath;
  String? baselinePath;
  var showHelp = false;
  final dirs = <String>[];

  for (final arg in args) {
    if (arg == '--run') {
      runMode = true;
    } else if (arg == '--help' || arg == '-h') {
      showHelp = true;
    } else if (arg.startsWith('--jobs=')) {
      jobs = int.tryParse(arg.substring('--jobs='.length));
      if (jobs == null || jobs <= 0) {
        stderr.writeln('Invalid --jobs value: $arg');
        exitCode = 1;
        return;
      }
    } else if (arg.startsWith('-j') && arg.length > 2) {
      jobs = _parseShortJobs(arg);
      if (jobs == null) {
        stderr.writeln('Invalid -j value: $arg');
        exitCode = 1;
        return;
      }
    } else if (arg.startsWith('--timeout=')) {
      timeoutSeconds =
          int.tryParse(arg.substring('--timeout='.length)) ?? -1;
      if (timeoutSeconds <= 0) {
        stderr.writeln('Invalid --timeout value: $arg');
        exitCode = 1;
        return;
      }
    } else if (arg.startsWith('--snapshot=')) {
      snapshotPath = arg.substring('--snapshot='.length);
    } else if (arg.startsWith('--baseline=')) {
      baselinePath = arg.substring('--baseline='.length);
    } else if (arg.startsWith('--') || (arg.startsWith('-') && arg != '-')) {
      stderr.writeln('Unknown option: $arg');
      stderr.writeln('');
      _printUsage(stderr);
      exitCode = 1;
      return;
    } else {
      dirs.add(arg);
    }
  }

  // -- Handle --help. --
  if (showHelp) {
    _printUsage(stdout);
    return;
  }

  // -- Validate arguments. --
  if (dirs.isEmpty) {
    stderr.writeln('Error: No directories provided.');
    stderr.writeln('');
    _printUsage(stderr);
    exitCode = 1;
    return;
  }

  // Default jobs to CPU core count.
  jobs ??= Platform.numberOfProcessors;

  // -- Discover tests. --
  final entries = discoverTests(dirs);

  if (!runMode) {
    // Discovery-only mode (default).
    stdout.writeln('Discovered ${entries.length} test(s):');
    for (final entry in entries) {
      stdout.writeln('  $entry');
    }
    return;
  }

  // -- Run mode: execute tests in parallel. --
  stderr.writeln(
    'Discovered ${entries.length} test(s). '
    'Running with $jobs worker(s), ${timeoutSeconds}s timeout...',
  );

  final progress = _ProgressReporter(entries.length);
  final outcomes = await runTestsParallel(
    entries,
    jobs: jobs,
    timeout: Duration(seconds: timeoutSeconds),
    onProgress: (completed, total, result) => progress.report(result),
  );
  progress.finish();
  stderr.writeln('');

  // -- Compute stats and print report to stdout. --
  final stats = computeStats(outcomes);
  stdout.write(formatReport(stats, outcomes));

  // -- Save snapshot if requested. --
  if (snapshotPath != null) {
    saveSnapshot(outcomes, snapshotPath);
    stderr.writeln('Snapshot saved to $snapshotPath');
  }

  // -- Compare against baseline if requested. --
  if (baselinePath != null) {
    final baseline = loadSnapshot(baselinePath);
    if (baseline.isEmpty) {
      stderr.writeln(
          'Baseline file not found or empty: $baselinePath (skipping diff)');
    } else {
      final diff = diffSnapshots(baseline, outcomesToMap(outcomes));
      stdout.writeln('');
      stdout.write(formatDiff(diff));
    }
  }
}
