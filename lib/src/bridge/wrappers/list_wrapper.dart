/// Registers `List` host bindings for the CALL_HOST pipeline.
///
/// Covers List instance methods, getters, operators, and static constructors.
/// Callback-based methods (sort, map, where, forEach, etc.) are registered
/// but full integration testing is deferred to 5.3.3 when DarticCallbackProxy
/// is ready.
///
/// See: docs/design/04-interop.md
library;

import '../host_bindings.dart';

/// Registers all `dart:core::List` host function bindings.
abstract final class ListBindings {
  static void register(HostBindings bindings) {
    // ── Getters ──
    bindings.register('dart:core::List::length#0', (args) {
      return (args[0] as List).length;
    });
    bindings.register('dart:core::List::isEmpty#0', (args) {
      return (args[0] as List).isEmpty;
    });
    bindings.register('dart:core::List::isNotEmpty#0', (args) {
      return (args[0] as List).isNotEmpty;
    });
    bindings.register('dart:core::List::first#0', (args) {
      return (args[0] as List).first;
    });
    bindings.register('dart:core::List::last#0', (args) {
      return (args[0] as List).last;
    });
    bindings.register('dart:core::List::reversed#0', (args) {
      return (args[0] as List).reversed;
    });
    bindings.register('dart:core::List::hashCode#0', (args) {
      return (args[0] as List).hashCode;
    });

    // length= setter: "dart:core::List::length=#1", argCount=2
    bindings.register('dart:core::List::length=#1', (args) {
      (args[0] as List).length = args[1] as int;
      return args[1];
    });

    // ── Operators ──
    bindings.register('dart:core::List::[]#1', (args) {
      return (args[0] as List)[args[1] as int];
    });
    bindings.register('dart:core::List::[]=#2', (args) {
      (args[0] as List)[args[1] as int] = args[2];
      return args[2];
    });

    // ── Methods ──
    bindings.register('dart:core::List::add#1', (args) {
      (args[0] as List).add(args[1]);
      return null;
    });
    bindings.register('dart:core::List::addAll#1', (args) {
      (args[0] as List).addAll(args[1] as Iterable);
      return null;
    });
    bindings.register('dart:core::List::insert#2', (args) {
      (args[0] as List).insert(args[1] as int, args[2]);
      return null;
    });
    bindings.register('dart:core::List::insertAll#2', (args) {
      (args[0] as List).insertAll(args[1] as int, args[2] as Iterable);
      return null;
    });
    bindings.register('dart:core::List::remove#1', (args) {
      return (args[0] as List).remove(args[1]);
    });
    bindings.register('dart:core::List::removeAt#1', (args) {
      return (args[0] as List).removeAt(args[1] as int);
    });
    bindings.register('dart:core::List::removeLast#0', (args) {
      return (args[0] as List).removeLast();
    });
    bindings.register('dart:core::List::clear#0', (args) {
      (args[0] as List).clear();
      return null;
    });
    bindings.register('dart:core::List::contains#1', (args) {
      return (args[0] as List).contains(args[1]);
    });
    bindings.register('dart:core::List::indexOf#2', (args) {
      final list = args[0] as List;
      if (args.length > 2 && args[2] != null) {
        return list.indexOf(args[1], args[2] as int);
      }
      return list.indexOf(args[1]);
    });
    bindings.register('dart:core::List::lastIndexOf#2', (args) {
      final list = args[0] as List;
      if (args.length > 2 && args[2] != null) {
        return list.lastIndexOf(args[1], args[2] as int);
      }
      return list.lastIndexOf(args[1]);
    });
    bindings.register('dart:core::List::sublist#2', (args) {
      final list = args[0] as List;
      if (args.length > 2 && args[2] != null) {
        return list.sublist(args[1] as int, args[2] as int);
      }
      return list.sublist(args[1] as int);
    });
    bindings.register('dart:core::List::join#1', (args) {
      return (args[0] as List).join(args.length > 1 ? args[1] as String : '');
    });
    bindings.register('dart:core::List::toString#0', (args) {
      return (args[0] as List).toString();
    });
    bindings.register('dart:core::List::asMap#0', (args) {
      return (args[0] as List).asMap();
    });
    bindings.register('dart:core::List::toSet#0', (args) {
      return (args[0] as List).toSet();
    });
    bindings.register('dart:core::List::toList#1', (args) {
      // toList({bool growable = true}) -- 1 named param
      if (args.length > 1 && args[1] != null) {
        return (args[0] as List).toList(growable: args[1] as bool);
      }
      return (args[0] as List).toList();
    });

    // ── Static constructors ──

    // List.filled(int length, E fill, {bool growable = false}) -- 3 formal params
    bindings.register('dart:core::List::filled#3', (args) {
      final length = args[0] as int;
      final fill = args[1];
      if (args.length > 2 && args[2] != null) {
        return List.filled(length, fill, growable: args[2] as bool);
      }
      return List.filled(length, fill);
    });

    // List.empty({bool growable = false}) -- 1 formal param (named)
    bindings.register('dart:core::List::empty#1', (args) {
      if (args.isNotEmpty && args[0] != null) {
        return List.empty(growable: args[0] as bool);
      }
      return List.empty();
    });

    // List.generate(int length, E Function(int) generator, {bool growable = true})
    bindings.register('dart:core::List::generate#3', (args) {
      final length = args[0] as int;
      final generator = args[1] as Function;
      if (args.length > 2 && args[2] != null) {
        return List.generate(
          length,
          (i) => generator(i),
          growable: args[2] as bool,
        );
      }
      return List.generate(length, (i) => generator(i));
    });

    // List.of(Iterable elements, {bool growable = true}) -- 2 formal params
    bindings.register('dart:core::List::of#2', (args) {
      final iterable = args[0] as Iterable;
      if (args.length > 1 && args[1] != null) {
        return List.of(iterable, growable: args[1] as bool);
      }
      return List.of(iterable);
    });

    // List.from(Iterable elements, {bool growable = true}) -- 2 formal params
    bindings.register('dart:core::List::from#2', (args) {
      final iterable = args[0] as Iterable;
      if (args.length > 1 && args[1] != null) {
        return List.from(iterable, growable: args[1] as bool);
      }
      return List.from(iterable);
    });

    // List.unmodifiable(Iterable elements) -- 1 formal param
    bindings.register('dart:core::List::unmodifiable#1', (args) {
      return List.unmodifiable(args[0] as Iterable);
    });

    // ── Callback methods ──

    bindings.register('dart:core::List::forEach#1', (args) {
      final fn = args[1] as Function;
      for (final e in args[0] as List) {
        fn(e);
      }
      return null;
    });
    bindings.register('dart:core::List::map#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as List).map((e) => fn(e));
    });
    bindings.register('dart:core::List::where#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as List).where((e) => fn(e) as bool);
    });
    bindings.register('dart:core::List::fold#2', (args) {
      final fn = args[2] as Function;
      return (args[0] as List)
          .fold(args[1], (prev, e) => fn(prev, e));
    });
    bindings.register('dart:core::List::any#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as List).any((e) => fn(e) as bool);
    });
    bindings.register('dart:core::List::every#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as List).every((e) => fn(e) as bool);
    });

    bindings.register('dart:core::List::sort#1', (args) {
      if (args.length > 1 && args[1] != null) {
        final fn = args[1] as Function;
        (args[0] as List).sort((a, b) => fn(a, b) as int);
      } else {
        (args[0] as List).sort();
      }
      return null;
    });
    bindings.register('dart:core::List::shuffle#1', (args) {
      (args[0] as List).shuffle();
      return null;
    });
    bindings.register('dart:core::List::fillRange#3', (args) {
      (args[0] as List).fillRange(
        args[1] as int,
        args[2] as int,
        args.length > 3 ? args[3] : null,
      );
      return null;
    });
    bindings.register('dart:core::List::setRange#4', (args) {
      (args[0] as List).setRange(
        args[1] as int,
        args[2] as int,
        args[3] as Iterable,
        args.length > 4 ? args[4] as int : 0,
      );
      return null;
    });
    bindings.register('dart:core::List::getRange#2', (args) {
      return (args[0] as List).getRange(args[1] as int, args[2] as int);
    });
    bindings.register('dart:core::List::replaceRange#3', (args) {
      (args[0] as List).replaceRange(
        args[1] as int,
        args[2] as int,
        args[3] as Iterable,
      );
      return null;
    });
    bindings.register('dart:core::List::iterator#0', (args) {
      return (args[0] as List).iterator;
    });

    // ── Internal _GrowableList factories ──
    // Dart SDK lowers list literals [a, b, c] to _GrowableList._literalN(...)
    // and [] to _GrowableList(0). We must register these internal names.

    // _GrowableList(int length) -- empty list constructor
    bindings.register('dart:core::_GrowableList::#1', (args) {
      return List<dynamic>.filled(args[0] as int, null, growable: true);
    });

    // _GrowableList._literal1 through _literal8
    bindings.register('dart:core::_GrowableList::_literal1#1', (args) {
      return <dynamic>[args[0]];
    });
    bindings.register('dart:core::_GrowableList::_literal2#2', (args) {
      return <dynamic>[args[0], args[1]];
    });
    bindings.register('dart:core::_GrowableList::_literal3#3', (args) {
      return <dynamic>[args[0], args[1], args[2]];
    });
    bindings.register('dart:core::_GrowableList::_literal4#4', (args) {
      return <dynamic>[args[0], args[1], args[2], args[3]];
    });
    bindings.register('dart:core::_GrowableList::_literal5#5', (args) {
      return <dynamic>[args[0], args[1], args[2], args[3], args[4]];
    });
    bindings.register('dart:core::_GrowableList::_literal6#6', (args) {
      return <dynamic>[args[0], args[1], args[2], args[3], args[4], args[5]];
    });
    bindings.register('dart:core::_GrowableList::_literal7#7', (args) {
      return <dynamic>[
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
        args[6],
      ];
    });
    bindings.register('dart:core::_GrowableList::_literal8#8', (args) {
      return <dynamic>[
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
        args[6],
        args[7],
      ];
    });

    // _GrowableList._literal(_List elements) -- for larger literals (> 8)
    bindings.register('dart:core::_GrowableList::_literal#1', (args) {
      return List<dynamic>.from(args[0] as List);
    });

    // _GrowableList.filled(int length, E fill)
    bindings.register('dart:core::_GrowableList::filled#2', (args) {
      return List<dynamic>.filled(args[0] as int, args[1], growable: true);
    });

    // ── Internal _List factories ──
    // List.filled(length, fill) with growable: false lowers to _List.filled

    // _List.filled(int length, E fill)
    bindings.register('dart:core::_List::filled#2', (args) {
      final length = args[0] as int;
      final fill = args[1];
      return List<dynamic>.filled(length, fill, growable: false);
    });

    // _List(int length) -- fixed-size list constructor
    bindings.register('dart:core::_List::#1', (args) {
      return List<dynamic>.filled(args[0] as int, null, growable: false);
    });

    // ── _GrowableList instance methods (mirrors of List methods) ──
    // Kernel may resolve instance methods to _GrowableList rather than List.

    _registerGrowableListInstanceMethods(bindings);
  }

  /// Registers instance method bindings on `_GrowableList` class names.
  ///
  /// These mirror the `List` bindings but use the internal class name,
  /// because Kernel may resolve instance calls on list literals to
  /// `_GrowableList` rather than `List`.
  static void _registerGrowableListInstanceMethods(HostBindings bindings) {
    // Getters
    bindings.register('dart:core::_GrowableList::length#0', (args) {
      return (args[0] as List).length;
    });
    bindings.register('dart:core::_GrowableList::isEmpty#0', (args) {
      return (args[0] as List).isEmpty;
    });
    bindings.register('dart:core::_GrowableList::isNotEmpty#0', (args) {
      return (args[0] as List).isNotEmpty;
    });
    bindings.register('dart:core::_GrowableList::first#0', (args) {
      return (args[0] as List).first;
    });
    bindings.register('dart:core::_GrowableList::last#0', (args) {
      return (args[0] as List).last;
    });
    bindings.register('dart:core::_GrowableList::reversed#0', (args) {
      return (args[0] as List).reversed;
    });
    bindings.register('dart:core::_GrowableList::hashCode#0', (args) {
      return (args[0] as List).hashCode;
    });
    bindings.register('dart:core::_GrowableList::length=#1', (args) {
      (args[0] as List).length = args[1] as int;
      return args[1];
    });

    // Operators
    bindings.register('dart:core::_GrowableList::[]#1', (args) {
      return (args[0] as List)[args[1] as int];
    });
    bindings.register('dart:core::_GrowableList::[]=#2', (args) {
      (args[0] as List)[args[1] as int] = args[2];
      return args[2];
    });

    // Methods
    bindings.register('dart:core::_GrowableList::add#1', (args) {
      (args[0] as List).add(args[1]);
      return null;
    });
    bindings.register('dart:core::_GrowableList::addAll#1', (args) {
      (args[0] as List).addAll(args[1] as Iterable);
      return null;
    });
    bindings.register('dart:core::_GrowableList::insert#2', (args) {
      (args[0] as List).insert(args[1] as int, args[2]);
      return null;
    });
    bindings.register('dart:core::_GrowableList::insertAll#2', (args) {
      (args[0] as List).insertAll(args[1] as int, args[2] as Iterable);
      return null;
    });
    bindings.register('dart:core::_GrowableList::remove#1', (args) {
      return (args[0] as List).remove(args[1]);
    });
    bindings.register('dart:core::_GrowableList::removeAt#1', (args) {
      return (args[0] as List).removeAt(args[1] as int);
    });
    bindings.register('dart:core::_GrowableList::removeLast#0', (args) {
      return (args[0] as List).removeLast();
    });
    bindings.register('dart:core::_GrowableList::clear#0', (args) {
      (args[0] as List).clear();
      return null;
    });
    bindings.register('dart:core::_GrowableList::contains#1', (args) {
      return (args[0] as List).contains(args[1]);
    });
    bindings.register('dart:core::_GrowableList::indexOf#2', (args) {
      final list = args[0] as List;
      if (args.length > 2 && args[2] != null) {
        return list.indexOf(args[1], args[2] as int);
      }
      return list.indexOf(args[1]);
    });
    bindings.register('dart:core::_GrowableList::lastIndexOf#2', (args) {
      final list = args[0] as List;
      if (args.length > 2 && args[2] != null) {
        return list.lastIndexOf(args[1], args[2] as int);
      }
      return list.lastIndexOf(args[1]);
    });
    bindings.register('dart:core::_GrowableList::sublist#2', (args) {
      final list = args[0] as List;
      if (args.length > 2 && args[2] != null) {
        return list.sublist(args[1] as int, args[2] as int);
      }
      return list.sublist(args[1] as int);
    });
    bindings.register('dart:core::_GrowableList::join#1', (args) {
      return (args[0] as List).join(
        args.length > 1 ? args[1] as String : '',
      );
    });
    bindings.register('dart:core::_GrowableList::toString#0', (args) {
      return (args[0] as List).toString();
    });
    bindings.register('dart:core::_GrowableList::asMap#0', (args) {
      return (args[0] as List).asMap();
    });
    bindings.register('dart:core::_GrowableList::toSet#0', (args) {
      return (args[0] as List).toSet();
    });
    bindings.register('dart:core::_GrowableList::toList#1', (args) {
      if (args.length > 1 && args[1] != null) {
        return (args[0] as List).toList(growable: args[1] as bool);
      }
      return (args[0] as List).toList();
    });
    bindings.register('dart:core::_GrowableList::iterator#0', (args) {
      return (args[0] as List).iterator;
    });
    bindings.register('dart:core::_GrowableList::getRange#2', (args) {
      return (args[0] as List).getRange(args[1] as int, args[2] as int);
    });
    bindings.register('dart:core::_GrowableList::fillRange#3', (args) {
      (args[0] as List).fillRange(
        args[1] as int,
        args[2] as int,
        args.length > 3 ? args[3] : null,
      );
      return null;
    });
    bindings.register('dart:core::_GrowableList::setRange#4', (args) {
      (args[0] as List).setRange(
        args[1] as int,
        args[2] as int,
        args[3] as Iterable,
        args.length > 4 ? args[4] as int : 0,
      );
      return null;
    });
    bindings.register('dart:core::_GrowableList::replaceRange#3', (args) {
      (args[0] as List).replaceRange(
        args[1] as int,
        args[2] as int,
        args[3] as Iterable,
      );
      return null;
    });
    bindings.register('dart:core::_GrowableList::sort#1', (args) {
      if (args.length > 1 && args[1] != null) {
        final fn = args[1] as Function;
        (args[0] as List).sort((a, b) => fn(a, b) as int);
      } else {
        (args[0] as List).sort();
      }
      return null;
    });
    bindings.register('dart:core::_GrowableList::shuffle#1', (args) {
      (args[0] as List).shuffle();
      return null;
    });

    // ── _GrowableList callback methods (mirrors of Iterable methods) ──
    bindings.register('dart:core::_GrowableList::forEach#1', (args) {
      final fn = args[1] as Function;
      for (final e in args[0] as List) {
        fn(e);
      }
      return null;
    });
    bindings.register('dart:core::_GrowableList::map#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as List).map((e) => fn(e));
    });
    bindings.register('dart:core::_GrowableList::where#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as List).where((e) => fn(e) as bool);
    });
    bindings.register('dart:core::_GrowableList::fold#2', (args) {
      final fn = args[2] as Function;
      return (args[0] as List)
          .fold(args[1], (prev, e) => fn(prev, e));
    });
    bindings.register('dart:core::_GrowableList::any#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as List).any((e) => fn(e) as bool);
    });
    bindings.register('dart:core::_GrowableList::every#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as List).every((e) => fn(e) as bool);
    });

    // _GrowableList.generate -- Kernel may resolve List.generate to _GrowableList.generate
    bindings.register('dart:core::_GrowableList::generate#3', (args) {
      final length = args[0] as int;
      final generator = args[1] as Function;
      if (args.length > 2 && args[2] != null) {
        return List.generate(
          length,
          (i) => generator(i),
          growable: args[2] as bool,
        );
      }
      return List.generate(length, (i) => generator(i));
    });
    bindings.register('dart:core::_GrowableList::generate#2', (args) {
      final length = args[0] as int;
      final generator = args[1] as Function;
      return List.generate(length, (i) => generator(i));
    });
  }
}
