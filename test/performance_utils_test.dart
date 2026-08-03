import 'package:flutter/widgets.dart';
import 'package:flutter_game_performance_utils/flutter_game_performance_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// The third exported module had no coverage at all. These pin the behaviour
/// the README promises — debounce collapses a burst, throttle rate-limits one,
/// both are keyed independently, and cleanup releases the timers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(PerformanceUtils.clearAllDebouncers);
  tearDown(PerformanceUtils.clearAllDebouncers);

  group('debouncedPostFrameCallback', () {
    // A widget tree has to exist for frames to be produced at all. The
    // other half of that — that the debouncer must call `scheduleFrame()`
    // itself, since `addPostFrameCallback` does not cause a frame — was a
    // real bug these tests found: with no frame scheduled the callback sat
    // queued indefinitely, and an idle app is exactly when a debounced
    // callback fires.
    Future<void> withFrames(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox.shrink());

    testWidgets('a burst of calls fires once', (tester) async {
      await withFrames(tester);
      var calls = 0;
      for (var i = 0; i < 5; i++) {
        PerformanceUtils.debouncedPostFrameCallback('burst', () => calls++);
      }
      expect(calls, 0, reason: 'must not fire synchronously');

      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 1);
    });

    testWidgets('different keys do not collapse into each other', (tester) async {
      await withFrames(tester);
      // Keying is the whole design; sharing one timer across keys would make
      // two unrelated subsystems silently cancel each other.
      var a = 0;
      var b = 0;
      PerformanceUtils.debouncedPostFrameCallback('a', () => a++);
      PerformanceUtils.debouncedPostFrameCallback('b', () => b++);

      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 1));
      expect(a, 1);
      expect(b, 1);
    });

    testWidgets('a later call postpones the pending one', (tester) async {
      await withFrames(tester);
      var calls = 0;
      PerformanceUtils.debouncedPostFrameCallback(
        'slide',
        () => calls++,
        duration: const Duration(milliseconds: 50),
      );
      await tester.pump(const Duration(milliseconds: 30));
      PerformanceUtils.debouncedPostFrameCallback(
        'slide',
        () => calls++,
        duration: const Duration(milliseconds: 50),
      );

      // The original deadline passes; the restart means nothing has fired yet.
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 0);

      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 1);
    });

    testWidgets('clearAllDebouncers cancels a pending callback', (tester) async {
      await withFrames(tester);
      var calls = 0;
      PerformanceUtils.debouncedPostFrameCallback(
        'cancelled',
        () => calls++,
        duration: const Duration(milliseconds: 50),
      );
      PerformanceUtils.clearAllDebouncers();

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 0);
    });
  });

  group('throttledCallback', () {
    test('the first call goes through immediately', () {
      var calls = 0;
      PerformanceUtils.throttledCallback('scroll', () => calls++);
      expect(calls, 1);
    });

    test('a rapid second call is dropped', () {
      var calls = 0;
      PerformanceUtils.throttledCallback('scroll', () => calls++);
      PerformanceUtils.throttledCallback('scroll', () => calls++);
      PerformanceUtils.throttledCallback('scroll', () => calls++);
      expect(calls, 1);
    });

    test('a call after the window goes through', () async {
      var calls = 0;
      PerformanceUtils.throttledCallback(
        'scroll',
        () => calls++,
        throttleDuration: const Duration(milliseconds: 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));
      PerformanceUtils.throttledCallback(
        'scroll',
        () => calls++,
        throttleDuration: const Duration(milliseconds: 10),
      );
      expect(calls, 2);
    });

    test('keys are throttled independently', () {
      var a = 0;
      var b = 0;
      PerformanceUtils.throttledCallback('a', () => a++);
      PerformanceUtils.throttledCallback('b', () => b++);
      expect(a, 1);
      expect(b, 1);
    });
  });

  group('batchProviderUpdates', () {
    test('runs every update, in order, off the current tick', () async {
      final order = <int>[];
      PerformanceUtils.batchProviderUpdates([
        () => order.add(1),
        () => order.add(2),
        () => order.add(3),
      ]);
      expect(order, isEmpty, reason: 'must be deferred to a microtask');

      await Future<void>.microtask(() {});
      expect(order, [1, 2, 3]);
    });

    test('an empty batch is harmless', () async {
      PerformanceUtils.batchProviderUpdates([]);
      await Future<void>.microtask(() {});
    });
  });
}
