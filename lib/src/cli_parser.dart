import 'errors.dart';
import 'models.dart';

/// Parses command-line arguments into a normalized execution request.
final class CliParser {
  /// Parses raw argv into [ParsedCli].
  ParsedCli parse(List<String> argv) {
    var showHelp = false;
    var showVersion = false;
    String? fromRaw;
    RuntimeMode runtime = RuntimeMode.auto;
    var refresh = false;
    var isolated = false;
    GhMode ghMode = GhMode.binary;
    String? gitPath;
    String? asset;
    var allowUnsigned = false;
    var verbose = false;

    final positional = <String>[];
    var i = 0;
    while (i < argv.length) {
      final token = argv[i];
      if (token == '--') {
        positional.addAll(argv.sublist(i));
        break;
      }

      if (!token.startsWith('-') || token == '-') {
        positional.addAll(argv.sublist(i));
        break;
      }

      if (token == '-h' || token == '--help') {
        showHelp = true;
        i++;
        continue;
      }
      if (token == '--version') {
        showVersion = true;
        i++;
        continue;
      }
      if (token == '-v' || token == '--verbose') {
        verbose = true;
        i++;
        continue;
      }
      if (token == '--refresh') {
        refresh = true;
        i++;
        continue;
      }
      if (token == '--isolated') {
        isolated = true;
        i++;
        continue;
      }
      if (token == '--allow-unsigned') {
        allowUnsigned = true;
        i++;
        continue;
      }

      if (token.startsWith('--gh-mode=')) {
        ghMode = _parseGhMode(token.substring('--gh-mode='.length).trim());
        i++;
        continue;
      }
      if (token == '--gh-mode') {
        if (i + 1 >= argv.length) {
          throw const CliParseException('Missing value for --gh-mode.');
        }
        ghMode = _parseGhMode(argv[i + 1].trim());
        i += 2;
        continue;
      }

      if (token.startsWith('--git-path=')) {
        gitPath = token.substring('--git-path='.length).trim();
        i++;
        continue;
      }
      if (token == '--git-path') {
        if (i + 1 >= argv.length) {
          throw const CliParseException('Missing value for --git-path.');
        }
        gitPath = argv[i + 1].trim();
        i += 2;
        continue;
      }

      if (token.startsWith('--from=')) {
        fromRaw = token.substring('--from='.length).trim();
        i++;
        continue;
      }
      if (token == '--from') {
        if (i + 1 >= argv.length) {
          throw const CliParseException('Missing value for --from.');
        }
        fromRaw = argv[i + 1].trim();
        i += 2;
        continue;
      }

      if (token.startsWith('--runtime=')) {
        runtime = _parseRuntime(token.substring('--runtime='.length).trim());
        i++;
        continue;
      }
      if (token == '--runtime') {
        if (i + 1 >= argv.length) {
          throw const CliParseException('Missing value for --runtime.');
        }
        runtime = _parseRuntime(argv[i + 1].trim());
        i += 2;
        continue;
      }

      if (token.startsWith('--asset=')) {
        asset = token.substring('--asset='.length).trim();
        i++;
        continue;
      }
      if (token == '--asset') {
        if (i + 1 >= argv.length) {
          throw const CliParseException('Missing value for --asset.');
        }
        asset = argv[i + 1].trim();
        i += 2;
        continue;
      }

      throw CliParseException('Unknown option: $token');
    }

    if (showHelp || showVersion) {
      return ParsedCli(showHelp: showHelp, showVersion: showVersion);
    }

    if (positional.isEmpty) {
      throw const CliParseException('Missing command.');
    }

    late final SourceSpec source;
    late final String command;
    late final List<String> commandArgsInput;

    // Priority order:
    // 1) Explicit --from source
    // 2) Inline source shorthand (pub:... / gh:...)
    // 3) Default pub shorthand (<pkg> or <pkg:exe>)
    if (fromRaw != null) {
      source = _parseFromSource(fromRaw);
      command = positional.first;
      commandArgsInput = positional.skip(1).toList(growable: false);
    } else if (_looksLikeSourceSpec(positional.first)) {
      source = _parseFromSource(positional.first);
      final remaining = positional.skip(1).toList(growable: false);
      if (remaining.isEmpty || remaining.first == '--') {
        if (source.type == SourceType.pub) {
          command = source.identifier;
          commandArgsInput = remaining;
        } else {
          throw const CliParseException(
            'Missing command for gh source. Use gh:<owner>/<repo> <command>.',
          );
        }
      } else {
        command = remaining.first;
        commandArgsInput = remaining.skip(1).toList(growable: false);
      }
    } else {
      final parsedDefault = _parseDefaultPubTarget(positional.first);
      source = parsedDefault.source;
      command = parsedDefault.command;
      commandArgsInput = positional.skip(1).toList(growable: false);
    }

    final commandArgs = _extractCommandArgs(commandArgsInput);
    final normalizedGitPath = gitPath?.trim();

    if (source.type != SourceType.gh && ghMode != GhMode.binary) {
      throw const CliParseException('--gh-mode is only valid for gh source.');
    }
    if (source.type != SourceType.gh && normalizedGitPath != null) {
      throw const CliParseException('--git-path is only valid for gh source.');
    }
    if (source.type == SourceType.gh &&
        ghMode == GhMode.binary &&
        normalizedGitPath != null &&
        normalizedGitPath.isNotEmpty) {
      throw const CliParseException(
        '--git-path requires --gh-mode source or --gh-mode auto.',
      );
    }
    if (normalizedGitPath != null && normalizedGitPath.isEmpty) {
      throw const CliParseException('--git-path cannot be empty.');
    }

    final request = CommandRequest(
      source: source,
      command: command,
      args: commandArgs,
      runtime: runtime,
      refresh: refresh,
      isolated: isolated,
      allowUnsigned: allowUnsigned,
      verbose: verbose,
      ghMode: ghMode,
      gitPath: normalizedGitPath,
      asset: asset?.isEmpty == true ? null : asset,
    );

    return ParsedCli(showHelp: false, showVersion: false, request: request);
  }

