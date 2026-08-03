import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_game_performance_utils/flutter_game_performance_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two defects this pins, both in the lifecycle path that is the package's
/// entire reason to exist:
///
/// 1. `_pauseAllSubscriptions` iterated `_activeSubscriptions.entries` while
///    `_pauseSubscription` removed from that same map — a
///    ConcurrentModificationError as soon as a second subscription existed.
///    With exactly one it happened to work, which is why nobody hit it.
/// 2. `_resumeAllSubscriptions` moved entries back into the active map without
///    ever calling `resume()`. Every subscription stayed paused for the rest of
///    the process while `activeConnectionCount` reported them live — a
///    connection manager that reports healthy and delivers nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manager = FirebaseConnectionManager();

  /// A subscription on a stream that never completes, so `isPaused` is a
  /// meaningful reading rather than an artefact of the stream having ended.
  StreamSubscription<int> makeSubscription() =>
      StreamController<int>.broadcast().stream.listen((_) {});

  setUp(() async {
    await FirebaseConnectionManager.cleanupAllConnections();
  });

  tearDown(() async {
    await FirebaseConnectionManager.cleanupAllConnections();
  });

  group('backgrounding with several subscriptions', () {
    test('does not throw ConcurrentModificationError', () {
      // Three, not one: the bug is invisible with a single entry, which is
      // exactly the shape a quick manual check would have used.
      for (var i = 0; i < 3; i++) {
        FirebaseConnectionManager.registerSubscription(makeSubscription(),
            id: 'sub_$i');
      }
      expect(FirebaseConnectionManager.activeConnectionCount, 3);

      expect(
        () => manager.didChangeAppLifecycleState(AppLifecycleState.paused),
        returnsNormally,
      );
    });

    test('pauses every subscription, not just the first', () {
      final subs = [
        for (var i = 0; i < 3; i++) makeSubscription(),
      ];
      for (var i = 0; i < subs.length; i++) {
        FirebaseConnectionManager.registerSubscription(subs[i], id: 'sub_$i');
      }

      manager.didChangeAppLifecycleState(AppLifecycleState.paused);

      for (final sub in subs) {
        expect(sub.isPaused, isTrue);
      }
      expect(FirebaseConnectionManager.activeConnectionCount, 0);
      expect(FirebaseConnectionManager.isAppInBackground, isTrue);
    });

    test('a single subscription still works — the old happy path', () {
      // Negative control for the fix: whatever the snapshot change did, it must
      // not break the one case that previously worked.
      final sub = makeSubscription();
      FirebaseConnectionManager.registerSubscription(sub, id: 'only');
      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(sub.isPaused, isTrue);
    });
  });

  group('foregrounding', () {
    test('actually resumes the streams', () {
      final subs = [
        for (var i = 0; i < 3; i++) makeSubscription(),
      ];
      for (var i = 0; i < subs.length; i++) {
        FirebaseConnectionManager.registerSubscription(subs[i], id: 'sub_$i');
      }

      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(subs.every((s) => s.isPaused), isTrue);

      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);

      // The assertion that used to fail: the count came back but the streams
      // stayed paused.
      for (final sub in subs) {
        expect(sub.isPaused, isFalse,
            reason: 'subscription reported active but is still paused');
      }
      expect(FirebaseConnectionManager.activeConnectionCount, 3);
      expect(FirebaseConnectionManager.isAppInBackground, isFalse);
    });

    test('delivers events again after a background/foreground cycle', () {
      // The behavioural version of the check above: `isPaused` is an
      // implementation detail, "events arrive" is the promise.
      final controller = StreamController<int>.broadcast();
      final received = <int>[];
      final sub = controller.stream.listen(received.add);
      FirebaseConnectionManager.registerSubscription(sub, id: 'events');

      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);

      controller.add(1);
      controller.add(2);

      return Future<void>.delayed(Duration.zero, () {
        expect(received, [1, 2]);
        controller.close();
      });
    });

    test('a subscription registered while backgrounded is paused, then resumed',
        () {
      manager.didChangeAppLifecycleState(AppLifecycleState.paused);

      final late_ = makeSubscription();
      FirebaseConnectionManager.registerSubscription(late_, id: 'late');
      expect(late_.isPaused, isTrue);

      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(late_.isPaused, isFalse);
    });
  });

  group('repeated lifecycle events', () {
    test('surviving several cycles leaves every stream live', () {
      final subs = [
        for (var i = 0; i < 2; i++) makeSubscription(),
      ];
      for (var i = 0; i < subs.length; i++) {
        FirebaseConnectionManager.registerSubscription(subs[i], id: 'sub_$i');
      }

      for (var cycle = 0; cycle < 3; cycle++) {
        manager.didChangeAppLifecycleState(AppLifecycleState.paused);
        manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      }

      for (final sub in subs) {
        expect(sub.isPaused, isFalse);
      }
      expect(FirebaseConnectionManager.activeConnectionCount, 2);
    });

    test('a duplicate background event is a no-op', () {
      final sub = makeSubscription();
      FirebaseConnectionManager.registerSubscription(sub, id: 'dup');
      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(
        () => manager.didChangeAppLifecycleState(AppLifecycleState.inactive),
        returnsNormally,
      );
      expect(sub.isPaused, isTrue);
    });
  });
}
