import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Computes a lowercase SHA-256 digest for [bytes].
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Parses common checksum manifest formats into `{assetName: sha256}`.
Map<String, String> parseChecksumManifest(String content) {
  final checksums = <String, String>{};
  final lines = content.split('\n');
  final hashThenFile = RegExp(r'^([a-fA-F0-9]{64})\s+[* ]?(.+)$');
  final fileThenHash = RegExp(r'^(.+):\s*([a-fA-F0-9]{64})$');

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }

    final hashMatch = hashThenFile.firstMatch(line);
    if (hashMatch != null) {
      final hash = hashMatch.group(1)!.toLowerCase();
      final file = hashMatch.group(2)!.trim();
      checksums[file] = hash;
      checksums[p.basename(file)] = hash;
      continue;
    }

    final fileMatch = fileThenHash.firstMatch(line);
    if (fileMatch != null) {
      final file = fileMatch.group(1)!.trim();
      final hash = fileMatch.group(2)!.toLowerCase();
      checksums[file] = hash;
      checksums[p.basename(file)] = hash;
    }
  }

  return checksums;
}

/// Verifies a downloaded asset against a parsed checksum manifest.
bool verifyAssetChecksum({
  required String assetName,
  required List<int> bytes,
  required Map<String, String> checksums,
}) {
  final expected = checksums[assetName] ?? checksums[p.basename(assetName)];
  if (expected == null) {
    return false;
  }
  return sha256Hex(bytes).toLowerCase() == expected.toLowerCase();
}
