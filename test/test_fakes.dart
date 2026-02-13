import 'dart:async';

import 'package:drx/src/github_api.dart';
import 'package:drx/src/process_executor.dart';

final class ProcessCall {
  const ProcessCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.runInShell,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final bool runInShell;
}

typedef ProcessHandler =
    FutureOr<int> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      bool runInShell,
    });

final class FakeProcessExecutor implements ProcessExecutor {
  FakeProcessExecutor({required this.handler});

  final ProcessHandler handler;
  final calls = <ProcessCall>[];

  @override
  Future<int> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) async {
    calls.add(
      ProcessCall(
        executable: executable,
        arguments: List<String>.from(arguments),
        workingDirectory: workingDirectory,
        runInShell: runInShell,
      ),
    );
    return handler(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
  }
}

final class FakeGitHubApi implements GitHubApi {
  FakeGitHubApi({
    this.latest,
    this.byTag,
    this.releaseTagList,
    this.repositoryTagList,
  });

  final GitHubRelease? latest;
  final Map<String, GitHubRelease>? byTag;
  final List<String>? releaseTagList;
  final List<String>? repositoryTagList;

  @override
  Future<GitHubRelease> latestRelease(String owner, String repo) async {
    if (latest == null) {
      throw StateError('latest release not configured');
    }
    return latest!;
  }

  @override
  Future<GitHubRelease> releaseByTag(
    String owner,
    String repo,
    String tag,
  ) async {
    final release = byTag?[tag];
    if (release == null) {
      throw StateError('tag release not configured for $tag');
    }
    return release;
  }

  @override
  Future<List<String>> releaseTags(
    String owner,
    String repo, {
    int limit = 20,
  }) async {
    if (releaseTagList == null) {
      throw StateError('release tags not configured');
    }
    if (limit <= 0 || releaseTagList!.length <= limit) {
      return releaseTagList!;
    }
    return releaseTagList!.sublist(0, limit);
  }

  @override
  Future<List<String>> repositoryTags(
    String owner,
    String repo, {
    int limit = 20,
  }) async {
    if (repositoryTagList == null) {
      throw StateError('repository tags not configured');
    }
    if (limit <= 0 || repositoryTagList!.length <= limit) {
      return repositoryTagList!;
    }
    return repositoryTagList!.sublist(0, limit);
  }
}

final class FakeByteFetcher implements ByteFetcher {
  FakeByteFetcher(this.payloadByUri);

  final Map<String, List<int>> payloadByUri;
  final requested = <String>[];

  @override
  Future<List<int>> fetch(Uri uri) async {
    requested.add(uri.toString());
    final payload = payloadByUri[uri.toString()];
    if (payload == null) {
      throw StateError('missing payload for ${uri.toString()}');
    }
    return payload;
  }
}
