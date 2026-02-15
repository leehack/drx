import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drx/src/cache_paths.dart';
import 'package:drx/src/checksum.dart';
import 'package:drx/src/errors.dart';
import 'package:drx/src/github_api.dart';
import 'package:drx/src/github_runner.dart';
import 'package:drx/src/models.dart';
import 'package:drx/src/platform_info.dart';
import 'package:test/test.dart';

import 'test_fakes.dart';

void main() {
  group('GitHubRunner', () {
    test('blocks unsigned assets by default', () async {
      final home = await Directory.systemTemp.createTemp('drx_gh_test_');
      addTearDown(() => home.delete(recursive: true));

      final release = GitHubRelease(
        tag: 'v1.0.0',
        assets: const [
          GitHubAsset(
            name: 'tool-windows-x64.exe',
            downloadUrl: 'https://example/tool.exe',
          ),
        ],
      );

      final runner = GitHubRunner(
        paths: DrxPaths(home),
        platform: const HostPlatform(os: 'windows', arch: 'x64'),
        processExecutor: FakeProcessExecutor(
          handler:
              (executable, arguments, {workingDirectory, runInShell = false}) =>
                  0,
        ),
        api: FakeGitHubApi(latest: release),
        fetcher: FakeByteFetcher({
          'https://example/tool.exe': [1, 2, 3],
        }),
      );

      expect(
        () => runner.execute(
          const CommandRequest(
            source: SourceSpec(type: SourceType.gh, identifier: 'org/repo'),
            command: 'tool',
            args: [],
            runtime: RuntimeMode.auto,
            refresh: false,
            isolated: false,
            allowUnsigned: false,
            verbose: false,
          ),
        ),
        throwsA(isA<DrxException>()),
      );
    });

    test('runs signed raw executable asset', () async {
      final home = await Directory.systemTemp.createTemp('drx_gh_test_');
      addTearDown(() => home.delete(recursive: true));

      const exeName = 'gh.exe';
      final exeBytes = utf8.encode('binary');
      final checksum = sha256Hex(exeBytes);

      final release = GitHubRelease(
        tag: 'v2.0.0',
        assets: const [
          GitHubAsset(name: exeName, downloadUrl: 'https://example/gh.exe'),
          GitHubAsset(
            name: 'SHA256SUMS',
            downloadUrl: 'https://example/SHA256SUMS',
          ),
        ],
      );

      final fakeExec = FakeProcessExecutor(
        handler: (exe, args, {workingDirectory, runInShell = false}) => 0,
      );
      final runner = GitHubRunner(
        paths: DrxPaths(home),
        platform: const HostPlatform(os: 'windows', arch: 'x64'),
        processExecutor: fakeExec,
        api: FakeGitHubApi(latest: release),
        fetcher: FakeByteFetcher({
          'https://example/gh.exe': exeBytes,
          'https://example/SHA256SUMS': utf8.encode('$checksum  $exeName\n'),
        }),
      );

      final code = await runner.execute(
        const CommandRequest(
          source: SourceSpec(type: SourceType.gh, identifier: 'cli/cli'),
          command: 'gh',
          args: ['--version'],
          runtime: RuntimeMode.auto,
          refresh: false,
          isolated: false,
          allowUnsigned: false,
          verbose: false,
        ),
      );

      expect(code, 0);
      expect(fakeExec.calls, hasLength(1));
      expect(fakeExec.calls.single.executable.toLowerCase(), endsWith('.exe'));
      expect(fakeExec.calls.single.arguments, ['--version']);
    });

    test('extracts zip asset and runs command', () async {
      final home = await Directory.systemTemp.createTemp('drx_gh_test_');
      addTearDown(() => home.delete(recursive: true));

      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'tool.exe',
            utf8.encode('dummy').length,
            utf8.encode('dummy'),
          ),
        );
      final zipBytes = ZipEncoder().encode(archive);
      final zipChecksum = sha256Hex(zipBytes);

      final release = GitHubRelease(
        tag: 'v1.2.3',
        assets: const [
          GitHubAsset(
            name: 'tool-windows-x64.zip',
            downloadUrl: 'https://example/tool.zip',
          ),
          GitHubAsset(
            name: 'checksums.txt',
            downloadUrl: 'https://example/checksums.txt',
          ),
        ],
      );

      final fakeExec = FakeProcessExecutor(
        handler: (exe, args, {workingDirectory, runInShell = false}) => 0,
      );

      final runner = GitHubRunner(
        paths: DrxPaths(home),
        platform: const HostPlatform(os: 'windows', arch: 'x64'),
        processExecutor: fakeExec,
        api: FakeGitHubApi(latest: release),
        fetcher: FakeByteFetcher({
          'https://example/tool.zip': zipBytes,
          'https://example/checksums.txt': utf8.encode(
            '${release.assets.first.name}: $zipChecksum\n',
          ),
        }),
      );

      final code = await runner.execute(
        const CommandRequest(
          source: SourceSpec(type: SourceType.gh, identifier: 'org/repo'),
          command: 'tool',
          args: ['arg1'],
          runtime: RuntimeMode.auto,
          refresh: false,
          isolated: false,
          allowUnsigned: false,
          verbose: false,
        ),
      );

      expect(code, 0);
      expect(fakeExec.calls.single.executable.toLowerCase(), endsWith('.exe'));
      expect(fakeExec.calls.single.arguments, ['arg1']);
    });

    test('allows unsigned when explicitly requested', () async {
      final home = await Directory.systemTemp.createTemp('drx_gh_test_');
      addTearDown(() => home.delete(recursive: true));

      final release = GitHubRelease(
        tag: 'v1.0.0',
        assets: const [
          GitHubAsset(
            name: 'tool-windows-x64.exe',
            downloadUrl: 'https://example/tool.exe',
          ),
        ],
      );
      final fakeExec = FakeProcessExecutor(
        handler: (exe, args, {workingDirectory, runInShell = false}) => 0,
      );

      final runner = GitHubRunner(
        paths: DrxPaths(home),
        platform: const HostPlatform(os: 'windows', arch: 'x64'),
        processExecutor: fakeExec,
        api: FakeGitHubApi(latest: release),
        fetcher: FakeByteFetcher({
          'https://example/tool.exe': [1, 2, 3],
        }),
      );

      final code = await runner.execute(
        const CommandRequest(
          source: SourceSpec(type: SourceType.gh, identifier: 'org/repo'),
          command: 'tool-windows-x64',
          args: [],
          runtime: RuntimeMode.auto,
          refresh: false,
          isolated: false,
          allowUnsigned: true,
          verbose: false,
        ),
      );

      expect(code, 0);
      expect(fakeExec.calls, hasLength(1));
    });

    test(
      'verifies checksum when matching entry is in later checksum file',
      () async {
        final home = await Directory.systemTemp.createTemp('drx_gh_test_');
        addTearDown(() => home.delete(recursive: true));

        const exeName = 'drx-windows-x64.exe';
        final exeBytes = utf8.encode('binary');
        final checksum = sha256Hex(exeBytes);

        final release = GitHubRelease(
          tag: 'v3.0.0',
          assets: const [
            GitHubAsset(name: exeName, downloadUrl: 'https://example/drx.exe'),
            GitHubAsset(
              name: 'linux.sha256',
              downloadUrl: 'https://example/linux.sha256',
            ),
            GitHubAsset(
              name: 'windows.sha256',
              downloadUrl: 'https://example/windows.sha256',
            ),
          ],
        );

        final fakeExec = FakeProcessExecutor(
          handler: (exe, args, {workingDirectory, runInShell = false}) => 0,
        );

        final runner = GitHubRunner(
          paths: DrxPaths(home),
          platform: const HostPlatform(os: 'windows', arch: 'x64'),
          processExecutor: fakeExec,
          api: FakeGitHubApi(latest: release),
          fetcher: FakeByteFetcher({
            'https://example/drx.exe': exeBytes,
            'https://example/linux.sha256': utf8.encode(
              '${sha256Hex(utf8.encode('nope'))}  drx-linux-x64\n',
            ),
            'https://example/windows.sha256': utf8.encode(
              '$checksum  $exeName\n',
            ),
          }),
        );

        final code = await runner.execute(
          const CommandRequest(
            source: SourceSpec(type: SourceType.gh, identifier: 'org/repo'),
            command: 'drx-windows-x64',
            args: ['--version'],
            runtime: RuntimeMode.auto,
            refresh: false,
            isolated: false,
            allowUnsigned: false,
            verbose: false,
          ),
        );

        expect(code, 0);
        expect(fakeExec.calls, hasLength(1));
      },
    );

    test('resolves and runs Dart executable in gh source mode', () async {
      final home = await Directory.systemTemp.createTemp('drx_gh_test_');
      addTearDown(() => home.delete(recursive: true));

      final fakeExec = FakeProcessExecutor(
        handler: (exe, args, {workingDirectory, runInShell = false}) async {
          if (exe == 'dart' && args.length >= 2 && args[0] == 'pub') {
            return 0;
          }
          if (exe == 'dart' && args.length >= 2 && args[0] == 'run') {
            expect(args[1], 'mcp_dart_cli:mcp_dart');
            expect(args.skip(2), ['--help']);
            return 0;
          }
          return 1;
        },
      );

      final runner = GitHubRunner(
        paths: DrxPaths(home),
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
        processExecutor: fakeExec,
        api: FakeGitHubApi(
          latest: const GitHubRelease(tag: 'v0', assets: []),
        ),
        fetcher: FakeByteFetcher(const {}),
      );

      final code = await runner.execute(
        const CommandRequest(
          source: SourceSpec(
            type: SourceType.gh,
            identifier: 'leehack/mcp_dart',
            version: 'mcp_dart_cli-v0.1.6',
          ),
          command: 'mcp_dart_cli:mcp_dart',
          args: ['--help'],
          runtime: RuntimeMode.auto,
          refresh: false,
          isolated: false,
          allowUnsigned: false,
          verbose: false,
          ghMode: GhMode.source,
          gitPath: 'packages/mcp_dart_cli',
        ),
      );

      expect(code, 0);
      expect(fakeExec.calls, hasLength(2));
      expect(fakeExec.calls.first.executable, 'dart');
      expect(fakeExec.calls.first.arguments, ['pub', 'get']);
      expect(fakeExec.calls.last.arguments, [
        'run',
        'mcp_dart_cli:mcp_dart',
        '--help',
      ]);
    });

    test(
      'auto gh mode falls back to source when binaries are unavailable',
      () async {
        final home = await Directory.systemTemp.createTemp('drx_gh_test_');
        addTearDown(() => home.delete(recursive: true));

        final fakeExec = FakeProcessExecutor(
          handler: (exe, args, {workingDirectory, runInShell = false}) async {
            if (exe == 'dart' && args.length >= 2 && args[0] == 'pub') {
              return 0;
            }
            if (exe == 'dart' && args.length >= 2 && args[0] == 'run') {
              expect(args[1], 'tool:tool');
              expect(args.skip(2), ['--version']);
              return 0;
            }
            return 1;
          },
        );

        final runner = GitHubRunner(
          paths: DrxPaths(home),
          platform: const HostPlatform(os: 'linux', arch: 'x64'),
          processExecutor: fakeExec,
          api: FakeGitHubApi(
            latest: const GitHubRelease(tag: 'v1.0.0', assets: []),
          ),
          fetcher: FakeByteFetcher({
            'https://raw.githubusercontent.com/org/repo/HEAD/pubspec.yaml': utf8
                .encode('name: tool\n'),
          }),
        );

        final code = await runner.execute(
          const CommandRequest(
            source: SourceSpec(type: SourceType.gh, identifier: 'org/repo'),
            command: 'tool',
            args: ['--version'],
            runtime: RuntimeMode.auto,
            refresh: false,
            isolated: false,
            allowUnsigned: false,
            verbose: false,
            ghMode: GhMode.auto,
          ),
        );

        expect(code, 0);
        expect(fakeExec.calls, hasLength(2));
        expect(fakeExec.calls.first.executable, 'dart');
        expect(fakeExec.calls.first.arguments, ['pub', 'get']);
        expect(fakeExec.calls.last.arguments, [
          'run',
          'tool:tool',
          '--version',
        ]);
      },
    );
  });
}
