# drx Compatibility Guide for Tool Maintainers

This guide explains how to make your tool runnable through `drx`.

`drx` supports two source types:

- `pub` for Dart package executables
- `gh` for precompiled binaries from public GitHub Releases

## pub.dev Compatibility

Use this path for users with Dart SDK installed.

### Requirements

1. Publish a Dart package to pub.dev.
2. Expose at least one executable in `pubspec.yaml`.
3. Provide the executable entrypoint in `bin/<script>.dart`.
4. Ensure the executable runs with `dart run package:executable`.

### Minimal layout

```text
my_tool/
  bin/
    my_tool.dart
  lib/
    ...
  pubspec.yaml
```

### `pubspec.yaml` example

```yaml
name: my_tool
executables:
  my_tool: my_tool
```

### Entrypoint example

```dart
// bin/my_tool.dart
Future<void> main(List<String> args) async {
  // your CLI logic
}
```

### Validation

```bash
dart run my_tool:my_tool -- --version
drx my_tool -- --version
drx my_tool@1.2.3 -- --version
```

### AOT compatibility note

If you want reliable `drx --runtime aot` support, avoid wrappers that depend on
global-activation-specific runtime state. Some `package:cli_launcher` patterns
can fail under direct AOT execution.

## GitHub Releases Compatibility

Use this path for users without Dart SDK.

This source is language-agnostic. Your executable can be built from any stack
(for example Go, Rust, C/C++, Zig, or .NET native AOT) as long as release
assets match platform/arch naming and include checksums.

### Requirements

1. Publish binaries on GitHub Releases.
2. Ship platform-specific assets for Linux/macOS/Windows.
3. Provide checksum metadata (`SHA256SUMS`, `checksums.txt`, or `*.sha256`).
4. Use recognizable OS/arch tokens in asset names.

### Recommended asset naming

- OS tokens: `linux`, `macos` (or `darwin`), `windows`
- Arch tokens: `x64`/`x86_64`/`amd64`, `arm64`/`aarch64`

Examples:

- `my_tool-linux-x64.tar.gz`
- `my_tool-macos-arm64.tar.gz`
- `my_tool-windows-x64.exe`

### Supported formats in drx

- raw binary (`.exe` on Windows)
- `.zip`
- `.tar.gz` / `.tgz`

### Checksum formats accepted

`drx` accepts common checksum line styles, including:

- `<sha256>  <asset-name>`
- `<asset-name>: <sha256>`

Example `SHA256SUMS`:

```text
4d6fd9cdf2156dc5f1886527b3f5838ea7f21295f7ad8c9f92634fce2f1213f9  my_tool-linux-x64.tar.gz
8f434346648f6b96df89dda901c5176b10a6d83961f7300a0f88a0f51f35dfa5  my_tool-windows-x64.exe
```

### Validation

```bash
drx --from gh:<owner>/<repo>@v1.2.3 <command> -- --version
drx --from gh:<owner>/<repo>@v1.2.3 <command> --asset <asset-name> -- --version
```

Real-world examples:

```bash
drx --from gh:cli/cli gh -- version
drx --from gh:BurntSushi/ripgrep rg -- --version
drx --from gh:sharkdp/fd fd -- --version
drx --from gh:sharkdp/bat bat -- --version
drx --from gh:dandavison/delta delta -- --version
drx --from gh:jqlang/jq jq -- --version
drx --from gh:charmbracelet/gum gum -- --version
```

### Security behavior

- Unsigned assets are blocked by default.
- Users can bypass with `--allow-unsigned`.
- Best practice is to always publish checksums and keep assets deterministic.

## Quick Checklist

- pub path:
  - `executables` configured
  - `bin/` entrypoint works with `dart run`
- gh path:
  - cross-platform assets uploaded
  - checksums uploaded
  - naming includes OS/arch tokens
- verify with both `drx <package>` and `drx --from gh:...`
