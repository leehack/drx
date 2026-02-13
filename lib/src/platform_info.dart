import 'dart:ffi';
import 'dart:io';

import 'errors.dart';

/// Normalized host OS and architecture used by drx runners.
final class HostPlatform {
  const HostPlatform({required this.os, required this.arch});

  final String os;
  final String arch;

  /// Whether the current host OS is Windows.
  bool get isWindows => os == 'windows';

  /// Detects and normalizes the current runtime platform.
  static HostPlatform detect() {
    return HostPlatform(
      os: normalizeOs(Platform.operatingSystem),
      arch: normalizeArch(Abi.current()),
    );
  }

  /// Normalizes Dart OS identifiers into drx values.
  static String normalizeOs(String value) {
    switch (value) {
      case 'macos':
      case 'linux':
      case 'windows':
        return value;
      case 'ios':
      case 'android':
      case 'fuchsia':
        throw DrxException('Unsupported host OS: $value.');
      default:
        throw DrxException('Unknown host OS: $value.');
    }
  }

  /// Normalizes Dart ABI values into common architecture strings.
  static String normalizeArch(Abi abi) {
    switch (abi) {
      case Abi.linuxX64:
      case Abi.macosX64:
      case Abi.windowsX64:
        return 'x64';
      case Abi.linuxArm64:
      case Abi.macosArm64:
      case Abi.windowsArm64:
      case Abi.androidArm64:
      case Abi.iosArm64:
        return 'arm64';
      case Abi.linuxIA32:
      case Abi.windowsIA32:
      case Abi.androidIA32:
        return 'x86';
      default:
        throw DrxException('Unsupported host architecture: $abi.');
    }
  }
}
