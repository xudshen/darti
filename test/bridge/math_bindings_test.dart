import 'dart:math';

import 'package:dartic/src/bridge/bindings/math_bindings.dart';
import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:dartic/src/bridge/math_bindings.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  late HostFunctionRegistry registry;

  setUp(() {
    registry = HostFunctionRegistry();
    CoreBindings.registerAll(registry);
    MathBindings.register(registry);
  });

  Object? invoke(String name, List<Object?> args) {
    final id = registry.lookupByName(name);
    if (id == -1) fail('Binding not found: $name');
    return registry.invoke(id, args);
  }

  group('MathBindings top-level functions', () {
    test('min/max', () {
      expect(invoke('dart:math::::min#2', [3, 5]), 3);
      expect(invoke('dart:math::::max#2', [3, 5]), 5);
    });

    test('sqrt/pow', () {
      expect(invoke('dart:math::::sqrt#1', [9]), 3.0);
      expect(invoke('dart:math::::pow#2', [2, 3]), 8);
    });

    test('trig functions', () {
      expect(invoke('dart:math::::sin#1', [0]), 0.0);
      expect(invoke('dart:math::::cos#1', [0]), 1.0);
      expect(invoke('dart:math::::tan#1', [0]), closeTo(0.0, 1e-10));
    });

    test('log/exp', () {
      expect(invoke('dart:math::::log#1', [1]), 0.0);
      expect(invoke('dart:math::::exp#1', [0]), 1.0);
    });

    test('atan2', () {
      expect(invoke('dart:math::::atan2#2', [0, 1]), 0.0);
    });
  });

  group('MathBindings Random', () {
    test('constructor and methods', () {
      final rng = invoke('dart:math::Random::#1', [42]) as Random;
      expect(rng, isA<Random>());

      final nextInt = invoke('dart:math::Random::nextInt#1', [rng, 100]) as int;
      expect(nextInt, inInclusiveRange(0, 99));

      final nextDouble =
          invoke('dart:math::Random::nextDouble#0', [rng]) as double;
      expect(nextDouble, inInclusiveRange(0.0, 1.0));

      final nextBool =
          invoke('dart:math::Random::nextBool#0', [rng]) as bool;
      expect(nextBool, isA<bool>());
    });
  });

  group('MathBindings Rectangle methods', () {
    test('containsPoint is registered', () {
      expect(registry.lookupByName('dart:math::Rectangle::containsPoint#1'),
          isNot(equals(-1)));
    });

    test('containsPoint returns true for point inside', () {
      final rect = Rectangle(0, 0, 10, 10);
      final p = Point(5, 5);
      expect(invoke('dart:math::Rectangle::containsPoint#1', [rect, p]), true);
    });

    test('containsPoint returns false for point outside', () {
      final rect = Rectangle(0, 0, 10, 10);
      final p = Point(15, 5);
      expect(
          invoke('dart:math::Rectangle::containsPoint#1', [rect, p]), false);
    });

    test('intersects is registered', () {
      expect(registry.lookupByName('dart:math::Rectangle::intersects#1'),
          isNot(equals(-1)));
    });

    test('intersects detects overlapping rectangles', () {
      final r1 = Rectangle(0, 0, 10, 10);
      final r2 = Rectangle(5, 5, 10, 10);
      expect(invoke('dart:math::Rectangle::intersects#1', [r1, r2]), true);
    });

    test('intersects detects non-overlapping rectangles', () {
      final r1 = Rectangle(0, 0, 5, 5);
      final r2 = Rectangle(10, 10, 5, 5);
      expect(invoke('dart:math::Rectangle::intersects#1', [r1, r2]), false);
    });

    test('intersection is registered', () {
      expect(registry.lookupByName('dart:math::Rectangle::intersection#1'),
          isNot(equals(-1)));
    });

    test('intersection returns overlap region', () {
      final r1 = Rectangle(0, 0, 10, 10);
      final r2 = Rectangle(5, 5, 10, 10);
      final result = invoke('dart:math::Rectangle::intersection#1', [r1, r2])
          as Rectangle;
      expect(result.left, 5);
      expect(result.top, 5);
      expect(result.width, 5);
      expect(result.height, 5);
    });

    test('intersection returns null for non-overlapping', () {
      final r1 = Rectangle(0, 0, 5, 5);
      final r2 = Rectangle(10, 10, 5, 5);
      expect(
          invoke('dart:math::Rectangle::intersection#1', [r1, r2]), isNull);
    });

    test('boundingBox is registered', () {
      expect(registry.lookupByName('dart:math::Rectangle::boundingBox#1'),
          isNot(equals(-1)));
    });

    test('boundingBox returns enclosing rectangle', () {
      final r1 = Rectangle(0, 0, 5, 5);
      final r2 = Rectangle(3, 3, 10, 10);
      final result = invoke('dart:math::Rectangle::boundingBox#1', [r1, r2])
          as Rectangle;
      expect(result.left, 0);
      expect(result.top, 0);
      expect(result.right, 13);
      expect(result.bottom, 13);
    });
  });

  group('MathBindings Rectangle.fromPoints', () {
    test('Rectangle.fromPoints is registered', () {
      expect(registry.lookupByName('dart:math::Rectangle::fromPoints#2'),
          isNot(equals(-1)));
    });

    test('Rectangle.fromPoints creates rectangle from two corners', () {
      final p1 = Point(1, 2);
      final p2 = Point(4, 6);
      final rect =
          invoke('dart:math::Rectangle::fromPoints#2', [p1, p2]) as Rectangle;
      expect(rect.left, 1);
      expect(rect.top, 2);
      expect(rect.width, 3);
      expect(rect.height, 4);
    });

    test('Rectangle.fromPoints handles reversed points', () {
      final p1 = Point(4, 6);
      final p2 = Point(1, 2);
      final rect =
          invoke('dart:math::Rectangle::fromPoints#2', [p1, p2]) as Rectangle;
      expect(rect.left, 1);
      expect(rect.top, 2);
      expect(rect.width, 3);
      expect(rect.height, 4);
    });
  });

  group('MathBindings MutableRectangle', () {
    test('MutableRectangle constructor is registered', () {
      expect(registry.lookupByName('dart:math::MutableRectangle::#4'),
          isNot(equals(-1)));
    });

    test('MutableRectangle constructor creates mutable rectangle', () {
      final rect =
          invoke('dart:math::MutableRectangle::#4', [1, 2, 10, 20])
              as MutableRectangle;
      expect(rect.left, 1);
      expect(rect.top, 2);
      expect(rect.width, 10);
      expect(rect.height, 20);
    });

    test('MutableRectangle.fromPoints is registered', () {
      expect(
          registry.lookupByName('dart:math::MutableRectangle::fromPoints#2'),
          isNot(equals(-1)));
    });

    test('MutableRectangle.fromPoints creates from two points', () {
      final rect = invoke('dart:math::MutableRectangle::fromPoints#2',
          [Point(1, 2), Point(4, 6)]) as MutableRectangle;
      expect(rect.left, 1);
      expect(rect.top, 2);
      expect(rect.width, 3);
      expect(rect.height, 4);
    });

    test('MutableRectangle getters work', () {
      final rect = MutableRectangle(0, 0, 10, 20);
      expect(invoke('dart:math::MutableRectangle::left#0', [rect]), 0);
      expect(invoke('dart:math::MutableRectangle::top#0', [rect]), 0);
      expect(invoke('dart:math::MutableRectangle::width#0', [rect]), 10);
      expect(invoke('dart:math::MutableRectangle::height#0', [rect]), 20);
      expect(invoke('dart:math::MutableRectangle::right#0', [rect]), 10);
      expect(invoke('dart:math::MutableRectangle::bottom#0', [rect]), 20);
    });

    test('MutableRectangle setters work', () {
      final rect = MutableRectangle(0, 0, 10, 20);
      invoke('dart:math::MutableRectangle::left=#1', [rect, 5]);
      expect(rect.left, 5);
      invoke('dart:math::MutableRectangle::top=#1', [rect, 3]);
      expect(rect.top, 3);
      invoke('dart:math::MutableRectangle::width=#1', [rect, 15]);
      expect(rect.width, 15);
      invoke('dart:math::MutableRectangle::height=#1', [rect, 25]);
      expect(rect.height, 25);
    });

    test('MutableRectangle toString/hashCode/==', () {
      final rect = MutableRectangle(1, 2, 3, 4);
      expect(invoke('dart:math::MutableRectangle::toString#0', [rect]),
          isA<String>());
      expect(invoke('dart:math::MutableRectangle::hashCode#0', [rect]),
          isA<int>());
      final rect2 = MutableRectangle(1, 2, 3, 4);
      expect(invoke('dart:math::MutableRectangle::==#1', [rect, rect2]), true);
    });

    test('MutableRectangle inherited methods', () {
      final rect = MutableRectangle(0, 0, 10, 10);
      final p = Point(5, 5);
      // These may resolve to Rectangle:: or MutableRectangle::
      expect(
          invoke('dart:math::MutableRectangle::containsPoint#1', [rect, p]),
          true);
      final rect2 = MutableRectangle(5, 5, 10, 10);
      expect(invoke('dart:math::MutableRectangle::intersects#1', [rect, rect2]),
          true);
      final inter =
          invoke('dart:math::MutableRectangle::intersection#1', [rect, rect2])
              as Rectangle;
      expect(inter.left, 5);
      final bbox =
          invoke('dart:math::MutableRectangle::boundingBox#1', [rect, rect2])
              as Rectangle;
      expect(bbox.left, 0);
      expect(bbox.right, 15);
    });
  });

  group('MathBindings Point', () {
    test('constructor and getters', () {
      final p = invoke('dart:math::Point::#2', [3, 4]) as Point;
      expect(invoke('dart:math::Point::x#0', [p]), 3);
      expect(invoke('dart:math::Point::y#0', [p]), 4);
    });

    test('distanceTo', () {
      final p1 = Point(0, 0);
      final p2 = Point(3, 4);
      expect(invoke('dart:math::Point::distanceTo#1', [p1, p2]), 5.0);
    });

    test('magnitude', () {
      final p = Point(3, 4);
      expect(invoke('dart:math::Point::magnitude#0', [p]), 5.0);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // E2E compile+run tests
  // ══════════════════════════════════════════════════════════════════

  group('MathBindings e2e', () {
    Future<(Object?, List<String>)> runMathWithHost(String source) async {
      final printLog = <String>[];
      final module = await compileDart(source);
      final reg = HostFunctionRegistry();
      CoreBindings.registerAll(reg, printFn: (v) => printLog.add('$v'));
      MathBindingsHub.registerAll(reg);
      final interp = DarticInterpreter(
        hostFunctionRegistry: reg,
        fuelBudget: DarticInterpreter.defaultFuelBudget,
      );
      interp.execute(module);
      return (interp.entryResult, printLog);
    }

    test('Rectangle.fromPoints + containsPoint', () async {
      final (_, prints) = await runMathWithHost('''
import 'dart:math';

void main() {
  var rect = Rectangle.fromPoints(Point(0, 0), Point(10, 10));
  print(rect.containsPoint(Point(5, 5)));
  print(rect.containsPoint(Point(15, 5)));
}
''');
      expect(prints, ['true', 'false']);
    });
  });
}
