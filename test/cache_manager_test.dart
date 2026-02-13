import 'dart:io';

import 'package:drx/src/cache_manager.dart';
import 'package:drx/src/cache_paths.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('CacheManager', () {
    test('summarizes cache entries and can clean all', () async {
      final temp = await Directory.systemTemp.createTemp('drx_cache_mgr_test_');
      addTearDown(() => temp.delete(recursive: true));

      final paths = DrxPaths(temp);
      await paths.ensureBaseDirectories();

      final pubEntry = Directory(
        p.join(paths.cacheDirectory.path, 'pub', 'one'),
      );
      final pubAotEntry = Directory(
        p.join(paths.cacheDirectory.path, 'pub-aot', 'two'),
      );
      final ghEntry = Directory(
        p.join(paths.cacheDirectory.path, 'gh', 'three'),
      );

      await pubEntry.create(recursive: true);
      await pubAotEntry.create(recursive: true);
      await ghEntry.create(recursive: true);

      await File(p.join(pubEntry.path, 'a.txt')).writeAsString('a');
      await File(p.join(pubAotEntry.path, 'b.txt')).writeAsString('bb');
      await File(p.join(ghEntry.path, 'c.txt')).writeAsString('ccc');

      final manager = CacheManager(paths);
      final summary = await manager.summarize();
      expect(summary.pubEntries, 1);
      expect(summary.pubAotEntries, 1);
      expect(summary.ghEntries, 1);
      expect(summary.totalBytes, greaterThan(0));

      await manager.cleanAll();
      final after = await manager.summarize();
      expect(after.pubEntries, 0);
      expect(after.pubAotEntries, 0);
      expect(after.ghEntries, 0);
      expect(after.totalBytes, 0);
    });

    test('prunes by age and by max size', () async {
      final temp = await Directory.systemTemp.createTemp('drx_cache_mgr_test_');
      addTearDown(() => temp.delete(recursive: true));

      final paths = DrxPaths(temp);
      await paths.ensureBaseDirectories();
      final manager = CacheManager(paths);

      final ageEntry = Directory(
        p.join(paths.cacheDirectory.path, 'pub', 'age'),
      );
      await ageEntry.create(recursive: true);
      await File(
        p.join(ageEntry.path, 'age.bin'),
      ).writeAsBytes(List<int>.filled(512, 1));

      final agePruned = await manager.prune(maxAge: Duration.zero);
      expect(agePruned.removedEntries, 1);
      expect(await ageEntry.exists(), isFalse);

      final sizeEntryA = Directory(
        p.join(paths.cacheDirectory.path, 'gh', 'size-a'),
      );
      final sizeEntryB = Directory(
        p.join(paths.cacheDirectory.path, 'pub-aot', 'size-b'),
      );
      await sizeEntryA.create(recursive: true);
      await sizeEntryB.create(recursive: true);
      await File(
        p.join(sizeEntryA.path, 'a.bin'),
      ).writeAsBytes(List<int>.filled(2048, 2));
      await File(
        p.join(sizeEntryB.path, 'b.bin'),
      ).writeAsBytes(List<int>.filled(2048, 3));

      final sizePruned = await manager.prune(maxTotalBytes: 1024);
      expect(sizePruned.removedEntries, greaterThanOrEqualTo(1));
      expect(sizePruned.remainingBytes, lessThanOrEqualTo(1024));
    });
  });
}
