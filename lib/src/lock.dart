import 'dart:io';

/// Executes [action] while holding an exclusive lock on [lockFile].
Future<T> withFileLock<T>(File lockFile, Future<T> Function() action) async {
  await lockFile.parent.create(recursive: true);
  final raf = lockFile.openSync(mode: FileMode.write);
  try {
    raf.lockSync(FileLock.exclusive);
    return await action();
  } finally {
    raf.unlockSync();
    raf.closeSync();
  }
}
