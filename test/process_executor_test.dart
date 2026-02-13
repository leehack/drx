import 'dart:io';

import 'package:drx/src/process_executor.dart';
import 'package:test/test.dart';

void main() {
  test('IoProcessExecutor runs command and returns exit code', () async {
    const executor = IoProcessExecutor();
    final code = await executor.run('dart', const [
      '--version',
    ], runInShell: Platform.isWindows);
    expect(code, 0);
  });
}
