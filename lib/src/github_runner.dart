import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'cache_paths.dart';
import 'checksum.dart';
import 'errors.dart';
import 'github_api.dart';
import 'lock.dart';
import 'models.dart';
import 'platform_info.dart';
import 'process_executor.dart';

/// Executes tools from GitHub release assets.
final class GitHubRunner {
  GitHubRunner({
    required this.paths,
    required this.platform,
    required this.processExecutor,
    required this.api,
    required this.fetcher,
  });

  final DrxPaths paths;
  final HostPlatform platform;
  final ProcessExecutor processExecutor;
  final GitHubApi api;
  final ByteFetcher fetcher;

  /// Resolves, verifies, and runs a command from a GitHub release.
  Future<int> execute(CommandRequest request) async {
    final ownerRepo = request.source.identifier.split('/');
    if (ownerRepo.length != 2) {
      throw DrxException(
        'Invalid GitHub repository: ${request.source.identifier}.',
      );
    }
    final owner = ownerRepo[0];
    final repo = ownerRepo[1];

    _log(
      request.verbose,
      'source=gh repo=$owner/$repo tag=${request.source.version ?? 'latest'} command=${request.command}',
    );

    final release = request.source.version == null
        ? await api.latestRelease(owner, repo)
        : await api.releaseByTag(owner, repo, request.source.version!);
    final asset = _selectAsset(release, request.command, request.asset);
    _log(
      request.verbose,
      'selected release=${release.tag} asset=${asset.name}',
    );

    final lock = paths.lockFileFor(
      'gh:$owner/$repo:${release.tag}:${asset.name}:${platform.os}:${platform.arch}',
    );
    return withFileLock(lock, () async {
      final installDir = request.isolated
          ? await Directory.systemTemp.createTemp('drx_gh_')
          : paths.ghAssetDir(owner, repo, release.tag, asset.name, platform);

      if (request.refresh && await installDir.exists() && !request.isolated) {
        _log(request.verbose, 'refresh requested, clearing ${installDir.path}');
        await installDir.delete(recursive: true);
      }
      await installDir.create(recursive: true);

      try {
        final rawAssetFile = File(p.join(installDir.path, asset.name));
        final assetBytes = await _downloadIfNeeded(
          uri: Uri.parse(asset.downloadUrl),
          target: rawAssetFile,
          refresh: request.refresh,
        );
        _log(request.verbose, 'downloaded asset ${rawAssetFile.path}');

        await _verifyChecksum(
          release: release,
          asset: asset,
          assetBytes: assetBytes,
          allowUnsigned: request.allowUnsigned,
          verbose: request.verbose,
        );

        final extractDir = Directory(p.join(installDir.path, 'extract'));
        if (request.refresh && await extractDir.exists()) {
          await extractDir.delete(recursive: true);
        }
        await extractDir.create(recursive: true);
        final commandPath = await _prepareCommand(
          assetFile: rawAssetFile,
          command: request.command,
          extractDir: extractDir,
          refresh: request.refresh,
        );
        _log(request.verbose, 'executing $commandPath');

        return processExecutor.run(
          commandPath,
          request.args,
          runInShell: platform.isWindows && _isShellScript(commandPath),
        );
      } finally {
        if (request.isolated) {
          await installDir.delete(recursive: true);
        }
      }
    });
  }

