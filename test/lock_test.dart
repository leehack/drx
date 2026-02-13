import 'dart:io';

import 'package:drx/src/lock.dart';
import 'package:test/test.dart';

void main() {
  test('withFileLock runs action and returns result', () async {
    final temp = await Directory.systemTemp.createTemp('drx_lock_test_');
    addTearDown(() => temp.delete(recursive: true));

    final lockFile = File('${temp.path}/example.lock');
    final value = await withFileLock(lockFile, () async => 42);

    expect(value, 42);
    expect(await lockFile.exists(), isTrue);
  });
}
