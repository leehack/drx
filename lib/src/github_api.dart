import 'dart:convert';
import 'dart:io';

import 'errors.dart';

/// GitHub release asset metadata required by the runner.
final class GitHubAsset {
  const GitHubAsset({required this.name, required this.downloadUrl});

  final String name;
  final String downloadUrl;
}

/// GitHub release metadata used by drx.
final class GitHubRelease {
  const GitHubRelease({required this.tag, required this.assets});

  final String tag;
  final List<GitHubAsset> assets;
}

/// GitHub API surface used by the GH source runner.
abstract interface class GitHubApi {
  Future<GitHubRelease> latestRelease(String owner, String repo);
  Future<GitHubRelease> releaseByTag(String owner, String repo, String tag);
  Future<List<String>> releaseTags(String owner, String repo, {int limit});
  Future<List<String>> repositoryTags(String owner, String repo, {int limit});
}

/// Fetches a URL and returns raw response bytes.
abstract interface class ByteFetcher {
  Future<List<int>> fetch(Uri uri);
}

/// Byte fetcher backed by [HttpClient].
final class HttpByteFetcher implements ByteFetcher {
  const HttpByteFetcher({HttpClient? client}) : _client = client;

  final HttpClient? _client;

  @override
  Future<List<int>> fetch(Uri uri) async {
    final client = _client ?? HttpClient();
    final ownsClient = _client == null;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'drx/0.1');
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DrxException(
          'Failed to fetch ${uri.toString()} (${response.statusCode}).',
        );
      }
      return bytes;
    } finally {
      if (ownsClient) {
        client.close(force: true);
      }
    }
  }
}

/// GitHub REST API client used by drx.
final class HttpGitHubApi implements GitHubApi {
  HttpGitHubApi({ByteFetcher? fetcher})
    : _fetcher = fetcher ?? const HttpByteFetcher();

  final ByteFetcher _fetcher;

  @override
  Future<GitHubRelease> latestRelease(String owner, String repo) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases/latest',
    );
    return _decodeRelease(await _fetcher.fetch(uri));
  }

  @override
  Future<GitHubRelease> releaseByTag(
    String owner,
    String repo,
    String tag,
  ) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases/tags/$tag',
    );
    return _decodeRelease(await _fetcher.fetch(uri));
  }

  @override
  Future<List<String>> releaseTags(
    String owner,
    String repo, {
    int limit = 20,
  }) async {
    final perPage = limit <= 0 ? 100 : limit;
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases?per_page=$perPage',
    );
    final decoded = jsonDecode(utf8.decode(await _fetcher.fetch(uri)));
    if (decoded is! List) {
      throw const DrxException('GitHub release list response is invalid JSON.');
    }

    final tags = <String>[];
    for (final node in decoded) {
      if (node is! Map<String, dynamic>) {
        continue;
      }
      final tag = node['tag_name'];
      if (tag is String && tag.isNotEmpty) {
        tags.add(tag);
      }
    }
    return tags;
  }

  @override
  Future<List<String>> repositoryTags(
    String owner,
    String repo, {
    int limit = 20,
  }) async {
    final perPage = limit <= 0 ? 100 : limit;
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/tags?per_page=$perPage',
    );
    final decoded = jsonDecode(utf8.decode(await _fetcher.fetch(uri)));
    if (decoded is! List) {
      throw const DrxException('GitHub tag list response is invalid JSON.');
    }

    final tags = <String>[];
    for (final node in decoded) {
      if (node is! Map<String, dynamic>) {
        continue;
      }
      final name = node['name'];
      if (name is String && name.isNotEmpty) {
        tags.add(name);
      }
    }
    return tags;
  }

  GitHubRelease _decodeRelease(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const DrxException('GitHub release response is invalid JSON.');
    }

    final tag = decoded['tag_name'];
    final assetsNode = decoded['assets'];
    if (tag is! String || assetsNode is! List) {
      throw const DrxException('GitHub release payload is missing fields.');
    }

    final assets = <GitHubAsset>[];
    for (final asset in assetsNode) {
      if (asset is! Map<String, dynamic>) {
        continue;
      }
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is String && url is String) {
        assets.add(GitHubAsset(name: name, downloadUrl: url));
      }
    }

    return GitHubRelease(tag: tag, assets: assets);
  }
}
