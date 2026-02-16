import 'dart:io';
import 'dart:convert';

import 'cache_manager.dart';
import 'cache_paths.dart';
import 'cli_parser.dart';
import 'errors.dart';
import 'github_api.dart';
import 'github_runner.dart';
import 'models.dart';
import 'platform_info.dart';
import 'process_executor.dart';
import 'pub_runner.dart';
import 'version_lister.dart';

/// Current drx CLI version.
const String drxVersion = '0.3.1';

/// Command engine that coordinates parsing, resolution, and execution.
final class DrxEngine {
  DrxEngine({
    CliParser? parser,
    HostPlatform? platform,
    DrxPaths? paths,
    ProcessExecutor? processExecutor,
    GitHubApi? gitHubApi,
    ByteFetcher? fetcher,
    PubRunner? pubRunner,
    GitHubRunner? ghRunner,
  }) : _parser = parser ?? CliParser(),
       _platform = platform ?? HostPlatform.detect(),
       _paths = paths ?? DrxPaths.resolve(platform: platform),
       _processExecutor = processExecutor ?? const IoProcessExecutor(),
       _fetcher = fetcher ?? const HttpByteFetcher(),
       _gitHubApi = gitHubApi ?? HttpGitHubApi(fetcher: fetcher),
       _pubRunner = pubRunner,
       _ghRunner = ghRunner;

  final CliParser _parser;
  final HostPlatform _platform;
  final DrxPaths _paths;
  final ProcessExecutor _processExecutor;
  final ByteFetcher _fetcher;
  final GitHubApi _gitHubApi;
  final PubRunner? _pubRunner;
  final GitHubRunner? _ghRunner;

  /// Runs a drx command and returns a process-style exit code.
  Future<int> run(List<String> argv) async {
    try {
      if (argv.isEmpty) {
        stdout.writeln(_helpText());
        return 0;
      }

      final utilityGlobals = _parseUtilityGlobals(argv);
      final utilityArgs = utilityGlobals.remaining;

      if (utilityArgs.isEmpty) {
        if (utilityGlobals.showVersion) {
          stdout.writeln(drxVersion);
          return 0;
        }
        stdout.writeln(_helpText());
        return 0;
      }

      if (utilityArgs.first == 'cache') {
        return await _handleCacheCommand(
          utilityArgs.skip(1).toList(growable: false),
          jsonOutput: utilityGlobals.jsonOutput,
          verbose: utilityGlobals.verbose,
        );
      }

      if (utilityArgs.first == 'versions') {
        return await _handleVersionsCommand(
          utilityArgs.skip(1).toList(growable: false),
          jsonOutput: utilityGlobals.jsonOutput,
          verbose: utilityGlobals.verbose,
        );
      }

      final parsed = _parser.parse(argv);
      if (parsed.showHelp) {
        stdout.writeln(_helpText());
        return 0;
      }
      if (parsed.showVersion) {
        stdout.writeln(drxVersion);
        return 0;
      }

      await _paths.ensureBaseDirectories();
      final request = parsed.request!;
      final pubRunner =
          _pubRunner ??
          PubRunner(
            paths: _paths,
            platform: _platform,
            processExecutor: _processExecutor,
          );
      final ghRunner =
          _ghRunner ??
          GitHubRunner(
            paths: _paths,
            platform: _platform,
            processExecutor: _processExecutor,
            api: _gitHubApi,
            fetcher: _fetcher,
          );

      switch (request.source.type) {
        case SourceType.pub:
          return await pubRunner.execute(request);
        case SourceType.gh:
          return await ghRunner.execute(request);
      }
    } on CliParseException catch (error) {
      stderr.writeln('drx: ${error.message}');
      stderr.writeln('Try `drx --help` for usage.');
      return 64;
    } on DrxException catch (error) {
      stderr.writeln('drx: ${error.message}');
      return error.exitCode;
    }
  }

