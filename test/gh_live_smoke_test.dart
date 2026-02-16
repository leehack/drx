import 'dart:io';

import 'package:drx/src/cache_paths.dart';
import 'package:drx/src/engine.dart';
import 'package:drx/src/platform_info.dart';
import 'package:test/test.dart';

const _liveEnvKey = 'DRX_ENABLE_LIVE_GH_TESTS';

void main() {
  final liveEnabled = Platform.environment[_liveEnvKey] == '1';
  final skipReason = liveEnabled
      ? false
      : 'Set $_liveEnvKey=1 to run live GitHub smoke tests.';

  group('Live GitHub smoke', () {
    late Directory home;

    setUpAll(() async {
      home = await Directory.systemTemp.createTemp('drx_gh_live_');
    });

    tearDownAll(() async {
      if (await home.exists()) {
        await home.delete(recursive: true);
      }
    });

    test(
      'default gh-mode auto uses release binary when available',
      () async {
        final engine = DrxEngine(
          paths: DrxPaths(home),
          platform: HostPlatform.detect(),
        );

        final code = await engine.run([
          '--from',
          'gh:BurntSushi/ripgrep@14.1.1',
          'rg',
          '--',
          '--version',
        ]);

        expect(code, 0);
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'default gh-mode auto falls back to source and runs runtime auto',
      () async {
        final engine = DrxEngine(
          paths: DrxPaths(home),
          platform: HostPlatform.detect(),
        );

        final code = await engine.run([
          '--runtime',
          'auto',
          '--from',
          'gh:leehack/mcp_dart@mcp_dart_cli-v0.1.6',
          '--git-path',
          'packages/mcp_dart_cli',
          'mcp_dart',
          '--',
          '--help',
        ]);

        expect(code, 0);
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 8)),
    );
  });
}
