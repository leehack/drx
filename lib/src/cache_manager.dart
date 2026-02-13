import 'dart:io';

import 'package:path/path.dart' as p;

import 'cache_paths.dart';

final class _CacheEntry {
  const _CacheEntry({
    required this.source,
    required this.path,
    required this.modified,
    required this.sizeBytes,
  });

  final String source;
  final String path;
  final DateTime modified;
  final int sizeBytes;
}

/// Snapshot of drx cache state.
final class CacheSummary {
  const CacheSummary({
    required this.pubEntries,
    required this.pubAotEntries,
    required this.ghEntries,
    required this.totalBytes,
  });

  final int pubEntries;
  final int pubAotEntries;
  final int ghEntries;
  final int totalBytes;
}

/// Summary returned after pruning cache entries.
final class CachePruneSummary {
  const CachePruneSummary({
    required this.removedEntries,
    required this.removedBytes,
    required this.remainingEntries,
    required this.remainingBytes,
  });

  final int removedEntries;
  final int removedBytes;
  final int remainingEntries;
  final int remainingBytes;
}

/// Utility for listing and cleaning local drx caches.
final class CacheManager {
  CacheManager(this.paths);

  final DrxPaths paths;

  /// Deletes cache and lock directories, then recreates them.
  Future<void> cleanAll() async {
    if (await paths.cacheDirectory.exists()) {
      await paths.cacheDirectory.delete(recursive: true);
    }
    if (await paths.lockDirectory.exists()) {
      await paths.lockDirectory.delete(recursive: true);
    }
    await paths.ensureBaseDirectories();
  }

  /// Reads current cache entry counts and total size.
  Future<CacheSummary> summarize() async {
    final pubEntries = await _countHashedEntries(
      Directory(p.join(paths.cacheDirectory.path, 'pub')),
    );
    final pubAotEntries = await _countHashedEntries(
      Directory(p.join(paths.cacheDirectory.path, 'pub-aot')),
    );
    final ghEntries = await _countHashedEntries(
      Directory(p.join(paths.cacheDirectory.path, 'gh')),
    );
    final totalBytes = await _directorySize(paths.cacheDirectory);

    return CacheSummary(
      pubEntries: pubEntries,
      pubAotEntries: pubAotEntries,
      ghEntries: ghEntries,
      totalBytes: totalBytes,
    );
  }

  /// Prunes cache entries by age, and optionally enforces a max total size.
  Future<CachePruneSummary> prune({
    Duration? maxAge,
    int? maxTotalBytes,
  }) async {
    final entries = await _listEntries();
    var removedEntries = 0;
    var removedBytes = 0;

    final kept = <_CacheEntry>[];
    final now = DateTime.now();
    for (final entry in entries) {
      final expired = maxAge != null && now.difference(entry.modified) > maxAge;
      if (expired) {
        await Directory(entry.path).delete(recursive: true);
        removedEntries++;
        removedBytes += entry.sizeBytes;
      } else {
        kept.add(entry);
      }
    }

    if (maxTotalBytes != null && maxTotalBytes >= 0) {
      kept.sort((a, b) => a.modified.compareTo(b.modified));
      var total = kept.fold<int>(0, (sum, entry) => sum + entry.sizeBytes);
      final stillKept = <_CacheEntry>[];
      for (final entry in kept) {
        if (total > maxTotalBytes) {
          await Directory(entry.path).delete(recursive: true);
          removedEntries++;
          removedBytes += entry.sizeBytes;
          total -= entry.sizeBytes;
        } else {
          stillKept.add(entry);
        }
      }
      kept
        ..clear()
        ..addAll(stillKept);
    }

    final remainingEntries = kept.length;
    final remainingBytes = kept.fold<int>(
      0,
      (sum, entry) => sum + entry.sizeBytes,
    );

    return CachePruneSummary(
      removedEntries: removedEntries,
      removedBytes: removedBytes,
      remainingEntries: remainingEntries,
      remainingBytes: remainingBytes,
    );
  }

  Future<List<_CacheEntry>> _listEntries() async {
    final entries = <_CacheEntry>[];
    entries.addAll(
      await _entriesFromSource(
        source: 'pub',
        directory: Directory(p.join(paths.cacheDirectory.path, 'pub')),
      ),
    );
    entries.addAll(
      await _entriesFromSource(
        source: 'pub-aot',
        directory: Directory(p.join(paths.cacheDirectory.path, 'pub-aot')),
      ),
    );
    entries.addAll(
      await _entriesFromSource(
        source: 'gh',
        directory: Directory(p.join(paths.cacheDirectory.path, 'gh')),
      ),
    );
    return entries;
  }

  Future<List<_CacheEntry>> _entriesFromSource({
    required String source,
    required Directory directory,
  }) async {
    if (!await directory.exists()) {
      return const [];
    }

    final entries = <_CacheEntry>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! Directory) {
        continue;
      }
      final stat = await entry.stat();
      final size = await _directorySize(entry);
      final modified = await _entryModified(entry, fallback: stat.modified);
      entries.add(
        _CacheEntry(
          source: source,
          path: entry.path,
          modified: modified,
          sizeBytes: size,
        ),
      );
    }
    return entries;
  }

  Future<DateTime> _entryModified(
    Directory entry, {
    required DateTime fallback,
  }) async {
    var latest = fallback;
    await for (final node in entry.list(recursive: true, followLinks: false)) {
      if (node is! File) {
        continue;
      }
      final modified = (await node.stat()).modified;
      if (modified.isAfter(latest)) {
        latest = modified;
      }
    }
    return latest;
  }

  Future<int> _countHashedEntries(Directory directory) async {
    if (!await directory.exists()) {
      return 0;
    }

    var count = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is Directory) {
        count++;
      }
    }
    return count;
  }

  Future<int> _directorySize(Directory directory) async {
    if (!await directory.exists()) {
      return 0;
    }

    var total = 0;
    await for (final entry in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is! File) {
        continue;
      }
      total += await entry.length();
    }
    return total;
  }
}
