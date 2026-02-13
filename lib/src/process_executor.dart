import 'dart:io';

/// Process execution abstraction to simplify testing.
abstract interface class ProcessExecutor {
  /// Starts a process and returns the child exit code.
  Future<int> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell,
  });
}

/// [ProcessExecutor] implementation backed by `dart:io`.
final class IoProcessExecutor implements ProcessExecutor {
  const IoProcessExecutor();

  @override
  Future<int> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );

    final stdoutDone = stdout.addStream(process.stdout);
    final stderrDone = stderr.addStream(process.stderr);
    final exitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;
    return exitCode;
  }
}
