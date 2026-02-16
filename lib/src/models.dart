/// Supported command sources.
enum SourceType { pub, gh }

/// Runtime strategy for pub executables.
enum RuntimeMode { auto, jit, aot }

/// Strategy for resolving `gh:` sources.
enum GhMode { binary, source, auto }

/// Parsed source selector and optional version/tag.
final class SourceSpec {
  const SourceSpec({
    required this.type,
    required this.identifier,
    this.version,
  });

  final SourceType type;
  final String identifier;
  final String? version;
}

/// Normalized execution request returned by the CLI parser.
final class CommandRequest {
  const CommandRequest({
    required this.source,
    required this.command,
    required this.args,
    required this.runtime,
    required this.refresh,
    required this.isolated,
    required this.allowUnsigned,
    required this.verbose,
    this.ghMode = GhMode.binary,
    this.gitPath,
    this.asset,
  });

  final SourceSpec source;
  final String command;
  final List<String> args;
  final RuntimeMode runtime;
  final bool refresh;
  final bool isolated;
  final bool allowUnsigned;
  final bool verbose;
  final GhMode ghMode;
  final String? gitPath;
  final String? asset;
}

/// Top-level parser result.
final class ParsedCli {
  const ParsedCli({
    required this.showHelp,
    required this.showVersion,
    this.request,
  });

  final bool showHelp;
  final bool showVersion;
  final CommandRequest? request;
}