  Future<int> _handleCacheCommand(
    List<String> args, {
    required bool jsonOutput,
    required bool verbose,
  }) async {
    await _paths.ensureBaseDirectories();
    final manager = CacheManager(_paths);

    String? subcommand;
    Duration? maxAge;
    int? maxSizeBytes;
    var i = 0;
    while (i < args.length) {
      final token = args[i];
      if (token == '--json') {
        jsonOutput = true;
        i++;
        continue;
      }
      if (token == '-v' || token == '--verbose') {
        verbose = true;
        i++;
        continue;
      }
      if (token.startsWith('--max-age-days=')) {
        maxAge = _parseAgeOption(token.substring('--max-age-days='.length));
        i++;
        continue;
      }
      if (token == '--max-age-days') {
        if (i + 1 >= args.length) {
          throw const CliParseException('Missing value for --max-age-days.');
        }
        maxAge = _parseAgeOption(args[i + 1]);
        i += 2;
        continue;
      }
      if (token.startsWith('--max-size-mb=')) {
        maxSizeBytes = _parseSizeOption(
          token.substring('--max-size-mb='.length),
        );
        i++;
        continue;
      }
      if (token == '--max-size-mb') {
        if (i + 1 >= args.length) {
          throw const CliParseException('Missing value for --max-size-mb.');
        }
        maxSizeBytes = _parseSizeOption(args[i + 1]);
        i += 2;
        continue;
      }

      if (token.startsWith('-')) {
        throw CliParseException('Unknown option for cache: $token');
      }

      if (subcommand == null) {
        subcommand = token;
        i++;
        continue;
      }

      throw CliParseException('Unexpected cache argument: $token');
    }

    subcommand ??= 'list';

    if (verbose) {
      stderr.writeln(
        '[drx:cache] command=$subcommand path=${_paths.cacheDirectory.path}',
      );
    }

    if (subcommand == 'list' || subcommand == 'ls') {
      final summary = await manager.summarize();
      if (jsonOutput) {
        stdout.writeln(
          jsonEncode({
            'cachePath': _paths.cacheDirectory.path,
            'pubEntries': summary.pubEntries,
            'pubAotEntries': summary.pubAotEntries,
            'ghEntries': summary.ghEntries,
            'totalBytes': summary.totalBytes,
            'totalSize': _formatBytes(summary.totalBytes),
          }),
        );
        return 0;
      }

      stdout.writeln('drx cache: ${_paths.cacheDirectory.path}');
      stdout.writeln('  pub sandboxes : ${summary.pubEntries}');
      stdout.writeln('  pub aot bins  : ${summary.pubAotEntries}');
      stdout.writeln('  gh assets     : ${summary.ghEntries}');
      stdout.writeln('  total size    : ${_formatBytes(summary.totalBytes)}');
      return 0;
    }

    if (subcommand == 'clean') {
      await manager.cleanAll();
      if (jsonOutput) {
        stdout.writeln(
          jsonEncode({
            'action': 'clean',
            'cachePath': _paths.cacheDirectory.path,
            'ok': true,
          }),
        );
        return 0;
      }
      stdout.writeln('drx cache cleaned: ${_paths.cacheDirectory.path}');
      return 0;
    }

    if (subcommand == 'prune') {
      maxAge ??= const Duration(days: 30);
      final summary = await manager.prune(
        maxAge: maxAge,
        maxTotalBytes: maxSizeBytes,
      );
      if (jsonOutput) {
        stdout.writeln(
          jsonEncode({
            'action': 'prune',
            'cachePath': _paths.cacheDirectory.path,
            'removedEntries': summary.removedEntries,
            'removedBytes': summary.removedBytes,
            'removedSize': _formatBytes(summary.removedBytes),
            'remainingEntries': summary.remainingEntries,
            'remainingBytes': summary.remainingBytes,
            'remainingSize': _formatBytes(summary.remainingBytes),
            'maxAgeDays': maxAge.inDays,
            'maxSizeMb': maxSizeBytes == null
                ? null
                : (maxSizeBytes / (1024 * 1024)).round(),
          }),
        );
        return 0;
      }

      stdout.writeln('drx cache pruned: ${_paths.cacheDirectory.path}');
      stdout.writeln('  removed entries : ${summary.removedEntries}');
      stdout.writeln(
        '  removed size    : ${_formatBytes(summary.removedBytes)}',
      );
      stdout.writeln('  remaining entry : ${summary.remainingEntries}');
      stdout.writeln(
        '  remaining size  : ${_formatBytes(summary.remainingBytes)}',
      );
      return 0;
    }

    throw CliParseException(
      'Unknown cache command "$subcommand". Use `cache list`, `cache clean`, or `cache prune`.',
    );
  }