  RuntimeMode _parseRuntime(String value) {
    switch (value) {
      case 'auto':
        return RuntimeMode.auto;
      case 'jit':
        return RuntimeMode.jit;
      case 'aot':
        return RuntimeMode.aot;
      default:
        throw CliParseException(
          'Invalid runtime "$value". Use auto, jit, or aot.',
        );
    }
  }

  GhMode _parseGhMode(String value) {
    switch (value) {
      case 'binary':
        return GhMode.binary;
      case 'source':
        return GhMode.source;
      case 'auto':
        return GhMode.auto;
      default:
        throw CliParseException(
          'Invalid gh mode "$value". Use binary, source, or auto.',
        );
    }
  }

  ({SourceSpec source, String command}) _parseDefaultPubTarget(String token) {
    final at = token.lastIndexOf('@');
    final hasVersion = at > 0;
    final base = hasVersion ? token.substring(0, at) : token;
    final version = hasVersion ? token.substring(at + 1) : null;

    if (base.isEmpty) {
      throw const CliParseException('Missing package name.');
    }
    if (hasVersion && (version == null || version.isEmpty)) {
      throw const CliParseException('Version cannot be empty after @.');
    }

    final colon = base.indexOf(':');
    final package = colon > 0 ? base.substring(0, colon) : base;
    final command = colon > 0 ? base.substring(colon + 1) : base;
    if (package.isEmpty || command.isEmpty) {
      throw CliParseException('Invalid package command "$token".');
    }

    return (
      source: SourceSpec(
        type: SourceType.pub,
        identifier: package,
        version: version,
      ),
      command: command,
    );
  }

  SourceSpec _parseFromSource(String raw) {
    if (raw.isEmpty) {
      throw const CliParseException('--from cannot be empty.');
    }

    if (raw.startsWith('pub:')) {
      final value = raw.substring(4);
      if (value.isEmpty) {
        throw CliParseException('Invalid pub source "$raw".');
      }
      final at = value.lastIndexOf('@');
      if (at <= 0) {
        return SourceSpec(type: SourceType.pub, identifier: value);
      }

      final pkg = value.substring(0, at);
      final version = value.substring(at + 1);
      if (pkg.isEmpty || version.isEmpty) {
        throw CliParseException('Invalid pub source "$raw".');
      }
      return SourceSpec(
        type: SourceType.pub,
        identifier: pkg,
        version: version,
      );
    }

    if (raw.startsWith('gh:')) {
      final value = raw.substring(3);
      final at = value.lastIndexOf('@');
      if (at <= 0) {
        _validateRepo(value, raw);
        return SourceSpec(type: SourceType.gh, identifier: value);
      }

      final repo = value.substring(0, at);
      final tag = value.substring(at + 1);
      _validateRepo(repo, raw);
      if (tag.isEmpty) {
        throw CliParseException('Invalid gh source "$raw".');
      }
      return SourceSpec(type: SourceType.gh, identifier: repo, version: tag);
    }

    throw CliParseException('Unsupported source "$raw". Use pub: or gh:.');
  }

  bool _looksLikeSourceSpec(String value) {
    return value.startsWith('pub:') || value.startsWith('gh:');
  }

  void _validateRepo(String repo, String raw) {
    final parts = repo.split('/');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      throw CliParseException(
        'Invalid gh source "$raw". Use gh:<owner>/<repo>.',
      );
    }
  }

  List<String> _extractCommandArgs(List<String> args) {
    if (args.isEmpty) {
      return const [];
    }
    if (args.first == '--') {
      return args.skip(1).toList(growable: false);
    }
    return args;
  }
}
