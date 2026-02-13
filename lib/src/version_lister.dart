import 'dart:convert';

import 'errors.dart';
import 'github_api.dart';

/// Lists available versions from pub.dev or GitHub releases.
final class VersionLister {
  VersionLister({required ByteFetcher fetcher, required GitHubApi gitHubApi})
    : _fetcher = fetcher,
      _gitHubApi = gitHubApi;

  final ByteFetcher _fetcher;
  final GitHubApi _gitHubApi;

  /// Returns available versions for [target].
  ///
  /// Target forms:
  /// - `package`
  /// - `package:executable`
  /// - `pub:package`
  /// - `gh:owner/repo`
  Future<List<String>> listVersions(String target, {int limit = 20}) async {
    if (target.startsWith('gh:')) {
      return _listGhVersions(target, limit: limit);
    }
    return _listPubVersions(target, limit: limit);
  }

  Future<List<String>> _listPubVersions(
    String target, {
    required int limit,
  }) async {
    final packageName = _parsePubPackageName(target);
    final uri = Uri.parse('https://pub.dev/api/packages/$packageName');
    final decoded = jsonDecode(utf8.decode(await _fetcher.fetch(uri)));
    if (decoded is! Map<String, dynamic>) {
      throw DrxException(
        'Invalid pub.dev response for package "$packageName".',
      );
    }

    final versionsNode = decoded['versions'];
    if (versionsNode is! List) {
      throw DrxException(
        'pub.dev response for "$packageName" has no versions.',
      );
    }

    final versions = <String>[];
    for (final node in versionsNode) {
      if (node is! Map<String, dynamic>) {
        continue;
      }
      final value = node['version'];
      if (value is String && value.isNotEmpty) {
        versions.add(value);
      }
    }

    if (versions.isEmpty) {
      throw DrxException('No versions found on pub.dev for "$packageName".');
    }

    final newestFirst = versions.reversed.toList(growable: false);
    if (limit <= 0 || newestFirst.length <= limit) {
      return newestFirst;
    }
    return newestFirst.sublist(0, limit);
  }

  Future<List<String>> _listGhVersions(
    String target, {
    required int limit,
  }) async {
    var value = target.substring(3);
    final at = value.lastIndexOf('@');
    if (at > 0) {
      value = value.substring(0, at);
    }
    final parts = value.split('/');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      throw DrxException('Invalid gh target "$target". Use gh:<owner>/<repo>.');
    }

    final tags = await _gitHubApi.releaseTags(
      parts[0],
      parts[1],
      limit: limit <= 0 ? 100 : limit,
    );
    if (tags.isNotEmpty) {
      return tags;
    }

    final repositoryTags = await _gitHubApi.repositoryTags(
      parts[0],
      parts[1],
      limit: limit <= 0 ? 100 : limit,
    );
    if (repositoryTags.isNotEmpty) {
      return repositoryTags;
    }

    throw DrxException(
      'No GitHub releases or tags found for ${parts[0]}/${parts[1]}.',
    );
  }

  String _parsePubPackageName(String target) {
    var value = target;
    if (value.startsWith('pub:')) {
      value = value.substring(4);
    }

    final at = value.lastIndexOf('@');
    if (at > 0) {
      value = value.substring(0, at);
    }

    final colon = value.indexOf(':');
    if (colon > 0) {
      value = value.substring(0, colon);
    }

    if (value.isEmpty) {
      throw DrxException('Missing package name for versions lookup.');
    }
    return value;
  }
}
