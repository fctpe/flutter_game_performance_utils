# Flutter Game Performance Utils

Performance optimization utilities for Flutter mobile games.

**Built for [Sultan's Gambit](https://sultansgambit.com)** and open sourced for the community.

## Features

- ⚡ **Debouncing & Throttling** - Prevent excessive callbacks
- 🎨 **Asset Caching** - Batched image preloading with progress tracking  
- 🔋 **Firebase Connection Manager** - Auto-pause connections when app backgrounds
- 📊 **Performance Monitoring** - Built-in debug utilities
- 🎯 **Production-tested** - Powers a commercial game

## Installation

```yaml
dependencies:
  flutter_game_performance_utils: ^0.1.0
```

## Quick Start

### Debouncing & Throttling

```dart
import 'package:flutter_game_performance_utils/flutter_game_performance_utils.dart';

// Debounce - wait for action to settle
PerformanceUtils.debouncedPostFrameCallback(
  'update_ui',
  () => updateUI(),
  duration: Duration(milliseconds: 16),
);

// Throttle - limit frequency
PerformanceUtils.throttledCallback(
  'on_scroll',
  () => loadMoreContent(),
  throttleDuration: Duration(milliseconds: 100),
);

// Batch provider updates
PerformanceUtils.batchProviderUpdates([
  () => ref.read(provider1.notifier).update(),
  () => ref.read(provider2.notifier).update(),
]);
```

### Asset Caching

```dart
final cacheService = GameAssetCacheService();

// Cache with progress tracking
await cacheService.cacheAssets(
  [
    'assets/images/card_1.webp',
    'assets/images/card_2.webp',
    // ... more assets
  ],
  batchSize: 10,
  onProgress: (loaded, total) {
    print('Cached $loaded/$total assets');
  },
);

// Check cache status
final stats = cacheService.getCacheStats();
print('Cached ${stats['totalCachedAssets']} assets');
```

### Firebase Connection Manager

```dart
// Initialize during app startup
await FirebaseConnectionManager.initialize();

// Register Firebase listeners
final subscription = FirebaseFirestore.instance
    .collection('games')
    .doc(gameId)
    .snapshots()
    .listen((snapshot) {
      // Handle updates
    });

FirebaseConnectionManager.registerSubscription(
  subscription,
  id: 'game_$gameId',
);

// Automatically pauses when app backgrounds!
// Automatically resumes when app foregrounds!

// Cleanup when done
FirebaseConnectionManager.unregisterSubscription(subscription);
```

## API Reference

### PerformanceUtils

- `debouncedPostFrameCallback()` - Debounce with frame callback
- `throttledCallback()` - Throttle execution frequency
- `batchProviderUpdates()` - Batch multiple provider updates
- `clearAllDebouncers()` - Cleanup all timers

### GameAssetCacheService

- `cacheAssets()` - Batch cache assets with progress
- `getCacheStats()` - Get cache statistics (cached *and* failed counts)
- `failedAssetPaths` - Paths that failed to load on the last attempt
- `clearCache()` - Clear cached and failed paths
- `isAssetCached()` - Check if asset is cached

A failed load is recorded as a failure, not a success. Worth stating, because it
used to be the other way round: the whole batch was marked cached once it
settled while the per-asset loader swallowed every error. A missing or typo'd
path was counted as loaded, reported in the success log, and — since the cached
set is what `cacheAssets` filters on — skipped on every later call, so it could
never be retried.

### FirebaseConnectionManager

- `initialize()` - Setup lifecycle observer
- `registerSubscription()` - Track Firebase listener
- `unregisterSubscription()` - Remove tracked listener
- `cleanupAllConnections()` - Force cleanup all
- `activeConnectionCount` / `isAppInBackground` - Current state
- `getDebugInfo()` - Debug connection state

## Battery Optimization

The Firebase Connection Manager automatically pauses all registered Firestore/Realtime Database listeners when your app goes to background, preventing unnecessary battery drain.

**Before (without manager):**
- Firebase listeners continue running in background
- Battery drains even when app is inactive
- Network requests continue

**After (with manager):**
- All listeners paused automatically
- Zero battery drain from Firebase when backgrounded
- Seamless resume when app returns

### What that promise actually cost to keep

Three defects sat in exactly that path until they were tested, and they are
listed here rather than quietly patched because each one made the manager
*report* success while delivering nothing:

- **Backgrounding crashed with two or more subscriptions.** The pause loop
  iterated the live subscription map while the per-subscription pause removed
  from it — `ConcurrentModificationError`. With exactly one registered
  subscription it worked, which is the shape a quick manual check uses.
- **Foregrounding never resumed anything.** Subscriptions were moved back into
  the active map without `resume()` ever being called, so they stayed paused for
  the life of the process while `activeConnectionCount` reported them live.
- **`cleanupAllConnections()` left the state half-reset**, clearing the paused
  flag but not the backgrounded one, after which neither handler could recover:
  backgrounding early-returned as already-backgrounded, foregrounding
  early-returned as not-paused.

Separately, `debouncedPostFrameCallback` now calls `scheduleFrame()`.
`addPostFrameCallback` registers work for the end of the next frame; it does not
cause one. With no frame scheduled the callback waited on some unrelated
repaint — and an idle app is precisely when a debounced callback fires.
[`test/`](test) covers all four.

## Credits

Built for **Sultan's Gambit** - A strategic card game with:
- 150+ cached card images
- Real-time Firebase multiplayer
- Optimized for battery life

## License

MIT License
