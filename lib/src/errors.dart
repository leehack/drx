/// Runtime error with an explicit process exit code.
final class DrxException implements Exception {
  const DrxException(this.message, {this.exitCode = 1});

  final String message;
  final int exitCode;

  @override
  String toString() => 'DrxException($exitCode): $message';
}

/// Argument parsing error from the CLI layer.
final class CliParseException implements Exception {
  const CliParseException(this.message);

  final String message;

  @override
  String toString() => 'CliParseException: $message';
}
