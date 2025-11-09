import 'dart:async';
import 'package:flutter/widgets.dart';

/// Utility class for performance optimizations
class PerformanceUtils {
  static final Map<String, Timer> _debouncers = {};
  static final Map<String, DateTime> _lastCallTimes = {};

  /// Debounced addPostFrameCallback that prevents excessive callback scheduling
  /// [key] - Unique identifier for the callback type
  /// [callback] - The function to execute
  /// [duration] - Debounce duration (defaults to 16ms - roughly 1 frame)
  static void debouncedPostFrameCallback(
    String key,
    VoidCallback callback, {
    Duration duration = const Duration(milliseconds: 16),
  }) {
    // Cancel any existing timer for this key
    _debouncers[key]?.cancel();
    
    // Create new debounced timer
    _debouncers[key] = Timer(duration, () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        callback();
      });
      _debouncers.remove(key);
    });
  }

  /// Throttled callback execution that limits frequency
  /// [key] - Unique identifier for the callback type  
  /// [callback] - The function to execute
  /// [throttleDuration] - Minimum time between executions (defaults to 32ms)
  static void throttledCallback(
    String key,
    VoidCallback callback, {
    Duration throttleDuration = const Duration(milliseconds: 32),
  }) {
    final now = DateTime.now();
    final lastCall = _lastCallTimes[key];
    
    if (lastCall == null || now.difference(lastCall) >= throttleDuration) {
      _lastCallTimes[key] = now;
      callback();
    }
  }

  /// Batch provider updates using Future.microtask for better performance
  /// [updates] - List of provider update functions to execute
  static void batchProviderUpdates(List<VoidCallback> updates) {
    Future.microtask(() {
      for (final update in updates) {
        update();
      }
    });
  }

  /// Clear all debounce timers (useful for cleanup)
  static void clearAllDebouncers() {
    for (final timer in _debouncers.values) {
      timer.cancel();
    }
    _debouncers.clear();
    _lastCallTimes.clear();
  }
} 