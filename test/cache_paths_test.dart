import 'dart:io';

import 'package:drx/src/cache_paths.dart';
import 'package:drx/src/platform_info.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('DrxPaths', () {
    test('uses DRX_HOME override when present', () {
      final paths = DrxPaths.resolve(
        environment: {'DRX_HOME': '/tmp/custom-drx'},
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
      );
      expect(paths.homeDirectory.path, '/tmp/custom-drx');
    });

    test('uses LOCALAPPDATA on windows', () {
      final paths = DrxPaths.resolve(
        environment: {'LOCALAPPDATA': r'C:\Users\foo\AppData\Local'},
        platform: const HostPlatform(os: 'windows', arch: 'x64'),
      );
      expect(paths.homeDirectory.path, contains('drx'));
    });

    test('uses HOME on unix-like systems', () {
      final paths = DrxPaths.resolve(
        environment: {'HOME': '/home/example'},
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
      );
      expect(paths.homeDirectory.path, p.join('/home/example', '.drx'));
    });

    test('builds deterministic keys', () {
      final paths = DrxPaths(Directory.systemTemp);
      final first = paths.stableKey(['a', 'b', 'c']);
      final second = paths.stableKey(['a', 'b', 'c']);
      final third = paths.stableKey(['a', 'c', 'b']);

      expect(first, second);
      expect(first, isNot(third));
      expect(first.length, 64);
    });
  });
}
