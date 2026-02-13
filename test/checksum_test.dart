import 'package:drx/src/checksum.dart';
import 'package:test/test.dart';

void main() {
  group('checksum parsing and verification', () {
    test('parses hash-first manifest lines', () {
      final checksums = parseChecksumManifest('''
8f434346648f6b96df89dda901c5176b10a6d83961f7300a0f88a0f51f35dfa5  tool-linux-x64.tar.gz
''');

      expect(
        checksums['tool-linux-x64.tar.gz'],
        '8f434346648f6b96df89dda901c5176b10a6d83961f7300a0f88a0f51f35dfa5',
      );
    });

    test('parses file-first manifest lines', () {
      final checksums = parseChecksumManifest('''
tool.zip: 4d6fd9cdf2156dc5f1886527b3f5838ea7f21295f7ad8c9f92634fce2f1213f9
''');

      expect(
        checksums['tool.zip'],
        '4d6fd9cdf2156dc5f1886527b3f5838ea7f21295f7ad8c9f92634fce2f1213f9',
      );
    });

    test('verifies checksum using basename match', () {
      final bytes = 'hello'.codeUnits;
      final hash = sha256Hex(bytes);
      final checksums = {'nested/path/tool': hash, 'tool': hash};

      final ok = verifyAssetChecksum(
        assetName: 'tool',
        bytes: bytes,
        checksums: checksums,
      );
      expect(ok, isTrue);
    });

    test('fails verification when asset checksum is missing', () {
      final ok = verifyAssetChecksum(
        assetName: 'tool',
        bytes: 'hello'.codeUnits,
        checksums: const {},
      );
      expect(ok, isFalse);
    });
  });
}
