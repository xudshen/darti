/// Subprocess runner: loads a .dill, compiles to dartic bytecode, executes.
///
/// Stdout carries the test's print output (for async marker detection).
/// Stderr carries error messages from the harness/interpreter.
/// Exit code: 0 = success, 1 = runtime error, 2 = usage error.
///
/// The Dart VM naturally keeps the event loop running until all pending
/// async operations (Futures, Timers, microtasks) complete — this provides
/// correct async test behavior without any Completer hacks.
library;

import 'dart:io';

import 'package:dartic/src/bridge/async_bindings.dart';
import 'package:dartic/src/bridge/collection_bindings.dart';
import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:dartic/src/bridge/math_bindings.dart';
import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/compiler/compiler.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:kernel/ast.dart' as ir;
import 'package:kernel/binary/ast_from_binary.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dartic_run.dart <path-to-dill>');
    exit(2);
  }

  final bytes = File(args[0]).readAsBytesSync();
  final component = ir.Component();
  BinaryBuilder(bytes).readComponent(component);

  final DarticModule module;
  try {
    module = DarticCompiler(component).compile();
  } on Object catch (e) {
    stderr.writeln('$e');
    exit(1);
  }

  final registry = HostFunctionRegistry();
  CoreBindings.registerAll(registry);
  AsyncBindings.registerAll(registry);
  MathBindingsHub.registerAll(registry);
  CollectionBindingsHub.registerAll(registry);
  final interp = DarticInterpreter(hostFunctionRegistry: registry);

  try {
    interp.execute(module);
  } on Object catch (e) {
    stderr.writeln('$e');
    exit(1);
  }

  final result = interp.entryResult;
  if (result is Future) {
    try {
      await result;
    } on Object catch (e) {
      stderr.writeln('$e');
      exit(1);
    }
  }

  // Dart VM will wait for pending async operations (Futures, Timers)
  // before exiting — this is the "natural" async test completion mechanism,
  // matching how the official co19 runner works (process-based execution).
}
