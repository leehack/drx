import 'dart:io';
import 'dart:convert';

import 'package:drx/src/cache_paths.dart';
import 'package:drx/src/engine.dart';
import 'package:drx/src/github_api.dart';
import 'package:drx/src/github_runner.dart';
import 'package:drx/src/platform_info.dart';
import 'package:drx/src/pub_runner.dart';
import 'package:test/test.dart';

import 'test_fakes.dart';

void main() {
  group('DrxEngine', () {
    test('returns zero for help and version', () async {
      final temp = await Directory.systemTemp.createTemp('drx_engine_test_');
      addTearDown(() => temp.delete(recursive: true));

      final engine = DrxEngine(
        paths: DrxPaths(temp),
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
      );

      expect(await engine.run(['--help']), 0);
      expect(await engine.run(['--version']), 0);
      expect(await engine.run([]), 0);
    });

    test('supports cache list and clean commands', () async {
      final temp = await Directory.systemTemp.createTemp('drx_engine_test_');
      addTearDown(() => temp.delete(recursive: true));

      final engine = DrxEngine(
        paths: DrxPaths(temp),
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
      );

      expect(await engine.run(['cache', 'list']), 0);
      expect(await engine.run(['--json', 'cache', 'list']), 0);
      expect(await engine.run(['cache', '--json', 'list']), 0);
      expect(await engine.run(['--verbose', 'cache', 'list']), 0);
      expect(
        await engine.run([
          'cache',
          'prune',
          '--max-age-days',
          '0',
          '--max-size-mb',
          '0',
        ]),
        0,
      );
      expect(await engine.run(['cache', 'clean']), 0);
      expect(await engine.run(['cache']), 0);
      expect(await engine.run(['cache', 'unknown']), 64);
    });

    test('supports versions command for pub and gh', () async {
      final temp = await Directory.systemTemp.createTemp('drx_engine_test_');
      addTearDown(() => temp.delete(recursive: true));

      final fetcher = FakeByteFetcher({
        'https://pub.dev/api/packages/melos': utf8.encode(
          jsonEncode({
            'versions': [
              {'version': '1.0.0'},
              {'version': '2.0.0'},
            ],
          }),
        ),
      });

      final engine = DrxEngine(
        paths: DrxPaths(temp),
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
        fetcher: fetcher,
        gitHubApi: FakeGitHubApi(releaseTagList: const ['v2.0.0', 'v1.0.0']),
      );

      expect(await engine.run(['versions', 'melos', '--limit', '1']), 0);
      expect(await engine.run(['versions', '--json', 'melos']), 0);
      expect(await engine.run(['--json', 'versions', 'melos']), 0);
      expect(await engine.run(['--verbose', 'versions', 'melos']), 0);
      expect(await engine.run(['versions', 'gh:cli/cli']), 0);
      expect(await engine.run(['versions']), 64);
    });

    test('returns parse error code for invalid options', () async {
      final temp = await Directory.systemTemp.createTemp('drx_engine_test_');
      addTearDown(() => temp.delete(recursive: true));

      final engine = DrxEngine(
        paths: DrxPaths(temp),
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
      );

      final code = await engine.run(['--not-a-real-flag']);
      expect(code, 64);
    });

    test('returns runner error code without throwing stacktrace', () async {
      final temp = await Directory.systemTemp.createTemp('drx_engine_test_');
      addTearDown(() => temp.delete(recursive: true));

      final fakeExec = FakeProcessExecutor(
        handler: (exe, args, {workingDirectory, runInShell = false}) {
          if (exe == 'dart' && args.isNotEmpty && args[0] == 'pub') {
            return 1;
          }
          return 0;
        },
      );

      final pubRunner = PubRunner(
        paths: DrxPaths(temp),
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
        processExecutor: fakeExec,
      );

      final ghRunner = GitHubRunner(
        paths: DrxPaths(temp),
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
        processExecutor: fakeExec,
        api: FakeGitHubApi(
          latest: const GitHubRelease(tag: 'v0', assets: []),
        ),
        fetcher: FakeByteFetcher(const {}),
      );

      final engine = DrxEngine(
        paths: DrxPaths(temp),
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
        processExecutor: fakeExec,
        pubRunner: pubRunner,
        ghRunner: ghRunner,
      );

      final code = await engine.run(['pub:mcp_dart']);
      expect(code, 1);
    });

    test('routes pub source to pub runner', () async {
      final temp = await Directory.systemTemp.createTemp('drx_engine_test_');
      addTearDown(() => temp.delete(recursive: true));

      final fakeExec = FakeProcessExecutor(
        handler: (exe, args, {workingDirectory, runInShell = false}) {
          if (exe == 'dart' && args.isNotEmpty && args[0] == 'pub') {
            return 0;
          }
          if (exe == 'dart' && args.isNotEmpty && args[0] == 'run') {
            return 0;
          }
          return 1;
        },
      );

      final pubRunner = PubRunner(
        paths: DrxPaths(temp),
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
        processExecutor: fakeExec,
      );

      final ghRunner = GitHubRunner(
        paths: DrxPaths(temp),
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
        processExecutor: fakeExec,
        api: FakeGitHubApi(
          latest: const GitHubRelease(tag: 'v0', assets: []),
        ),
        fetcher: FakeByteFetcher(const {}),
      );

      final engine = DrxEngine(
        paths: DrxPaths(temp),
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
        processExecutor: fakeExec,
        pubRunner: pubRunner,
        ghRunner: ghRunner,
      );

      final code = await engine.run([
        '--runtime',
        'jit',
        'melos',
        '--',
        '--version',
      ]);
      expect(code, 0);
    });
  });
}
