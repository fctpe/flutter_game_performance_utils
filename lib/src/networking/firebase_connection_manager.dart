import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Centralized Firebase connection lifecycle manager for battery optimization
///
/// Manages Firebase stream subscriptions to optimize battery usage during
/// app lifecycle changes. Automatically pauses connections when app backgrounds.
///
/// Example usage:
/// ```dart
/// // Initialize during app startup
/// await FirebaseConnectionManager.initialize();
///
/// // Register Firebase listeners
/// final subscription = FirebaseFirestore.instance
///     .collection('games')
///     .doc(gameId)
///     .snapshots()
///     .listen((snapshot) {
///       // Handle updates
///     });
///
/// FirebaseConnectionManager.registerSubscription(subscription, id: 'game_$gameId');
///
/// // Cleanup when done
/// FirebaseConnectionManager.unregisterSubscription(subscription);
/// ```
class FirebaseConnectionManager with WidgetsBindingObserver {
  static final FirebaseConnectionManager _instance = 
      FirebaseConnectionManager._internal();
  factory FirebaseConnectionManager() => _instance;
  FirebaseConnectionManager._internal();

  final Map<String, StreamSubscription> _activeSubscriptions = {};
  final Map<String, StreamSubscription> _pausedSubscriptions = {};

  bool _isAppInBackground = false;
  bool _isInitialized = false;
  bool _isPaused = false;

  /// Initialize the connection manager - call during app startup
  static Future<void> initialize() async {
    final manager = FirebaseConnectionManager();
    if (!manager._isInitialized) {
      WidgetsBinding.instance.addObserver(manager);
      manager._isInitialized = true;
      if (kDebugMode) {
        print('[FirebaseConnectionManager] Initialized');
      }
    }
  }

  /// Register a Firebase stream subscription for lifecycle management
  static void registerSubscription(
    StreamSubscription subscription, {
    String? id,
  }) {
    final manager = FirebaseConnectionManager();
    final subscriptionId = 
        id ?? 'subscription_${DateTime.now().millisecondsSinceEpoch}';
    manager._activeSubscriptions[subscriptionId] = subscription;

    if (kDebugMode) {
      print('[FirebaseConnectionManager] Registered: $subscriptionId');
    }

    // If currently paused, immediately pause this subscription
    if (manager._isPaused) {
      manager._pauseSubscription(subscriptionId, subscription);
    }
  }

