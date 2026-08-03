import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Service for intelligently caching game assets (images) with batched preloading
///
/// Perfect for card games, board games, or any app with many visual assets.
/// Provides memory-efficient batched loading with progress tracking.
class GameAssetCacheService {
  final Set<String> _cachedAssetPaths = {};

  /// Paths that were attempted and failed. Tracked separately from
  /// `_cachedAssetPaths` so a failure is neither counted as a success nor
  /// permanently skipped: `cacheAssets` filters on what is *cached*, so a
  /// failed path stays eligible for a later retry.
  final Set<String> _failedAssetPaths = {};

  bool _isCaching = false;

  /// Paths that failed to load on the last attempt.
  Set<String> get failedAssetPaths => Set.unmodifiable(_failedAssetPaths);

  /// Cache a list of asset paths in batches
  ///
  /// [assetPaths] - List of asset paths (e.g., 'assets/images/card.webp')
  /// [batchSize] - Number of assets to load simultaneously (default: 10)
  /// [onProgress] - Optional callback for progress tracking
  Future<void> cacheAssets(
    List<String> assetPaths, {
    int batchSize = 10,
    void Function(int loaded, int total)? onProgress,
  }) async {
    if (_isCaching) {
      if (kDebugMode) {
        print('[GameAssetCache] Already caching, skipping...');
      }
      return;
    }

    _isCaching = true;
    
    try {
      // Filter out already cached assets
      final uncachedPaths = assetPaths
          .where((path) => !_cachedAssetPaths.contains(path))
          .toList();

      if (uncachedPaths.isEmpty) {
        if (kDebugMode) {
          print('[GameAssetCache] All assets already cached');
        }
        return;
      }

      if (kDebugMode) {
        print('[GameAssetCache] Caching ${uncachedPaths.length} assets in batches of $batchSize');
      }

      // Process in batches
      final batches = <List<String>>[];
      for (int i = 0; i < uncachedPaths.length; i += batchSize) {
        final end = (i + batchSize < uncachedPaths.length) 
            ? i + batchSize 
            : uncachedPaths.length;
        batches.add(uncachedPaths.sublist(i, end));
      }

      int loadedCount = 0;
      int failedCount = 0;
      for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        final batch = batches[batchIndex];

        // Record only what actually loaded.
        //
        // This used to `addAll(batch)` unconditionally after the batch settled,
        // while `_preloadSingleAsset` swallowed every failure — so a typo'd or
        // missing asset path was marked cached, counted as loaded, and reported
        // in the success line. Worse, `_cachedAssetPaths` is the filter at the
        // top of this method, so the bad path was then skipped on every future
        // call: one failed load meant the asset could never be retried, and
        // `getCacheStats` reported a cache that was partly fictional.
        final results = await Future.wait(
          batch.map(_preloadSingleAsset).toList(),
          eagerError: false,
        );

        for (int i = 0; i < batch.length; i++) {
          if (results[i]) {
            _cachedAssetPaths.add(batch[i]);
            loadedCount++;
          } else {
            _failedAssetPaths.add(batch[i]);
            failedCount++;
          }
        }

        onProgress?.call(loadedCount, uncachedPaths.length);

        // Small delay between batches
        if (batchIndex < batches.length - 1) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      if (kDebugMode) {
        print('[GameAssetCache] Cached $loadedCount assets successfully'
            '${failedCount > 0 ? ', $failedCount failed' : ''}');
      }
    } finally {
      _isCaching = false;
    }
  }

  /// Preload a single asset. Returns whether it actually loaded — the caller
  /// needs that to decide what to record, and a `Future<void>` that swallows
  /// failures gives it no way to tell success from failure.
  Future<bool> _preloadSingleAsset(String assetPath) async {
    try {
      final imageProvider = AssetImage(assetPath);
      final binding = WidgetsBinding.instance;

      if (binding.rootElement != null) {
        await precacheImage(imageProvider, binding.rootElement!);
      } else {
        await rootBundle.load(assetPath);
      }
      return true;
    } catch (e) {
      // Still non-fatal — a missing asset must not abort a batch — but no
      // longer silent to the caller.
      if (kDebugMode) {
        print('[GameAssetCache] Failed to cache $assetPath: $e');
      }
      return false;
    }
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'totalCachedAssets': _cachedAssetPaths.length,
      'totalFailedAssets': _failedAssetPaths.length,
      'isCaching': _isCaching,
      'cachedPaths': _cachedAssetPaths.toList(),
      'failedPaths': _failedAssetPaths.toList(),
    };
  }

  /// Clear the cache
  void clearCache() {
    _cachedAssetPaths.clear();
    _failedAssetPaths.clear();
    if (kDebugMode) {
      print('[GameAssetCache] Cache cleared');
    }
  }

  /// Check if an asset is cached
  bool isAssetCached(String assetPath) => _cachedAssetPaths.contains(assetPath);
}
