import 'package:drx/src/errors.dart';
import 'package:test/test.dart';

void main() {
  test('DrxException has readable toString', () {
    const error = DrxException('boom', exitCode: 7);
    expect(error.toString(), 'DrxException(7): boom');
  });

  test('CliParseException has readable toString', () {
    const error = CliParseException('bad input');
    expect(error.toString(), 'CliParseException: bad input');
  });
}
