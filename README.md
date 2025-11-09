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
- `getCacheStats()` - Get cache statistics
- `clearCache()` - Clear all cached assets
- `isAssetCached()` - Check if asset is cached

### FirebaseConnectionManager

- `initialize()` - Setup lifecycle observer
- `registerSubscription()` - Track Firebase listener
- `unregisterSubscription()` - Remove tracked listener
- `cleanupAllConnections()` - Force cleanup all
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

## Credits

Built for **Sultan's Gambit** - A strategic card game with:
- 150+ cached card images
- Real-time Firebase multiplayer
- Optimized for battery life

## License

MIT License