  GitHubAsset _selectAsset(
    GitHubRelease release,
    String command,
    String? overrideName,
  ) {
    if (overrideName != null) {
      for (final asset in release.assets) {
        if (asset.name == overrideName) {
          return asset;
        }
      }
      throw DrxException(
        'Asset "$overrideName" was not found in release ${release.tag}.',
      );
    }

    final candidates = release.assets
        .where((asset) => !_looksLikeChecksum(asset.name))
        .toList(growable: false);
    if (candidates.isEmpty) {
      throw DrxException('No runnable assets found in release ${release.tag}.');
    }

    final scored = <({GitHubAsset asset, int score})>[];
    for (final asset in candidates) {
      final score = _scoreAsset(asset.name, command);
      scored.add((asset: asset, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    if (scored.first.score <= 0) {
      throw DrxException(
        'No compatible asset found for ${platform.os}/${platform.arch} in ${release.tag}.',
      );
    }
    return scored.first.asset;
  }

  int _scoreAsset(String name, String command) {
    final lower = name.toLowerCase();
    final osTokens = switch (platform.os) {
      'macos' => ['macos', 'darwin', 'apple-darwin', 'osx'],
      'linux' => ['linux', 'unknown-linux', 'gnu-linux'],
      'windows' => ['windows', 'win64', 'win32', 'pc-windows', 'msvc'],
      _ => <String>[],
    };
    final archTokens = switch (platform.arch) {
      'x64' => ['x64', 'x86_64', 'amd64'],
      'arm64' => ['arm64', 'aarch64'],
      _ => [platform.arch],
    };

    var score = 0;
    if (lower.contains(command.toLowerCase())) {
      score += 5;
    }
    if (osTokens.any(lower.contains)) {
      score += 10;
    }
    if (archTokens.any(lower.contains)) {
      score += 10;
    }
    if (_isArchive(name)) {
      score += 2;
    }
    if (lower.endsWith('.exe') && platform.isWindows) {
      score += 3;
    }
    return score;
  }

  Future<List<int>> _downloadIfNeeded({
    required Uri uri,
    required File target,
    required bool refresh,
  }) async {
    if (!refresh && await target.exists()) {
      return target.readAsBytes();
    }
    final bytes = await fetcher.fetch(uri);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
    return bytes;
  }

  Future<void> _verifyChecksum({
    required GitHubRelease release,
    required GitHubAsset asset,
    required List<int> assetBytes,
    required bool allowUnsigned,
    required bool verbose,
  }) async {
    final checksumAssets = release.assets
        .where((candidate) => _looksLikeChecksum(candidate.name))
        .toList(growable: false);

    if (checksumAssets.isEmpty) {
      if (allowUnsigned) {
        _log(
          verbose,
          'running unsigned asset because --allow-unsigned was set',
        );
        return;
      }
      throw const DrxException(
        'Release asset is unsigned. Use --allow-unsigned to bypass.',
      );
    }

    final targetName = p.basename(asset.name);
    for (final checksumAsset in checksumAssets) {
      final checksumBytes = await fetcher.fetch(
        Uri.parse(checksumAsset.downloadUrl),
      );
      final checksums = parseChecksumManifest(utf8.decode(checksumBytes));
      final hasEntry =
          checksums.containsKey(asset.name) ||
          checksums.containsKey(targetName);
      if (!hasEntry) {
        continue;
      }

      final ok = verifyAssetChecksum(
        assetName: asset.name,
        bytes: assetBytes,
        checksums: checksums,
      );
      if (ok) {
        _log(verbose, 'checksum verified via ${checksumAsset.name}');
        return;
      }
      throw DrxException('Checksum verification failed for ${asset.name}.');
    }

    throw DrxException(
      'No checksum entry found for ${asset.name} in release ${release.tag}.',
    );
  }

  Future<String> _prepareCommand({
    required File assetFile,
    required String command,
    required Directory extractDir,
    required bool refresh,
  }) async {
    if (_isArchive(assetFile.path)) {
      final marker = File(p.join(extractDir.path, '.extracted'));
      if (refresh || !await marker.exists()) {
        await _extractArchive(assetFile, extractDir);
        await marker.writeAsString('ok');
      }

      final found = await _findCommand(extractDir, command);
      if (found == null) {
        throw DrxException(
          'Command "$command" not found in archive ${assetFile.path}.',
        );
      }
      return found;
    }

    final target = File(p.join(extractDir.path, p.basename(assetFile.path)));
    if (refresh || !await target.exists()) {
      await target.writeAsBytes(await assetFile.readAsBytes(), flush: true);
    }

    if (!platform.isWindows) {
      await _chmodExecutable(target.path);
    }

    if (_matchesCommand(target.path, command)) {
      return target.path;
    }

    throw DrxException(
      'Asset ${assetFile.path} does not provide "$command". Use --asset to select another file.',
    );
  }

  Future<void> _extractArchive(File archiveFile, Directory outputDir) async {
    final bytes = await archiveFile.readAsBytes();
    Archive archive;
    final lower = archiveFile.path.toLowerCase();
    if (lower.endsWith('.zip')) {
      archive = ZipDecoder().decodeBytes(bytes);
    } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
      final tarBytes = GZipDecoder().decodeBytes(bytes);
      archive = TarDecoder().decodeBytes(tarBytes);
    } else {
      throw DrxException('Unsupported archive format: ${archiveFile.path}.');
    }

    final outputRoot = p.normalize(outputDir.path);
    for (final item in archive) {
      final name = item.name;
      final outputPath = p.normalize(p.join(outputRoot, name));
      if (!p.isWithin(outputRoot, outputPath) && outputPath != outputRoot) {
        throw const DrxException(
          'Archive contains invalid path traversal entry.',
        );
      }

      if (item.isDirectory) {
        await Directory(outputPath).create(recursive: true);
        continue;
      }

      final content = item.readBytes();
      if (content == null) {
        throw DrxException('Archive entry "$name" has no readable content.');
      }
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(content, flush: true);
      if (!platform.isWindows) {
        await _chmodExecutable(file.path);
      }
    }
  }

  Future<String?> _findCommand(Directory root, String command) async {
    final candidates = platform.isWindows
        ? <String>[command, '$command.exe', '$command.cmd', '$command.bat']
        : <String>[command];

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final base = p.basename(entity.path).toLowerCase();
      if (candidates.any((candidate) => candidate.toLowerCase() == base)) {
        return entity.path;
      }
    }
    return null;
  }

  bool _looksLikeChecksum(String name) {
    final lower = name.toLowerCase();
    return lower.contains('sha256') ||
        lower.contains('checksum') ||
        lower == 'sha256sums' ||
        lower.endsWith('.sha256') ||
        lower.endsWith('.sha256sum') ||
        lower.endsWith('.txt') && lower.contains('sums');
  }

  bool _matchesCommand(String filePath, String command) {
    final base = p.basename(filePath).toLowerCase();
    final target = command.toLowerCase();
    if (base == target) {
      return true;
    }
    if (platform.isWindows &&
        (base == '$target.exe' ||
            base == '$target.cmd' ||
            base == '$target.bat')) {
      return true;
    }
    return false;
  }

  bool _isArchive(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.zip') ||
        lower.endsWith('.tar.gz') ||
        lower.endsWith('.tgz');
  }

  bool _isShellScript(String filePath) {
    final lower = filePath.toLowerCase();
    return lower.endsWith('.cmd') || lower.endsWith('.bat');
  }

  void _log(bool enabled, String message) {
    if (!enabled) {
      return;
    }
    stderr.writeln('[drx:gh] $message');
  }

  Future<void> _chmodExecutable(String filePath) async {
    await Process.run('chmod', ['+x', filePath]);
  }
}
