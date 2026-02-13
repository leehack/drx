import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'platform_info.dart';

/// Resolves and builds drx cache and lock paths.
final class DrxPaths {
  DrxPaths(this.homeDirectory);

  final Directory homeDirectory;

  Directory get cacheDirectory =>
      Directory(p.join(homeDirectory.path, 'cache'));
  Directory get lockDirectory => Directory(p.join(homeDirectory.path, 'locks'));

  /// Resolves the drx home directory from environment and host defaults.
  static DrxPaths resolve({
    Map<String, String>? environment,
    HostPlatform? platform,
  }) {
    final env = environment ?? Platform.environment;
    final host = platform ?? HostPlatform.detect();
    final configured = env['DRX_HOME'];
    if (configured != null && configured.trim().isNotEmpty) {
      return DrxPaths(Directory(configured));
    }

    if (host.isWindows) {
      final appData = env['LOCALAPPDATA'];
      if (appData != null && appData.trim().isNotEmpty) {
        return DrxPaths(Directory(p.join(appData, 'drx')));
      }
    }

    final home = env['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      return DrxPaths(Directory(p.join(home, '.drx')));
    }

    return DrxPaths(Directory(p.join(Directory.systemTemp.path, 'drx')));
  }

  /// Cache location for pub dependency sandboxes.
  Directory pubSandboxDir(String package, String versionKey) {
    final key = stableKey(['pub', package, versionKey]);
    return Directory(p.join(cacheDirectory.path, 'pub', key, 'sandbox'));
  }

  /// Cache location for compiled AOT pub executables.
  Directory pubAotDir(
    String package,
    String versionKey,
    String command,
    HostPlatform platform,
    String sdkVersion,
  ) {
    final key = stableKey([
      'pub-aot',
      package,
      versionKey,
      command,
      platform.os,
      platform.arch,
      sdkVersion,
    ]);
    return Directory(p.join(cacheDirectory.path, 'pub-aot', key));
  }

  /// Cache location for downloaded GH release assets.
  Directory ghAssetDir(
    String owner,
    String repo,
    String tag,
    String assetName,
    HostPlatform platform,
  ) {
    final key = stableKey([
      'gh',
      owner,
      repo,
      tag,
      assetName,
      platform.os,
      platform.arch,
    ]);
    return Directory(p.join(cacheDirectory.path, 'gh', key));
  }

  /// Lock file path derived from a deterministic key.
  File lockFileFor(String key) {
    final hash = stableKey([key]);
    return File(p.join(lockDirectory.path, '$hash.lock'));
  }

  /// Creates a stable SHA-256 key from path components.
  String stableKey(List<String> parts) {
    final payload = parts.join('|');
    return sha256.convert(payload.codeUnits).toString();
  }

  /// Ensures base cache and lock directories exist.
  Future<void> ensureBaseDirectories() async {
    await cacheDirectory.create(recursive: true);
    await lockDirectory.create(recursive: true);
  }
}
