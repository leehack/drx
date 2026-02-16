import 'dart:convert';
import 'dart:io';

import 'package:drx/src/cache_paths.dart';
import 'package:drx/src/checksum.dart';
import 'package:drx/src/engine.dart';
import 'package:drx/src/github_api.dart';
import 'package:drx/src/platform_info.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_fakes.dart';

void main() {
  group('GH integration matrix', () {
    test(
      'default gh-mode auto prefers binary when release asset is available',
      () async {
        final temp = await Directory.systemTemp.createTemp('drx_gh_int_');
        addTearDown(() => temp.delete(recursive: true));

        final assetBytes = utf8.encode('binary');
        final checksum = sha256Hex(assetBytes);
        final release = GitHubRelease(
          tag: 'v1.0.0',
          assets: const [
            GitHubAsset(
              name: 'tool.exe',
              downloadUrl: 'https://example/tool.exe',
            ),
            GitHubAsset(
              name: 'SHA256SUMS',
              downloadUrl: 'https://example/SHA256SUMS',
            ),
          ],
        );

        final fakeExec = FakeProcessExecutor(
          handler: (exe, args, {workingDirectory, runInShell = false}) {
            expect(exe.toLowerCase(), endsWith('.exe'));
            expect(args, ['--version']);
            return 0;
          },
        );

        final engine = DrxEngine(
          paths: DrxPaths(temp),
          platform: const HostPlatform(os: 'windows', arch: 'x64'),
          processExecutor: fakeExec,
          gitHubApi: FakeGitHubApi(byTag: {'v1.0.0': release}),
          fetcher: FakeByteFetcher({
            'https://example/tool.exe': assetBytes,
            'https://example/SHA256SUMS': utf8.encode('$checksum  tool.exe\n'),
          }),
        );

        final code = await engine.run([
          '--from',
          'gh:org/repo@v1.0.0',
          'tool',
          '--',
          '--version',
        ]);

        expect(code, 0);
        expect(fakeExec.calls, hasLength(1));
      },
    );

    test('gh source runtime aot compiles and runs native binary', () async {
      final temp = await Directory.systemTemp.createTemp('drx_gh_int_');
      addTearDown(() => temp.delete(recursive: true));

      final fakeExec = FakeProcessExecutor(
        handler: (exe, args, {workingDirectory, runInShell = false}) async {
          if (exe == 'dart' && args.length >= 2 && args[0] == 'pub') {
            await _seedResolvedPackage(
              workingDirectory!,
              packageName: 'tool',
              scriptName: 'tool',
            );
            return 0;
          }

          if (exe == 'dart' && args.length >= 2 && args[0] == 'compile') {
            final outputIndex = args.indexOf('--output');
            final outputPath = args[outputIndex + 1];
            final outputFile = File(outputPath);
            await outputFile.parent.create(recursive: true);
            await outputFile.writeAsString('binary');
            return 0;
          }

          if (p.basenameWithoutExtension(exe) == 'tool') {
            expect(args, ['--version']);
            return 0;
          }

          return 1;
        },
      );

      final engine = DrxEngine(
        paths: DrxPaths(temp),
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
        processExecutor: fakeExec,
        gitHubApi: FakeGitHubApi(
          latest: const GitHubRelease(tag: 'v0', assets: []),
        ),
        fetcher: FakeByteFetcher(const {}),
      );

      final code = await engine.run([
        '--gh-mode',
        'source',
        '--runtime',
        'aot',
        '--from',
        'gh:org/repo',
        'tool:tool',
        '--',
        '--version',
      ]);

      expect(code, 0);
      expect(fakeExec.calls, hasLength(3));
      expect(fakeExec.calls[0].arguments, ['pub', 'get']);
      expect(fakeExec.calls[1].arguments[0], 'compile');
      expect(fakeExec.calls[1].arguments[1], 'exe');
      expect(p.basenameWithoutExtension(fakeExec.calls[2].executable), 'tool');
    });

    test(
      'gh source runtime auto falls back to jit on compile failure',
      () async {
        final temp = await Directory.systemTemp.createTemp('drx_gh_int_');
        addTearDown(() => temp.delete(recursive: true));

        final fakeExec = FakeProcessExecutor(
          handler: (exe, args, {workingDirectory, runInShell = false}) async {
            if (exe == 'dart' && args.length >= 2 && args[0] == 'pub') {
              await _seedResolvedPackage(
                workingDirectory!,
                packageName: 'tool',
                scriptName: 'tool',
              );
              return 0;
            }

            if (exe == 'dart' && args.length >= 2 && args[0] == 'compile') {
              return 1;
            }

            if (exe == 'dart' && args.length >= 2 && args[0] == 'run') {
              expect(args, ['run', 'tool:tool', '--version']);
              return 0;
            }

            return 1;
          },
        );

        final engine = DrxEngine(
          paths: DrxPaths(temp),
          platform: const HostPlatform(os: 'linux', arch: 'x64'),
          processExecutor: fakeExec,
          gitHubApi: FakeGitHubApi(
            latest: const GitHubRelease(tag: 'v0', assets: []),
          ),
          fetcher: FakeByteFetcher(const {}),
        );

        final code = await engine.run([
          '--gh-mode',
          'source',
          '--runtime',
          'auto',
          '--from',
          'gh:org/repo',
          'tool:tool',
          '--',
          '--version',
        ]);

        expect(code, 0);
        expect(fakeExec.calls, hasLength(3));
        expect(fakeExec.calls[0].arguments, ['pub', 'get']);
        expect(fakeExec.calls[1].arguments[0], 'compile');
        expect(fakeExec.calls[2].arguments, ['run', 'tool:tool', '--version']);
      },
    );

    test(
      'gh source runtime auto falls back to jit for cli_launcher wrappers',
      () async {
        final temp = await Directory.systemTemp.createTemp('drx_gh_int_');
        addTearDown(() => temp.delete(recursive: true));

        final fakeExec = FakeProcessExecutor(
          handler: (exe, args, {workingDirectory, runInShell = false}) async {
            if (exe == 'dart' && args.length >= 2 && args[0] == 'pub') {
              await _seedResolvedPackage(
                workingDirectory!,
                packageName: 'tool',
                scriptName: 'tool',
                useCliLauncher: true,
              );
              return 0;
            }

            if (exe == 'dart' && args.length >= 2 && args[0] == 'run') {
              expect(args, ['run', 'tool:tool', '--version']);
              return 0;
            }

            if (exe == 'dart' && args.length >= 2 && args[0] == 'compile') {
              fail('compile should be skipped for cli_launcher wrappers');
            }

            return 1;
          },
        );

        final engine = DrxEngine(
          paths: DrxPaths(temp),
          platform: const HostPlatform(os: 'linux', arch: 'x64'),
          processExecutor: fakeExec,
          gitHubApi: FakeGitHubApi(
            latest: const GitHubRelease(tag: 'v0', assets: []),
          ),
          fetcher: FakeByteFetcher(const {}),
        );

        final code = await engine.run([
          '--gh-mode',
          'source',
          '--runtime',
          'auto',
          '--from',
          'gh:org/repo',
          'tool:tool',
          '--',
          '--version',
        ]);

        expect(code, 0);
        expect(fakeExec.calls, hasLength(2));
        expect(fakeExec.calls[0].arguments, ['pub', 'get']);
        expect(fakeExec.calls[1].arguments, ['run', 'tool:tool', '--version']);
      },
    );

    test(
      'default gh-mode auto falls back to source and uses runtime auto strategy',
      () async {
        final temp = await Directory.systemTemp.createTemp('drx_gh_int_');
        addTearDown(() => temp.delete(recursive: true));

        final fakeExec = FakeProcessExecutor(
          handler: (exe, args, {workingDirectory, runInShell = false}) async {
            if (exe == 'dart' && args.length >= 2 && args[0] == 'pub') {
              await _seedResolvedPackage(
                workingDirectory!,
                packageName: 'tool',
                scriptName: 'tool',
              );
              return 0;
            }

            if (exe == 'dart' && args.length >= 2 && args[0] == 'compile') {
              final outputIndex = args.indexOf('--output');
              final outputPath = args[outputIndex + 1];
              final outputFile = File(outputPath);
              await outputFile.parent.create(recursive: true);
              await outputFile.writeAsString('binary');
              return 0;
            }

            if (p.basenameWithoutExtension(exe) == 'tool') {
              expect(args, ['--version']);
              return 0;
            }

            return 1;
          },
        );

        final engine = DrxEngine(
          paths: DrxPaths(temp),
          platform: const HostPlatform(os: 'linux', arch: 'x64'),
          processExecutor: fakeExec,
          gitHubApi: FakeGitHubApi(
            latest: const GitHubRelease(tag: 'v1.0.0', assets: []),
          ),
          fetcher: FakeByteFetcher({
            'https://raw.githubusercontent.com/org/repo/HEAD/pubspec.yaml': utf8
                .encode('name: tool\n'),
          }),
        );

        final code = await engine.run([
          '--runtime',
          'auto',
          '--from',
          'gh:org/repo',
          'tool',
          '--',
          '--version',
        ]);

        expect(code, 0);
        expect(fakeExec.calls, hasLength(3));
        expect(fakeExec.calls[0].arguments, ['pub', 'get']);
        expect(fakeExec.calls[1].arguments[0], 'compile');
        expect(
          p.basenameWithoutExtension(fakeExec.calls[2].executable),
          'tool',
        );
      },
    );
  });
}

