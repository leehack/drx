import 'dart:io';

import 'package:drx/drx.dart';

/// drx CLI entrypoint.
Future<void> main(List<String> arguments) async {
  final engine = DrxEngine();
  final code = await engine.run(arguments);
  exit(code);
}
