import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Service for intelligently caching game assets (images) with batched preloading
///
/// Perfect for card games, board games, or any app with many visual assets.
/// Provides memory-efficient batched loading with progress tracking.
class GameAssetCacheService {
  final Set<String> _cachedAssetPaths = {};
  bool _isCaching = false;

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
        print('[GameAssetCache] Caching ${uncachedPaths.length} assets in batches of ${batchSize}');
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
      for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        final batch = batches[batchIndex];

        await Future.wait(
          batch.map((path) => _preloadSingleAsset(path)).toList(),
          eagerError: false,
        );

        _cachedAssetPaths.addAll(batch);
        loadedCount += batch.length;

        onProgress?.call(loadedCount, uncachedPaths.length);

        // Small delay between batches
        if (batchIndex < batches.length - 1) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      if (kDebugMode) {
        print('[GameAssetCache] Cached ${loadedCount} assets successfully');
      }
    } finally {
      _isCaching = false;
    }
  }

  /// Preload a single asset
  Future<void> _preloadSingleAsset(String assetPath) async {
    try {
      final imageProvider = AssetImage(assetPath);
      final binding = WidgetsBinding.instance;
      
      if (binding.rootElement != null) {
        await precacheImage(imageProvider, binding.rootElement!);
      } else {
        await rootBundle.load(assetPath);
      }
    } catch (e) {
      // Asset might not exist, skip silently
      if (kDebugMode) {
        print('[GameAssetCache] Failed to cache $assetPath: $e');
      }
    }
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'totalCachedAssets': _cachedAssetPaths.length,
      'isCaching': _isCaching,
      'cachedPaths': _cachedAssetPaths.toList(),
    };
  }

  /// Clear the cache
  void clearCache() {
    _cachedAssetPaths.clear();
    if (kDebugMode) {
      print('[GameAssetCache] Cache cleared');
    }
  }

  /// Check if an asset is cached
  bool isAssetCached(String assetPath) => _cachedAssetPaths.contains(assetPath);
}
