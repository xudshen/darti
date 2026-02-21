/// Registers `dart:math` host bindings for the CALL_HOST pipeline.
///
/// Covers top-level math functions (min, max, sqrt, pow, sin, cos, tan, log,
/// exp, atan2), the Random class, and the Point class.
///
/// Constants (pi, e) are compiled as inline constants by the CFE and do not
/// generate CALL_HOST bindings.
///
/// See: docs/design/04-interop.md
library;

import 'dart:math';

import '../host_function_registry.dart';

/// Registers all `dart:math` host function bindings.
abstract final class MathBindings {
  static void register(HostFunctionRegistry registry) {
    // ── Top-level functions ──

    registry.register('dart:math::::min#2', (args) {
      return min(args[0] as num, args[1] as num);
    });
    registry.register('dart:math::::max#2', (args) {
      return max(args[0] as num, args[1] as num);
    });
    registry.register('dart:math::::sqrt#1', (args) {
      return sqrt(args[0] as num);
    });
    registry.register('dart:math::::pow#2', (args) {
      return pow(args[0] as num, args[1] as num);
    });
    registry.register('dart:math::::sin#1', (args) {
      return sin(args[0] as num);
    });
    registry.register('dart:math::::cos#1', (args) {
      return cos(args[0] as num);
    });
    registry.register('dart:math::::tan#1', (args) {
      return tan(args[0] as num);
    });
    registry.register('dart:math::::log#1', (args) {
      return log(args[0] as num);
    });
    registry.register('dart:math::::exp#1', (args) {
      return exp(args[0] as num);
    });
    registry.register('dart:math::::atan2#2', (args) {
      return atan2(args[0] as num, args[1] as num);
    });
    registry.register('dart:math::::asin#1', (args) {
      return asin(args[0] as num);
    });
    registry.register('dart:math::::acos#1', (args) {
      return acos(args[0] as num);
    });
    registry.register('dart:math::::atan#1', (args) {
      return atan(args[0] as num);
    });

    // ── Random ──

    // Random([int? seed])
    registry.register('dart:math::Random::#1', (args) {
      final seed = args.isNotEmpty ? args[0] as int? : null;
      return Random(seed);
    });

    // Random.secure()
    registry.register('dart:math::Random::secure#0', (args) {
      return Random.secure();
    });

    // random.nextInt(int max) → int
    registry.register('dart:math::Random::nextInt#1', (args) {
      return (args[0] as Random).nextInt(args[1] as int);
    });

    // random.nextDouble() → double
    registry.register('dart:math::Random::nextDouble#0', (args) {
      return (args[0] as Random).nextDouble();
    });

    // random.nextBool() → bool
    registry.register('dart:math::Random::nextBool#0', (args) {
      return (args[0] as Random).nextBool();
    });

    // ── Point ──

    // Point(T x, T y)
    registry.register('dart:math::Point::#2', (args) {
      return Point(args[0] as num, args[1] as num);
    });

    // point.x → T
    registry.register('dart:math::Point::x#0', (args) {
      return (args[0] as Point).x;
    });

    // point.y → T
    registry.register('dart:math::Point::y#0', (args) {
      return (args[0] as Point).y;
    });

    // point.magnitude → double
    registry.register('dart:math::Point::magnitude#0', (args) {
      return (args[0] as Point).magnitude;
    });

    // point.distanceTo(Point<T> other) → double
    registry.register('dart:math::Point::distanceTo#1', (args) {
      return (args[0] as Point).distanceTo(args[1] as Point);
    });

    // point.squaredDistanceTo(Point<T> other) → T
    registry.register('dart:math::Point::squaredDistanceTo#1', (args) {
      return (args[0] as Point).squaredDistanceTo(args[1] as Point);
    });

    // point + Point<T> other → Point<T>
    registry.register('dart:math::Point::+#1', (args) {
      return (args[0] as Point) + (args[1] as Point);
    });

    // point - Point<T> other → Point<T>
    registry.register('dart:math::Point::-#1', (args) {
      return (args[0] as Point) - (args[1] as Point);
    });

    // point * num factor → Point<T>
    registry.register('dart:math::Point::*#1', (args) {
      return (args[0] as Point) * (args[1] as num);
    });

    // point.toString()
    registry.register('dart:math::Point::toString#0', (args) {
      return (args[0] as Point).toString();
    });

    // point.hashCode
    registry.register('dart:math::Point::hashCode#0', (args) {
      return (args[0] as Point).hashCode;
    });

    // point == other
    registry.register('dart:math::Point::==#1', (args) {
      return args[0] == args[1];
    });

    // ── Point _#fromFields (for InstanceConstant reconstruction) ──
    // Point has fields: x, y (sorted by name: [x, y])
    registry.register('dart:math::Point::_#fromFields#2', (args) {
      return Point(args[0] as num, args[1] as num);
    });

    // ── Rectangle ──

    // Rectangle(T left, T top, T width, T height)
    registry.register('dart:math::Rectangle::#4', (args) {
      return Rectangle(
          args[0] as num, args[1] as num, args[2] as num, args[3] as num);
    });

    // Rectangle.fromPoints(Point<T> a, Point<T> b) → Rectangle<T>
    registry.register('dart:math::Rectangle::fromPoints#2', (args) {
      return Rectangle.fromPoints(args[0] as Point, args[1] as Point);
    });

    // rectangle.left → T
    registry.register('dart:math::Rectangle::left#0', (args) {
      return (args[0] as Rectangle).left;
    });

    // rectangle.top → T
    registry.register('dart:math::Rectangle::top#0', (args) {
      return (args[0] as Rectangle).top;
    });

    // rectangle.width → T
    registry.register('dart:math::Rectangle::width#0', (args) {
      return (args[0] as Rectangle).width;
    });

    // rectangle.height → T
    registry.register('dart:math::Rectangle::height#0', (args) {
      return (args[0] as Rectangle).height;
    });

    // rectangle.right → T
    registry.register('dart:math::Rectangle::right#0', (args) {
      return (args[0] as Rectangle).right;
    });

    // rectangle.bottom → T
    registry.register('dart:math::Rectangle::bottom#0', (args) {
      return (args[0] as Rectangle).bottom;
    });

    // rectangle.containsPoint(Point<num> another) → bool
    registry.register('dart:math::Rectangle::containsPoint#1', (args) {
      return (args[0] as Rectangle).containsPoint(args[1] as Point);
    });

    // rectangle.intersects(Rectangle<num> other) → bool
    registry.register('dart:math::Rectangle::intersects#1', (args) {
      return (args[0] as Rectangle).intersects(args[1] as Rectangle);
    });

    // rectangle.intersection(Rectangle<num> other) → Rectangle<num>?
    registry.register('dart:math::Rectangle::intersection#1', (args) {
      return (args[0] as Rectangle).intersection(args[1] as Rectangle);
    });

    // rectangle.boundingBox(Rectangle<num> other) → Rectangle<num>
    registry.register('dart:math::Rectangle::boundingBox#1', (args) {
      return (args[0] as Rectangle).boundingBox(args[1] as Rectangle);
    });

    // rectangle.toString()
    registry.register('dart:math::Rectangle::toString#0', (args) {
      return (args[0] as Rectangle).toString();
    });

    // rectangle.hashCode
    registry.register('dart:math::Rectangle::hashCode#0', (args) {
      return (args[0] as Rectangle).hashCode;
    });

    // rectangle == other
    registry.register('dart:math::Rectangle::==#1', (args) {
      return args[0] == args[1];
    });

    // ── _RectangleBase (internal base class) ──
    // CFE may resolve Rectangle methods to _RectangleBase.

    registry.register('dart:math::_RectangleBase::left#0', (args) {
      return (args[0] as Rectangle).left;
    });
    registry.register('dart:math::_RectangleBase::top#0', (args) {
      return (args[0] as Rectangle).top;
    });
    registry.register('dart:math::_RectangleBase::width#0', (args) {
      return (args[0] as Rectangle).width;
    });
    registry.register('dart:math::_RectangleBase::height#0', (args) {
      return (args[0] as Rectangle).height;
    });
    registry.register('dart:math::_RectangleBase::right#0', (args) {
      return (args[0] as Rectangle).right;
    });
    registry.register('dart:math::_RectangleBase::bottom#0', (args) {
      return (args[0] as Rectangle).bottom;
    });
    registry.register('dart:math::_RectangleBase::containsPoint#1', (args) {
      return (args[0] as Rectangle).containsPoint(args[1] as Point);
    });
    registry.register('dart:math::_RectangleBase::intersects#1', (args) {
      return (args[0] as Rectangle).intersects(args[1] as Rectangle);
    });
    registry.register('dart:math::_RectangleBase::intersection#1', (args) {
      return (args[0] as Rectangle).intersection(args[1] as Rectangle);
    });
    registry.register('dart:math::_RectangleBase::boundingBox#1', (args) {
      return (args[0] as Rectangle).boundingBox(args[1] as Rectangle);
    });
    registry.register('dart:math::_RectangleBase::toString#0', (args) {
      return (args[0] as Rectangle).toString();
    });
    registry.register('dart:math::_RectangleBase::hashCode#0', (args) {
      return (args[0] as Rectangle).hashCode;
    });
    registry.register('dart:math::_RectangleBase::==#1', (args) {
      return args[0] == args[1];
    });

    // ── MutableRectangle ──

    // MutableRectangle(T left, T top, T width, T height)
    registry.register('dart:math::MutableRectangle::#4', (args) {
      return MutableRectangle(
          args[0] as num, args[1] as num, args[2] as num, args[3] as num);
    });

    // MutableRectangle.fromPoints(Point<T> a, Point<T> b)
    registry.register('dart:math::MutableRectangle::fromPoints#2', (args) {
      return MutableRectangle.fromPoints(
          args[0] as Point, args[1] as Point);
    });

    // ── MutableRectangle getters ──

    registry.register('dart:math::MutableRectangle::left#0', (args) {
      return (args[0] as MutableRectangle).left;
    });
    registry.register('dart:math::MutableRectangle::top#0', (args) {
      return (args[0] as MutableRectangle).top;
    });
    registry.register('dart:math::MutableRectangle::width#0', (args) {
      return (args[0] as MutableRectangle).width;
    });
    registry.register('dart:math::MutableRectangle::height#0', (args) {
      return (args[0] as MutableRectangle).height;
    });
    registry.register('dart:math::MutableRectangle::right#0', (args) {
      return (args[0] as MutableRectangle).right;
    });
    registry.register('dart:math::MutableRectangle::bottom#0', (args) {
      return (args[0] as MutableRectangle).bottom;
    });

    // ── MutableRectangle setters ──

    registry.register('dart:math::MutableRectangle::left=#1', (args) {
      (args[0] as MutableRectangle).left = args[1] as num;
      return args[1];
    });
    registry.register('dart:math::MutableRectangle::top=#1', (args) {
      (args[0] as MutableRectangle).top = args[1] as num;
      return args[1];
    });
    registry.register('dart:math::MutableRectangle::width=#1', (args) {
      (args[0] as MutableRectangle).width = args[1] as num;
      return args[1];
    });
    registry.register('dart:math::MutableRectangle::height=#1', (args) {
      (args[0] as MutableRectangle).height = args[1] as num;
      return args[1];
    });

    // ── MutableRectangle inherited methods ──
    // CFE may resolve to MutableRectangle:: rather than Rectangle::

    registry.register('dart:math::MutableRectangle::containsPoint#1', (args) {
      return (args[0] as MutableRectangle).containsPoint(args[1] as Point);
    });
    registry.register('dart:math::MutableRectangle::intersects#1', (args) {
      return (args[0] as MutableRectangle)
          .intersects(args[1] as Rectangle);
    });
    registry.register('dart:math::MutableRectangle::intersection#1', (args) {
      return (args[0] as MutableRectangle)
          .intersection(args[1] as Rectangle);
    });
    registry.register('dart:math::MutableRectangle::boundingBox#1', (args) {
      return (args[0] as MutableRectangle)
          .boundingBox(args[1] as Rectangle);
    });

    // ── MutableRectangle Object methods ──

    registry.register('dart:math::MutableRectangle::toString#0', (args) {
      return (args[0] as MutableRectangle).toString();
    });
    registry.register('dart:math::MutableRectangle::hashCode#0', (args) {
      return (args[0] as MutableRectangle).hashCode;
    });
    registry.register('dart:math::MutableRectangle::==#1', (args) {
      return args[0] == args[1];
    });
  }
}
