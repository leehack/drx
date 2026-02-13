import 'dart:io';

/// Fails with exit code 1 when line coverage is below a threshold.
///
/// Usage:
/// `dart run tool/check_coverage.dart [threshold] [reportPath]`
void main(List<String> args) {
  final threshold = args.isEmpty ? 80.0 : double.parse(args.first);
  final reportPath = args.length > 1 ? args[1] : 'coverage/lcov.info';

  final file = File(reportPath);
  if (!file.existsSync()) {
    stderr.writeln('Coverage report not found: $reportPath');
    exit(2);
  }

  final prettyLinePattern = RegExp(r'^\s*(\d+)\|');
  final lcovLinePattern = RegExp(r'^DA:(\d+),(\d+)$');
  var total = 0;
  var hit = 0;

  for (final line in file.readAsLinesSync()) {
    final lcovMatch = lcovLinePattern.firstMatch(line);
    if (lcovMatch != null) {
      total++;
      if (int.parse(lcovMatch.group(2)!) > 0) {
        hit++;
      }
      continue;
    }

    final prettyMatch = prettyLinePattern.firstMatch(line);
    if (prettyMatch != null) {
      total++;
      if (int.parse(prettyMatch.group(1)!) > 0) {
        hit++;
      }
    }
  }

  if (total == 0) {
    stderr.writeln('No instrumented lines found in $reportPath');
    exit(2);
  }

  final coverage = hit / total * 100;
  stdout.writeln('Coverage: ${coverage.toStringAsFixed(2)}% ($hit/$total)');

  if (coverage < threshold) {
    stderr.writeln(
      'Coverage threshold not met: ${coverage.toStringAsFixed(2)}% < ${threshold.toStringAsFixed(2)}%',
    );
    exit(1);
  }
}
