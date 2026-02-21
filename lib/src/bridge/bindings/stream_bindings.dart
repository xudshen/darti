/// Registers `dart:async::Stream` and `dart:async::StreamController` host
/// bindings for the CALL_HOST pipeline.
///
/// Covers Stream factory constructors, transformation methods, and
/// StreamController lifecycle management.
///
/// See: docs/design/04-interop.md
library;

import 'dart:async';

import '../host_function_registry.dart';

/// Registers all `dart:async::Stream` host function bindings.
abstract final class StreamBindings {
  static void register(HostFunctionRegistry registry) {
    // ══════════════════════════════════════════════════════════════════
    // Stream
    // ══════════════════════════════════════════════════════════════════

    // ── Factory constructors ──

    // Stream.fromIterable(Iterable<T> elements)
    registry.register('dart:async::Stream::fromIterable#1', (args) {
      return Stream.fromIterable(args[0] as Iterable);
    });

    // Stream.fromFuture(Future<T> future)
    registry.register('dart:async::Stream::fromFuture#1', (args) {
      return Stream.fromFuture(args[0] as Future);
    });

    // Stream.value(T value)
    registry.register('dart:async::Stream::value#1', (args) {
      return Stream.value(args[0]);
    });

    // Stream.error(Object error, [StackTrace? stackTrace])
    registry.register('dart:async::Stream::error#2', (args) {
      final error = args[0] as Object;
      final st = args.length > 1 ? args[1] as StackTrace? : null;
      return Stream.error(error, st);
    });

    // Stream.empty()
    registry.register('dart:async::Stream::empty#0', (args) {
      return const Stream.empty();
    });

    // ── Instance methods ──

    // stream.listen(void Function(T)? onData, {Function? onError,
    //               void Function()? onDone, bool? cancelOnError})
    registry.register('dart:async::Stream::listen#4', (args) {
      final stream = args[0] as Stream;
      final onData = args[1] as Function?;
      final onError = args.length > 2 ? args[2] as Function? : null;
      final onDone = args.length > 3 ? args[3] as Function? : null;
      final cancelOnError = args.length > 4 ? args[4] as bool? : null;
      return stream.listen(
        onData != null ? (e) => onData(e) : null,
        onError: onError,
        onDone: onDone != null ? () => onDone() : null,
        cancelOnError: cancelOnError,
      );
    });

    // stream.toList() → Future<List<T>>
    registry.register('dart:async::Stream::toList#0', (args) {
      return (args[0] as Stream).toList();
    });

    // stream.map<S>(S Function(T) convert) → Stream<S>
    registry.register('dart:async::Stream::map#1', (args) {
      final stream = args[0] as Stream;
      final convert = args[1] as Function;
      return stream.map((e) => convert(e));
    });

    // stream.where(bool Function(T) test) → Stream<T>
    registry.register('dart:async::Stream::where#1', (args) {
      final stream = args[0] as Stream;
      final test = args[1] as Function;
      return stream.where((e) => test(e) as bool);
    });

    // stream.first → Future<T>
    registry.register('dart:async::Stream::first#0', (args) {
      return (args[0] as Stream).first;
    });

    // stream.last → Future<T>
    registry.register('dart:async::Stream::last#0', (args) {
      return (args[0] as Stream).last;
    });

    // stream.length → Future<int>
    registry.register('dart:async::Stream::length#0', (args) {
      return (args[0] as Stream).length;
    });

    // stream.isEmpty → Future<bool>
    registry.register('dart:async::Stream::isEmpty#0', (args) {
      return (args[0] as Stream).isEmpty;
    });

    // stream.expand<S>(Iterable<S> Function(T) convert) → Stream<S>
    registry.register('dart:async::Stream::expand#1', (args) {
      final stream = args[0] as Stream;
      final convert = args[1] as Function;
      return stream.expand((e) => convert(e) as Iterable);
    });

    // stream.take(int count) → Stream<T>
    registry.register('dart:async::Stream::take#1', (args) {
      return (args[0] as Stream).take(args[1] as int);
    });

    // stream.skip(int count) → Stream<T>
    registry.register('dart:async::Stream::skip#1', (args) {
      return (args[0] as Stream).skip(args[1] as int);
    });

    // stream.every(bool Function(T) test) → Future<bool>
    registry.register('dart:async::Stream::every#1', (args) {
      final stream = args[0] as Stream;
      final test = args[1] as Function;
      return stream.every((e) => test(e) as bool);
    });

    // stream.any(bool Function(T) test) → Future<bool>
    registry.register('dart:async::Stream::any#1', (args) {
      final stream = args[0] as Stream;
      final test = args[1] as Function;
      return stream.any((e) => test(e) as bool);
    });

    // stream.contains(Object? needle) → Future<bool>
    registry.register('dart:async::Stream::contains#1', (args) {
      return (args[0] as Stream).contains(args[1]);
    });

    // stream.forEach(void Function(T) action) → Future<void>
    registry.register('dart:async::Stream::forEach#1', (args) {
      final stream = args[0] as Stream;
      final action = args[1] as Function;
      return stream.forEach((e) => action(e));
    });

    // stream.drain<E>([E? futureValue]) → Future<E>
    registry.register('dart:async::Stream::drain#1', (args) {
      return (args[0] as Stream).drain(args.length > 1 ? args[1] : null);
    });

    // stream.handleError(Function onError, {bool Function(dynamic)? test})
    registry.register('dart:async::Stream::handleError#2', (args) {
      final stream = args[0] as Stream;
      final onError = args[1] as Function;
      final test = args.length > 2 ? args[2] as Function? : null;
      return stream.handleError(
        onError,
        test: test != null ? (e) => test(e) as bool : null,
      );
    });

    // stream.asyncMap<E>(FutureOr<E> Function(T) convert) → Stream<E>
    registry.register('dart:async::Stream::asyncMap#1', (args) {
      final stream = args[0] as Stream;
      final convert = args[1] as Function;
      return stream.asyncMap((e) => convert(e) as FutureOr);
    });

    // stream.asyncExpand<E>(Stream<E>? Function(T) convert) → Stream<E>
    registry.register('dart:async::Stream::asyncExpand#1', (args) {
      final stream = args[0] as Stream;
      final convert = args[1] as Function;
      return stream.asyncExpand((e) => convert(e) as Stream?);
    });

    // stream.isBroadcast → bool
    registry.register('dart:async::Stream::isBroadcast#0', (args) {
      return (args[0] as Stream).isBroadcast;
    });

    // stream.asBroadcastStream({...}) → Stream<T>
    registry.register('dart:async::Stream::asBroadcastStream#2', (args) {
      return (args[0] as Stream).asBroadcastStream();
    });

    // stream.join([String separator = ""]) → Future<String>
    registry.register('dart:async::Stream::join#1', (args) {
      final stream = args[0] as Stream;
      final sep = args.length > 1 ? args[1] as String? : null;
      return stream.join(sep ?? '');
    });

    // stream.reduce(T Function(T, T) combine) → Future<T>
    registry.register('dart:async::Stream::reduce#1', (args) {
      final stream = args[0] as Stream;
      final combine = args[1] as Function;
      return stream.reduce((a, b) => combine(a, b));
    });

    // stream.fold<S>(S initialValue, S Function(S, T) combine) → Future<S>
    registry.register('dart:async::Stream::fold#2', (args) {
      final stream = args[0] as Stream;
      final initial = args[1];
      final combine = args[2] as Function;
      return stream.fold(initial, (prev, e) => combine(prev, e));
    });

    // stream.toSet() → Future<Set<T>>
    registry.register('dart:async::Stream::toSet#0', (args) {
      return (args[0] as Stream).toSet();
    });

    // stream.distinct([bool Function(T, T)? equals]) → Stream<T>
    registry.register('dart:async::Stream::distinct#1', (args) {
      final stream = args[0] as Stream;
      final equals = args.length > 1 ? args[1] as Function? : null;
      if (equals != null) {
        return stream.distinct((a, b) => equals(a, b) as bool);
      }
      return stream.distinct();
    });

    // stream.takeWhile(bool Function(T) test) → Stream<T>
    registry.register('dart:async::Stream::takeWhile#1', (args) {
      final stream = args[0] as Stream;
      final test = args[1] as Function;
      return stream.takeWhile((e) => test(e) as bool);
    });

    // stream.skipWhile(bool Function(T) test) → Stream<T>
    registry.register('dart:async::Stream::skipWhile#1', (args) {
      final stream = args[0] as Stream;
      final test = args[1] as Function;
      return stream.skipWhile((e) => test(e) as bool);
    });

    // stream.singleWhere(bool Function(T) test, {T Function()? orElse})
    registry.register('dart:async::Stream::singleWhere#2', (args) {
      final stream = args[0] as Stream;
      final test = args[1] as Function;
      final orElse = args.length > 2 ? args[2] as Function? : null;
      if (orElse != null) {
        return stream.singleWhere((e) => test(e) as bool,
            orElse: () => orElse());
      }
      return stream.singleWhere((e) => test(e) as bool);
    });

    // stream.firstWhere(bool Function(T) test, {T Function()? orElse})
    registry.register('dart:async::Stream::firstWhere#2', (args) {
      final stream = args[0] as Stream;
      final test = args[1] as Function;
      final orElse = args.length > 2 ? args[2] as Function? : null;
      if (orElse != null) {
        return stream.firstWhere((e) => test(e) as bool,
            orElse: () => orElse());
      }
      return stream.firstWhere((e) => test(e) as bool);
    });

    // stream.lastWhere(bool Function(T) test, {T Function()? orElse})
    registry.register('dart:async::Stream::lastWhere#2', (args) {
      final stream = args[0] as Stream;
      final test = args[1] as Function;
      final orElse = args.length > 2 ? args[2] as Function? : null;
      if (orElse != null) {
        return stream.lastWhere((e) => test(e) as bool,
            orElse: () => orElse());
      }
      return stream.lastWhere((e) => test(e) as bool);
    });

    // stream.single → Future<T>
    registry.register('dart:async::Stream::single#0', (args) {
      return (args[0] as Stream).single;
    });

    // stream.cast<R>() → Stream<R>
    registry.register('dart:async::Stream::cast#0', (args) {
      return (args[0] as Stream).cast();
    });

    // stream.pipe(StreamConsumer<T> streamConsumer) → Future
    registry.register('dart:async::Stream::pipe#1', (args) {
      return (args[0] as Stream).pipe(args[1] as StreamConsumer);
    });

    // stream.timeout(Duration timeLimit, {void Function(EventSink)? onTimeout})
    registry.register('dart:async::Stream::timeout#2', (args) {
      final stream = args[0] as Stream;
      final timeLimit = args[1] as Duration;
      final onTimeout = args.length > 2 ? args[2] as Function? : null;
      if (onTimeout != null) {
        return stream.timeout(timeLimit,
            onTimeout: (sink) => onTimeout(sink));
      }
      return stream.timeout(timeLimit);
    });

    // stream.transform<S>(StreamTransformer<T, S> transformer) → Stream<S>
    registry.register('dart:async::Stream::transform#1', (args) {
      return (args[0] as Stream)
          .transform(args[1] as StreamTransformer);
    });

    // ══════════════════════════════════════════════════════════════════
    // StreamController
    // ══════════════════════════════════════════════════════════════════

    // StreamController({void Function()? onListen, void Function()? onPause,
    //                   void Function()? onResume, FutureOr<void> Function()? onCancel,
    //                   bool sync = false})
    registry.register('dart:async::StreamController::#5', (args) {
      final onListen = args.isNotEmpty ? args[0] as Function? : null;
      final onPause = args.length > 1 ? args[1] as Function? : null;
      final onResume = args.length > 2 ? args[2] as Function? : null;
      final onCancel = args.length > 3 ? args[3] as Function? : null;
      final sync = args.length > 4 ? args[4] as bool? ?? false : false;
      return StreamController<Object?>(
        onListen: onListen != null ? () => onListen() : null,
        onPause: onPause != null ? () => onPause() : null,
        onResume: onResume != null ? () => onResume() : null,
        onCancel: onCancel != null ? () => onCancel() as FutureOr<void> : null,
        sync: sync,
      );
    });

    // StreamController.broadcast({void Function()? onListen, void Function()? onCancel, bool sync})
    registry.register('dart:async::StreamController::broadcast#3', (args) {
      final onListen = args.isNotEmpty ? args[0] as Function? : null;
      final onCancel = args.length > 1 ? args[1] as Function? : null;
      final sync = args.length > 2 ? args[2] as bool? ?? false : false;
      return StreamController<Object?>.broadcast(
        onListen: onListen != null ? () => onListen() : null,
        onCancel: onCancel != null ? () => onCancel() : null,
        sync: sync,
      );
    });

    // controller.add(T event)
    registry.register('dart:async::StreamController::add#1', (args) {
      (args[0] as StreamController).add(args[1]);
      return null;
    });

    // controller.addError(Object error, [StackTrace? stackTrace])
    registry.register('dart:async::StreamController::addError#2', (args) {
      final controller = args[0] as StreamController;
      final error = args[1] as Object;
      final st = args.length > 2 ? args[2] as StackTrace? : null;
      if (st != null) {
        controller.addError(error, st);
      } else {
        controller.addError(error);
      }
      return null;
    });

    // controller.close() → Future
    registry.register('dart:async::StreamController::close#0', (args) {
      return (args[0] as StreamController).close();
    });

    // controller.stream → Stream<T>
    registry.register('dart:async::StreamController::stream#0', (args) {
      return (args[0] as StreamController).stream;
    });

    // controller.sink → StreamSink<T>
    registry.register('dart:async::StreamController::sink#0', (args) {
      return (args[0] as StreamController).sink;
    });

    // controller.done → Future
    registry.register('dart:async::StreamController::done#0', (args) {
      return (args[0] as StreamController).done;
    });

    // controller.hasListener → bool
    registry.register('dart:async::StreamController::hasListener#0', (args) {
      return (args[0] as StreamController).hasListener;
    });

    // controller.isClosed → bool
    registry.register('dart:async::StreamController::isClosed#0', (args) {
      return (args[0] as StreamController).isClosed;
    });

    // controller.isPaused → bool
    registry.register('dart:async::StreamController::isPaused#0', (args) {
      return (args[0] as StreamController).isPaused;
    });

    // controller.addStream(Stream<T> source, {bool? cancelOnError})
    registry.register('dart:async::StreamController::addStream#2', (args) {
      final controller = args[0] as StreamController;
      final source = args[1] as Stream;
      final cancelOnError = args.length > 2 ? args[2] as bool? : null;
      return controller.addStream(source, cancelOnError: cancelOnError);
    });

    // ══════════════════════════════════════════════════════════════════
    // StreamSubscription
    // ══════════════════════════════════════════════════════════════════

    // subscription.cancel() → Future<void>
    registry.register('dart:async::StreamSubscription::cancel#0', (args) {
      return (args[0] as StreamSubscription).cancel();
    });

    // subscription.pause([Future<void>? resumeSignal])
    registry.register('dart:async::StreamSubscription::pause#1', (args) {
      final sub = args[0] as StreamSubscription;
      final resumeSignal = args.length > 1 ? args[1] as Future<void>? : null;
      sub.pause(resumeSignal);
      return null;
    });

    // subscription.resume()
    registry.register('dart:async::StreamSubscription::resume#0', (args) {
      (args[0] as StreamSubscription).resume();
      return null;
    });

    // subscription.isPaused → bool
    registry.register('dart:async::StreamSubscription::isPaused#0', (args) {
      return (args[0] as StreamSubscription).isPaused;
    });

    // subscription.onData(void Function(T)? handleData)
    registry.register('dart:async::StreamSubscription::onData#1', (args) {
      final sub = args[0] as StreamSubscription;
      final handler = args[1] as Function?;
      sub.onData(handler != null ? (e) => handler(e) : null);
      return null;
    });

    // subscription.onError(Function? handleError)
    registry.register('dart:async::StreamSubscription::onError#1', (args) {
      (args[0] as StreamSubscription).onError(args[1] as Function?);
      return null;
    });

    // subscription.onDone(void Function()? handleDone)
    registry.register('dart:async::StreamSubscription::onDone#1', (args) {
      final sub = args[0] as StreamSubscription;
      final handler = args[1] as Function?;
      sub.onDone(handler != null ? () => handler() : null);
      return null;
    });

    // subscription.asFuture<E>([E? futureValue]) → Future<E>
    registry.register('dart:async::StreamSubscription::asFuture#1', (args) {
      return (args[0] as StreamSubscription)
          .asFuture(args.length > 1 ? args[1] : null);
    });
  }
}
