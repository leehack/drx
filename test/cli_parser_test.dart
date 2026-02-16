import 'package:drx/src/cli_parser.dart';
import 'package:drx/src/errors.dart';
import 'package:drx/src/models.dart';
import 'package:test/test.dart';

void main() {
  group('CliParser', () {
    final parser = CliParser();

    test('parses default pub command with version', () {
      final parsed = parser.parse(['melos@4.1.0', '--', '--version']);
      final request = parsed.request!;

      expect(request.source.type, SourceType.pub);
      expect(request.source.identifier, 'melos');
      expect(request.source.version, '4.1.0');
      expect(request.command, 'melos');
      expect(request.args, ['--version']);
      expect(request.runtime, RuntimeMode.auto);
    });

    test('parses default pub package:executable with version', () {
      final parsed = parser.parse(['package_name:tool@1.2.3', '--', '--help']);
      final request = parsed.request!;

      expect(request.source.type, SourceType.pub);
      expect(request.source.identifier, 'package_name');
      expect(request.source.version, '1.2.3');
      expect(request.command, 'tool');
      expect(request.args, ['--help']);
    });

    test('parses explicit pub source', () {
      final parsed = parser.parse([
        '--from',
        'pub:very_good_cli@1.0.0',
        'very_good',
      ]);
      final request = parsed.request!;

      expect(request.source.type, SourceType.pub);
      expect(request.source.identifier, 'very_good_cli');
      expect(request.source.version, '1.0.0');
      expect(request.command, 'very_good');
    });

    test('parses explicit gh source', () {
      final parsed = parser.parse([
        '--from=gh:cli/cli@v2.70.0',
        'gh',
        'version',
      ]);
      final request = parsed.request!;

      expect(request.source.type, SourceType.gh);
      expect(request.source.identifier, 'cli/cli');
      expect(request.source.version, 'v2.70.0');
      expect(request.ghMode, GhMode.auto);
      expect(request.command, 'gh');
      expect(request.args, ['version']);
    });

    test('parses inline pub source shorthand', () {
      final parsed = parser.parse(['pub:mcp_dart']);
      final request = parsed.request!;

      expect(request.source.type, SourceType.pub);
      expect(request.source.identifier, 'mcp_dart');
      expect(request.source.version, isNull);
      expect(request.command, 'mcp_dart');
      expect(request.args, isEmpty);
    });

    test('parses inline gh source shorthand with command', () {
      final parsed = parser.parse([
        'gh:cli/cli@v2.70.0',
        'gh',
        '--',
        'version',
      ]);
      final request = parsed.request!;

      expect(request.source.type, SourceType.gh);
      expect(request.source.identifier, 'cli/cli');
      expect(request.source.version, 'v2.70.0');
      expect(request.ghMode, GhMode.auto);
      expect(request.command, 'gh');
      expect(request.args, ['version']);
    });

    test('parses flags', () {
      final parsed = parser.parse([
        '--runtime=aot',
        '--refresh',
        '--isolated',
        '--allow-unsigned',
        '--verbose',
        '--asset',
        'tool-linux-x64.tar.gz',
        'tool',
      ]);
      final request = parsed.request!;

      expect(request.runtime, RuntimeMode.aot);
      expect(request.refresh, isTrue);
      expect(request.isolated, isTrue);
      expect(request.allowUnsigned, isTrue);
      expect(request.verbose, isTrue);
      expect(request.asset, 'tool-linux-x64.tar.gz');
    });

    test('parses gh source mode flags', () {
      final parsed = parser.parse([
        '--from',
        'gh:leehack/mcp_dart@mcp_dart_cli-v0.1.6',
        '--gh-mode',
        'source',
        '--git-path',
        'packages/mcp_dart_cli',
        'mcp_dart_cli:mcp_dart',
        '--',
        '--help',
      ]);
      final request = parsed.request!;

      expect(request.source.type, SourceType.gh);
      expect(request.ghMode, GhMode.source);
      expect(request.gitPath, 'packages/mcp_dart_cli');
      expect(request.command, 'mcp_dart_cli:mcp_dart');
      expect(request.args, ['--help']);
    });

    test('parses explicit gh binary mode', () {
      final parsed = parser.parse([
        '--from',
        'gh:cli/cli@v2.70.0',
        '--gh-mode',
        'binary',
        'gh',
        'version',
      ]);
      final request = parsed.request!;

      expect(request.source.type, SourceType.gh);
      expect(request.ghMode, GhMode.binary);
      expect(request.command, 'gh');
      expect(request.args, ['version']);
    });

    test('returns help and version without requiring command', () {
      final help = parser.parse(['--help']);
      final version = parser.parse(['--version']);

      expect(help.showHelp, isTrue);
      expect(help.request, isNull);
      expect(version.showVersion, isTrue);
      expect(version.request, isNull);
    });

    test('throws on invalid runtime', () {
      expect(
        () => parser.parse(['--runtime=fast', 'foo']),
        throwsA(isA<CliParseException>()),
      );
    });

    test('throws on unsupported source', () {
      expect(
        () => parser.parse(['--from', 'url:https://example.com', 'foo']),
        throwsA(isA<CliParseException>()),
      );
    });

    test('throws when --gh-mode is used with pub source', () {
      expect(
        () => parser.parse(['--gh-mode', 'source', 'melos']),
        throwsA(isA<CliParseException>()),
      );
    });

    test('throws when --git-path is used with binary gh mode', () {
      expect(
        () => parser.parse([
          '--from',
          'gh:org/repo',
          '--gh-mode',
          'binary',
          '--git-path',
          'packages/tool',
          'tool',
        ]),
        throwsA(isA<CliParseException>()),
      );
    });

    test('throws when gh shorthand command is missing', () {
      expect(
        () => parser.parse(['gh:cli/cli@v2.70.0']),
        throwsA(isA<CliParseException>()),
      );
    });

    test('throws when command is missing', () {
      expect(() => parser.parse([]), throwsA(isA<CliParseException>()));
    });
  });
}