  Future<int> _handleVersionsCommand(
    List<String> args, {
    required bool jsonOutput,
    required bool verbose,
  }) async {
    if (args.isEmpty) {
      throw const CliParseException(
        'Missing versions target. Use: drx versions <package|pub:pkg|gh:owner/repo>.',
      );
    }

    var limit = 20;
    String? target;
    var i = 0;
    while (i < args.length) {
      final token = args[i];
      if (token == '--json') {
        jsonOutput = true;
        i++;
        continue;
      }
      if (token == '-v' || token == '--verbose') {
        verbose = true;
        i++;
        continue;
      }
      if (token.startsWith('--limit=')) {
        limit = int.tryParse(token.substring('--limit='.length)) ?? -1;
        if (limit < 1) {
          throw const CliParseException(
            'Invalid --limit value. Use integer > 0.',
          );
        }
        i++;
        continue;
      }
      if (token == '--limit') {
        if (i + 1 >= args.length) {
          throw const CliParseException('Missing value for --limit.');
        }
        limit = int.tryParse(args[i + 1]) ?? -1;
        if (limit < 1) {
          throw const CliParseException(
            'Invalid --limit value. Use integer > 0.',
          );
        }
        i += 2;
        continue;
      }
      if (token.startsWith('-')) {
        throw CliParseException('Unknown option for versions: $token');
      }
      if (target != null) {
        throw CliParseException('Unexpected extra argument: $token');
      }
      target = token;
      i++;
    }

    if (target == null || target.isEmpty) {
      throw const CliParseException(
        'Missing versions target. Use: drx versions <package|pub:pkg|gh:owner/repo>.',
      );
    }

    final lister = VersionLister(fetcher: _fetcher, gitHubApi: _gitHubApi);
    if (verbose) {
      stderr.writeln('[drx:versions] target=$target limit=$limit');
    }
    final versions = await lister.listVersions(target, limit: limit);
    if (jsonOutput) {
      stdout.writeln(
        jsonEncode({'target': target, 'limit': limit, 'versions': versions}),
      );
      return 0;
    }

    stdout.writeln('Available versions for $target:');
    for (final version in versions) {
      stdout.writeln('  $version');
    }
    return 0;
  }

  ({List<String> remaining, bool jsonOutput, bool verbose, bool showVersion})
  _parseUtilityGlobals(List<String> argv) {
    final remaining = <String>[];
    var jsonOutput = false;
    var verbose = false;
    var showVersion = false;

    var i = 0;
    while (i < argv.length) {
      final token = argv[i];
      if (token == '--json') {
        jsonOutput = true;
        i++;
        continue;
      }
      if (token == '-v' || token == '--verbose') {
        verbose = true;
        i++;
        continue;
      }
      if (token == '--version') {
        showVersion = true;
        i++;
        continue;
      }
      if (token == '-h' || token == '--help') {
        return (
          remaining: const [],
          jsonOutput: jsonOutput,
          verbose: verbose,
          showVersion: false,
        );
      }
      break;
    }

    remaining.addAll(argv.skip(i));
    return (
      remaining: remaining,
      jsonOutput: jsonOutput,
      verbose: verbose,
      showVersion: showVersion,
    );
  }

  Duration _parseAgeOption(String value) {
    final days = int.tryParse(value);
    if (days == null || days < 0) {
      throw const CliParseException(
        'Invalid --max-age-days value. Use integer >= 0.',
      );
    }
    return Duration(days: days);
  }

  int _parseSizeOption(String value) {
    final mb = int.tryParse(value);
    if (mb == null || mb < 0) {
      throw const CliParseException(
        'Invalid --max-size-mb value. Use integer >= 0.',
      );
    }
    return mb * 1024 * 1024;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var index = -1;
    while (value >= 1024 && index + 1 < units.length) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(1)} ${units[index]}';
  }

  String _helpText() {
    return '''
drx $drxVersion

Usage:
  drx <package[@version]> [--] [args...]
  drx <package:executable[@version]> [--] [args...]
  drx --from pub:<package[@version]> <command> [--] [args...]
  drx --from gh:<owner>/<repo[@tag]> <command> [--] [args...]
      [--gh-mode binary|source|auto] [--git-path <path>]
  drx cache [list|clean|prune] [--json]
  drx cache prune [--max-age-days N] [--max-size-mb N] [--json]
  drx versions <package|pub:pkg|gh:owner/repo> [--limit N] [--json]

Default source: pub.

Options:
  -h, --help             Show this help.
      --version          Show version.
      --from <source>    Source: pub:... or gh:...
      --runtime <mode>   auto | jit | aot
      --refresh          Refresh cached artifacts.
      --isolated         Use isolated temporary environment.
      --gh-mode <mode>   binary | source | auto (gh source only; default: auto)
      --git-path <path>  Package path in GitHub monorepo (gh source mode).
      --asset <name>     Asset override for gh binary mode.
      --allow-unsigned   Allow running unsigned gh assets.
      --json             JSON output (cache/versions commands).
  -v, --verbose          Verbose output.
''';
  }
}