  /// Unregister a Firebase stream subscription
  static void unregisterSubscription(StreamSubscription subscription) {
    final manager = FirebaseConnectionManager();

    String? keyToRemove;
    for (final entry in manager._activeSubscriptions.entries) {
      if (entry.value == subscription) {
        keyToRemove = entry.key;
        break;
      }
    }

    if (keyToRemove != null) {
      manager._activeSubscriptions.remove(keyToRemove);
      manager._pausedSubscriptions.remove(keyToRemove);
      if (kDebugMode) {
        print('[FirebaseConnectionManager] Unregistered: $keyToRemove');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _handleAppBackgrounded();
        break;
      case AppLifecycleState.resumed:
        _handleAppForegrounded();
        break;
    }
  }

  void _handleAppBackgrounded() {
    if (_isAppInBackground) return;

    _isAppInBackground = true;
    if (kDebugMode) {
      print('[FirebaseConnectionManager] App backgrounded - pausing ${_activeSubscriptions.length} connections');
    }

    _pauseAllSubscriptions();
  }

  void _handleAppForegrounded() {
    if (!_isAppInBackground) return;

    _isAppInBackground = false;
    if (kDebugMode) {
      print('[FirebaseConnectionManager] App foregrounded - resuming ${_pausedSubscriptions.length} connections');
    }

    _resumeAllSubscriptions();
  }

  void _pauseAllSubscriptions() {
    if (_isPaused) return;
    _isPaused = true;

    // Iterate a snapshot, not the live map. `_pauseSubscription` removes the
    // entry it just paused, and mutating a Map while iterating its entries
    // throws ConcurrentModificationError on the next step — so with two or more
    // registered subscriptions, backgrounding the app crashed instead of
    // pausing anything. With exactly one it happened to work, which is why it
    // survived: the failure needs a second connection to appear.
    final snapshot = _activeSubscriptions.entries.toList(growable: false);
    for (final entry in snapshot) {
      _pauseSubscription(entry.key, entry.value);
    }
  }

  void _resumeAllSubscriptions() {
    if (!_isPaused) return;
    _isPaused = false;

    // Actually resume the streams. This used to move the entries back into
    // `_activeSubscriptions` and stop there, so every subscription stayed
    // paused for the rest of the process: `activeConnectionCount` reported
    // them as live, and no event was ever delivered again. A connection
    // manager that never reconnects is worse than no connection manager,
    // because the count says everything is fine.
    final resumed = <String, StreamSubscription>{};
    _pausedSubscriptions.forEach((id, subscription) {
      try {
        // `pause()` can nest; resume until the stream is genuinely listening
        // again rather than assuming a single matching call.
        while (subscription.isPaused) {
          subscription.resume();
        }
        resumed[id] = subscription;
      } catch (e) {
        // Keep going: one dead subscription must not strand the others paused.
        if (kDebugMode) {
          print('[FirebaseConnectionManager] Error resuming $id: $e');
        }
      }
    });

    _activeSubscriptions.addAll(resumed);
    _pausedSubscriptions.clear();
  }

  void _pauseSubscription(String id, StreamSubscription subscription) {
    try {
      subscription.pause();
      _pausedSubscriptions[id] = subscription;
      _activeSubscriptions.remove(id);
    } catch (e) {
      if (kDebugMode) {
        print('[FirebaseConnectionManager] Error pausing $id: $e');
      }
    }
  }

  /// Get current app background state
  static bool get isAppInBackground => 
      FirebaseConnectionManager()._isAppInBackground;

  /// Get count of active Firebase connections
  static int get activeConnectionCount => 
      FirebaseConnectionManager()._activeSubscriptions.length;

  /// Force cleanup all registered subscriptions
  static Future<void> cleanupAllConnections() async {
    final manager = FirebaseConnectionManager();

    for (final subscription in manager._activeSubscriptions.values) {
      try {
        await subscription.cancel();
      } catch (e) {
        if (kDebugMode) {
          print('[FirebaseConnectionManager] Error cancelling: $e');
        }
      }
    }

    for (final subscription in manager._pausedSubscriptions.values) {
      try {
        await subscription.cancel();
      } catch (e) {
        if (kDebugMode) {
          print('[FirebaseConnectionManager] Error cancelling: $e');
        }
      }
    }

    manager._activeSubscriptions.clear();
    manager._pausedSubscriptions.clear();
    manager._isPaused = false;
    // Both lifecycle flags, not just one. Clearing `_isPaused` while leaving
    // `_isAppInBackground` set wedged the manager: a later background event
    // early-returned (already backgrounded) so nothing paused, and a later
    // foreground event early-returned inside `_resumeAllSubscriptions` (not
    // paused) so nothing resumed. Cleanup has to leave the state coherent, and
    // "half reset" is not a state the two handlers can recover from.
    manager._isAppInBackground = false;
  }

  /// Dispose the connection manager
  static void dispose() {
    final manager = FirebaseConnectionManager();
    if (manager._isInitialized) {
      WidgetsBinding.instance.removeObserver(manager);
      manager._isInitialized = false;
      if (kDebugMode) {
        print('[FirebaseConnectionManager] Disposed');
      }
    }
  }

  /// Get debug information about current connections
  static Map<String, dynamic> getDebugInfo() {
    final manager = FirebaseConnectionManager();
    return {
      'isAppInBackground': manager._isAppInBackground,
      'activeConnectionCount': manager._activeSubscriptions.length,
      'pausedConnectionCount': manager._pausedSubscriptions.length,
      'isInitialized': manager._isInitialized,
      'isPaused': manager._isPaused,
    };
  }
}
