import 'dart:ffi';

import 'package:drx/src/errors.dart';
import 'package:drx/src/platform_info.dart';
import 'package:test/test.dart';

void main() {
  group('HostPlatform normalization', () {
    test('normalizes known OS names', () {
      expect(HostPlatform.normalizeOs('linux'), 'linux');
      expect(HostPlatform.normalizeOs('macos'), 'macos');
      expect(HostPlatform.normalizeOs('windows'), 'windows');
    });

    test('throws on unsupported OS', () {
      expect(
        () => HostPlatform.normalizeOs('android'),
        throwsA(isA<DrxException>()),
      );
      expect(
        () => HostPlatform.normalizeOs('weird-os'),
        throwsA(isA<DrxException>()),
      );
    });

    test('normalizes arch from Abi', () {
      expect(HostPlatform.normalizeArch(Abi.linuxX64), 'x64');
      expect(HostPlatform.normalizeArch(Abi.macosArm64), 'arm64');
      expect(HostPlatform.normalizeArch(Abi.windowsIA32), 'x86');
    });
  });
}
