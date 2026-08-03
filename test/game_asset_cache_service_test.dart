import 'package:flutter_game_performance_utils/flutter_game_performance_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// The defect: `cacheAssets` did `_cachedAssetPaths.addAll(batch)` after the
/// batch settled, while `_preloadSingleAsset` returned `Future<void>` and
/// swallowed every failure. A missing or typo'd asset was therefore recorded as
/// cached, counted in the success log, and — because `_cachedAssetPaths` is the
/// filter at the top of `cacheAssets` — skipped forever after, so it could
/// never be retried. `getCacheStats` reported a cache that was partly fiction.
///
/// These paths do not exist in this package's (empty) asset bundle, so
/// `rootBundle.load` throws and the failure path is the one under test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const missing = [
    'assets/images/does_not_exist_1.webp',
    'assets/images/does_not_exist_2.webp',
  ];

  test('a failed load is not recorded as cached', () async {
    final cache = GameAssetCacheService();
    await cache.cacheAssets(missing);

    for (final path in missing) {
      expect(cache.isAssetCached(path), isFalse,
          reason: '$path failed to load but was marked cached');
    }
  });

  test('failures are reported rather than silently absorbed', () async {
    final cache = GameAssetCacheService();
    await cache.cacheAssets(missing);

    expect(cache.failedAssetPaths, containsAll(missing));
    final stats = cache.getCacheStats();
    expect(stats['totalCachedAssets'], 0);
    expect(stats['totalFailedAssets'], missing.length);
  });

  test('progress never counts a failure as loaded', () async {
    final cache = GameAssetCacheService();
    final loadedReports = <int>[];
    await cache.cacheAssets(missing, onProgress: (loaded, _) {
      loadedReports.add(loaded);
    });

    // Every progress callback used to report the full batch size regardless of
    // outcome, which is how a loading bar reaches 100% on assets that failed.
    expect(loadedReports.every((n) => n == 0), isTrue,
        reason: 'progress reported $loadedReports for loads that all failed');
  });

  test('a failed asset stays eligible for a retry', () async {
    final cache = GameAssetCacheService();
    await cache.cacheAssets(missing);

    // Marking it cached meant the filter skipped it on every later call, so a
    // transient failure became permanent. It must still be attempted.
    var attempted = false;
    await cache.cacheAssets(missing, onProgress: (_, total) {
      attempted = total == missing.length;
    });
    expect(attempted, isTrue,
        reason: 'the failed paths were filtered out as already cached');
  });

  test('clearing the cache clears failures too', () async {
    final cache = GameAssetCacheService();
    await cache.cacheAssets(missing);
    expect(cache.failedAssetPaths, isNotEmpty);

    cache.clearCache();
    expect(cache.failedAssetPaths, isEmpty);
    expect(cache.getCacheStats()['totalFailedAssets'], 0);
  });

  test('an empty list is a no-op, not an error', () async {
    final cache = GameAssetCacheService();
    await cache.cacheAssets(<String>[]);
    expect(cache.getCacheStats()['totalCachedAssets'], 0);
    expect(cache.failedAssetPaths, isEmpty);
  });
}
