import 'dart:convert';
import 'dart:io';

import 'package:drx/src/cache_paths.dart';
import 'package:drx/src/models.dart';
import 'package:drx/src/platform_info.dart';
import 'package:drx/src/pub_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_fakes.dart';

void main() {
  group('PubRunner', () {
    test('runs jit mode with dart run package:command', () async {
      final tempHome = await Directory.systemTemp.createTemp('drx_pub_test_');
      addTearDown(() => tempHome.delete(recursive: true));

      final fakeExec = FakeProcessExecutor(
        handler: (executable, args, {workingDirectory, runInShell = false}) {
          if (executable == 'dart' && args.length >= 2 && args[0] == 'pub') {
            return 0;
          }
          if (executable == 'dart' && args.isNotEmpty && args[0] == 'run') {
            return 0;
          }
          return 1;
        },
      );

      final runner = PubRunner(
        paths: DrxPaths(tempHome),
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
        processExecutor: fakeExec,
      );

      final code = await runner.execute(
        const CommandRequest(
          source: SourceSpec(type: SourceType.pub, identifier: 'melos'),
          command: 'melos',
          args: ['--version'],
          runtime: RuntimeMode.jit,
          refresh: false,
          isolated: false,
          allowUnsigned: false,
          verbose: false,
        ),
      );

      expect(code, 0);
      final runCall = fakeExec.calls
          .where((c) => c.executable == 'dart' && c.arguments.first == 'run')
          .single;
      expect(runCall.arguments[1], 'melos:melos');
      expect(runCall.arguments[2], '--version');
    });

    test(
      'runs aot mode and compiles executable from mapped pubspec executable',
      () async {
        final tempHome = await Directory.systemTemp.createTemp('drx_pub_test_');
        addTearDown(() => tempHome.delete(recursive: true));

        final paths = DrxPaths(tempHome);
        final sandbox = paths.pubSandboxDir('tool_pkg', 'latest');
        await _writePackageFixture(
          sandbox,
          package: 'tool_pkg',
          executableName: 'tool',
          scriptName: 'main_script',
        );

        final fakeExec = FakeProcessExecutor(
          handler: (executable, args, {workingDirectory, runInShell = false}) {
            if (executable == 'dart' && args.isNotEmpty && args[0] == 'pub') {
              return 0;
            }
            if (executable == 'dart' &&
                args.length >= 2 &&
                args[0] == 'compile') {
              return 0;
            }
            return 0;
          },
        );

        final runner = PubRunner(
          paths: paths,
          platform: const HostPlatform(os: 'windows', arch: 'x64'),
          processExecutor: fakeExec,
        );

        final code = await runner.execute(
          const CommandRequest(
            source: SourceSpec(type: SourceType.pub, identifier: 'tool_pkg'),
            command: 'tool',
            args: ['--check'],
            runtime: RuntimeMode.aot,
            refresh: false,
            isolated: false,
            allowUnsigned: false,
            verbose: false,
          ),
        );

        expect(code, 0);
        final compileCall = fakeExec.calls
            .where(
              (c) => c.executable == 'dart' && c.arguments.first == 'compile',
            )
            .single;
        expect(compileCall.arguments[2], '--packages');
        expect(
          _normalizedPath(compileCall.arguments[3]),
          endsWith('.dart_tool/package_config.json'),
        );
        expect(
          compileCall.arguments.last,
          endsWith(p.join('bin', 'main_script.dart')),
        );

        final runCall = fakeExec.calls.last;
        expect(runCall.executable, endsWith('tool.exe'));
        expect(runCall.arguments, ['--check']);
      },
    );

    test('auto runtime falls back to jit when aot compile fails', () async {
      final tempHome = await Directory.systemTemp.createTemp('drx_pub_test_');
      addTearDown(() => tempHome.delete(recursive: true));

      final paths = DrxPaths(tempHome);
      final sandbox = paths.pubSandboxDir('tool_pkg', 'latest');
      await _writePackageFixture(
        sandbox,
        package: 'tool_pkg',
        executableName: 'tool',
        scriptName: 'tool',
      );

      final fakeExec = FakeProcessExecutor(
        handler: (executable, args, {workingDirectory, runInShell = false}) {
          if (executable == 'dart' && args.isNotEmpty && args[0] == 'pub') {
            return 0;
          }
          if (executable == 'dart' && args.isNotEmpty && args[0] == 'compile') {
            return 1;
          }
          if (executable == 'dart' && args.isNotEmpty && args[0] == 'run') {
            return 0;
          }
          return 0;
        },
      );

      final runner = PubRunner(
        paths: paths,
        platform: const HostPlatform(os: 'windows', arch: 'x64'),
        processExecutor: fakeExec,
      );

      final code = await runner.execute(
        const CommandRequest(
          source: SourceSpec(type: SourceType.pub, identifier: 'tool_pkg'),
          command: 'tool',
          args: ['--version'],
          runtime: RuntimeMode.auto,
          refresh: false,
          isolated: false,
          allowUnsigned: false,
          verbose: false,
        ),
      );

      expect(code, 0);
      expect(
        fakeExec.calls.where(
          (c) => c.executable == 'dart' && c.arguments.first == 'run',
        ),
        hasLength(1),
      );
    });

    test('auto runtime skips AOT for cli_launcher wrapper', () async {
      final tempHome = await Directory.systemTemp.createTemp('drx_pub_test_');
      addTearDown(() => tempHome.delete(recursive: true));

      final paths = DrxPaths(tempHome);
      final sandbox = paths.pubSandboxDir('tool_pkg', 'latest');
      await _writePackageFixture(
        sandbox,
        package: 'tool_pkg',
        executableName: 'tool',
        scriptName: 'tool',
        scriptBody: '''
import 'package:cli_launcher/cli_launcher.dart';
Future<void> main(List<String> args) async => launchExecutable();
''',
      );

      final fakeExec = FakeProcessExecutor(
        handler: (executable, args, {workingDirectory, runInShell = false}) {
          if (executable == 'dart' && args.isNotEmpty && args[0] == 'pub') {
            return 0;
          }
          if (executable == 'dart' && args.isNotEmpty && args[0] == 'compile') {
            return 99;
          }
          if (executable == 'dart' && args.isNotEmpty && args[0] == 'run') {
            return 0;
          }
          return 0;
        },
      );

      final runner = PubRunner(
        paths: paths,
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
        processExecutor: fakeExec,
      );

      final code = await runner.execute(
        const CommandRequest(
          source: SourceSpec(type: SourceType.pub, identifier: 'tool_pkg'),
          command: 'tool',
          args: ['--version'],
          runtime: RuntimeMode.auto,
          refresh: false,
          isolated: false,
          allowUnsigned: false,
          verbose: false,
        ),
      );

      expect(code, 0);
      expect(
        fakeExec.calls.where(
          (c) => c.executable == 'dart' && c.arguments.first == 'compile',
        ),
        isEmpty,
      );
      expect(
        fakeExec.calls.where(
          (c) => c.executable == 'dart' && c.arguments.first == 'run',
        ),
        hasLength(1),
      );
    });

    test('aot runtime errors for cli_launcher wrapper', () async {
      final tempHome = await Directory.systemTemp.createTemp('drx_pub_test_');
      addTearDown(() => tempHome.delete(recursive: true));

      final paths = DrxPaths(tempHome);
      final sandbox = paths.pubSandboxDir('tool_pkg', 'latest');
      await _writePackageFixture(
        sandbox,
        package: 'tool_pkg',
        executableName: 'tool',
        scriptName: 'tool',
        scriptBody: '''
import 'package:cli_launcher/cli_launcher.dart';
Future<void> main(List<String> args) async => launchExecutable();
''',
      );

      final fakeExec = FakeProcessExecutor(
        handler: (executable, args, {workingDirectory, runInShell = false}) {
          if (executable == 'dart' && args.isNotEmpty && args[0] == 'pub') {
            return 0;
          }
          return 0;
        },
      );

      final runner = PubRunner(
        paths: paths,
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
        processExecutor: fakeExec,
      );

      expect(
        () => runner.execute(
          const CommandRequest(
            source: SourceSpec(type: SourceType.pub, identifier: 'tool_pkg'),
            command: 'tool',
            args: ['--version'],
            runtime: RuntimeMode.aot,
            refresh: false,
            isolated: false,
            allowUnsigned: false,
            verbose: false,
          ),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('package:cli_launcher'),
          ),
        ),
      );
    });
  });
}

String _normalizedPath(String value) => value.replaceAll('\\', '/');

Future<void> _writePackageFixture(
  Directory sandbox, {
  required String package,
  required String executableName,
  required String scriptName,
  String? scriptBody,
}) async {
  await Directory(p.join(sandbox.path, '.dart_tool')).create(recursive: true);

  final packageRoot = await Directory.systemTemp.createTemp('drx_pkg_root_');
  await Directory(p.join(packageRoot.path, 'bin')).create(recursive: true);
  await File(
    p.join(packageRoot.path, 'bin', '$scriptName.dart'),
  ).writeAsString(scriptBody ?? 'void main(List<String> args) {}');
  await File(p.join(packageRoot.path, 'pubspec.yaml')).writeAsString('''
name: $package
executables:
  $executableName: $scriptName
''');

  final packageConfig = {
    'configVersion': 2,
    'packages': [
      {
        'name': package,
        'rootUri': '${Uri.directory(packageRoot.path)}',
        'packageUri': 'lib/',
        'languageVersion': '3.0',
      },
    ],
  };

  await File(
    p.join(sandbox.path, '.dart_tool', 'package_config.json'),
  ).writeAsString(jsonEncode(packageConfig));
}