Future<void> _seedResolvedPackage(
  String sandboxPath, {
  required String packageName,
  required String scriptName,
  bool useCliLauncher = false,
}) async {
  final packageDirName = '${packageName}_pkg';
  final packageRoot = Directory(p.join(sandboxPath, packageDirName));
  await packageRoot.create(recursive: true);

  await File(
    p.join(packageRoot.path, 'pubspec.yaml'),
  ).writeAsString('name: $packageName\n');

  final binDir = Directory(p.join(packageRoot.path, 'bin'));
  await binDir.create(recursive: true);
  final entrypoint = useCliLauncher
      ? "import 'package:cli_launcher/cli_launcher.dart';\n"
            'Future<void> main(List<String> args) async => launchExecutable();\n'
      : 'void main(List<String> args) {}\n';
  await File(p.join(binDir.path, '$scriptName.dart')).writeAsString(entrypoint);

  final packageConfig = File(
    p.join(sandboxPath, '.dart_tool', 'package_config.json'),
  );
  await packageConfig.parent.create(recursive: true);
  await packageConfig.writeAsString(
    jsonEncode({
      'configVersion': 2,
      'packages': [
        {
          'name': packageName,
          'rootUri': '../$packageDirName/',
          'packageUri': 'lib/',
          'languageVersion': '3.0',
        },
      ],
    }),
  );
}
