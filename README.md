# drx

`drx` is a Dart-first `npx`/`uvx`-style tool runner.

- `pub` source: runs Dart package executables.
- `gh` source: runs precompiled binaries from public GitHub Releases.
  (language-agnostic: Go/Rust/C/C++/etc. all work)

## Command Forms

Default source is `pub`:

```bash
drx <package[@version]> [--] [args...]
drx <package:executable[@version]> [--] [args...]
```

Explicit source:

```bash
drx --from pub:<package[@version]> <command> [--] [args...]
drx --from gh:<owner>/<repo[@tag]> <command> [--] [args...]
drx cache [list|clean|prune] [--json]
drx versions <package|pub:pkg|gh:owner/repo> [--limit N] [--json]
```

Examples:

```bash
drx melos -- --version
drx mason_cli:mason -- --help
drx --from pub:very_good_cli very_good -- --help
drx --from gh:cli/cli@v2.70.0 gh -- version
drx --from gh:BurntSushi/ripgrep rg -- --version
drx --from gh:junegunn/fzf fzf -- --version
drx --from gh:charmbracelet/gum gum -- --version
drx --allow-unsigned --from gh:sharkdp/fd fd -- --version
drx --allow-unsigned --from gh:sharkdp/bat bat -- --version
drx --allow-unsigned --from gh:dandavison/delta delta -- --version
drx versions melos --limit 5
drx versions gh:cli/cli --limit 10
drx cache list
drx cache prune --max-age-days 30 --max-size-mb 2048
```

Note: some repositories do not publish checksums. Those require
`--allow-unsigned` as shown above.

## Cross-Platform Support

- Linux: `x64`, `arm64`
- macOS: `x64` (Intel), `arm64` (Apple Silicon)
- Windows: `x64`, `arm64`

`drx` handles Windows executable resolution (`.exe`, `.cmd`, `.bat`) and
Unix executable permissions for downloaded binaries.

## Flags

- `--runtime auto|jit|aot`: runtime mode for pub executables.
- `--refresh`: refresh cached artifacts.
- `--isolated`: use temporary, non-persistent caches.
- `--asset <name>`: force a specific GitHub asset name.
- `--allow-unsigned`: allow GH assets without checksum manifests.
- `--json`: machine-readable output for `cache` and `versions`.
- `--verbose`: enable verbose logging (currently minimal).

## Cache And Version Commands

- `drx cache list`: show cache location, entry counts, and size.
- `drx cache clean`: remove all cached artifacts and lock files.
- `drx cache prune`: remove old cache entries and optionally enforce size limits.
  - `--max-age-days N`: remove entries older than N days (default: 30 for prune).
  - `--max-size-mb N`: keep cache under N MB by removing oldest entries.
  - `--json`: output prune/list/clean results as JSON.
- `drx versions <target>`: list available versions from pub.dev or GH releases.
  - falls back to repository tags when GH releases are not present.
  - `--json`: output version list as JSON.
  - pub targets: `melos`, `pub:melos`, `mason_cli:mason`
  - gh targets: `gh:cli/cli`

## Runtime Behavior

- `jit`: uses `dart run package:executable`.
- `aot`: compiles with `dart compile exe` and runs cached native output.
- `auto`: prefers AOT, falls back to JIT when AOT is unsupported or fails.

`package:cli_launcher` wrappers (for example, recent `melos`) are not compatible
with reliable AOT execution in this model. In `auto` mode, drx falls back to JIT.

When run without arguments, `drx` shows the help screen.

Global flags can be placed before utility commands, for example:

```bash
drx --json versions gh:cli/cli
drx --verbose cache list
```

## Security Policy

- GH asset checksum verification is required by default.
- If no checksum manifest is present, execution is blocked.
- `--allow-unsigned` explicitly bypasses that block.

## Make Your Tool drx-Compatible

See the maintainer guide:
[`doc/compatibility.md`](https://github.com/leehack/drx/blob/main/doc/compatibility.md).

It covers:

- pub.dev executable compatibility requirements
- GitHub Releases binary compatibility requirements
- checksum formats and naming conventions
- validation commands for both `pub` and `gh` sources

## Publish To pub.dev

Dry-run validation:

```bash
dart pub publish --dry-run
```

Publish:

```bash
dart pub publish
```

`drx` is intended as the publish name on pub.dev.

## Install With Dart SDK (pub.dev)

Install globally with pub:

```bash
dart pub global activate drx
```

Install a specific version:

```bash
dart pub global activate drx 0.3.0
```

Run it:

```bash
drx --version
```

If your PATH is not configured for pub global executables:

```bash
dart pub global run drx:drx --version
```

Uninstall:

```bash
dart pub global deactivate drx
```

## Install Without Dart SDK (Binary Options)

For users without Dart installed, publish precompiled binaries in GitHub
Releases and provide platform-specific one-liner installers.

Recommended options:

1. `curl | sh` installer for Linux/macOS
2. PowerShell installer for Windows
3. Package managers (Homebrew tap, Scoop, winget, apt/rpm) as follow-ups

Typical one-liner patterns:

```bash
# Linux/macOS
curl -fsSL "https://raw.githubusercontent.com/leehack/drx/main/tool/install.sh" | DRX_REPO=leehack/drx sh
```

```powershell
# Windows PowerShell
$env:DRX_REPO = "leehack/drx"
iwr "https://raw.githubusercontent.com/leehack/drx/main/tool/install.ps1" -UseBasicParsing | iex
```

Install scripts download and verify the matching `.sha256` checksum before
installing binaries.

The repository includes ready workflows for CI and binary release publishing:

- `.github/workflows/ci.yml`
- `.github/workflows/installer-smoke.yml`
- `.github/workflows/release-binaries.yml`

`release-binaries.yml` runs on pushed tags (`v*`) and also supports manual
dispatch with a required `tag` input.

`installer-smoke.yml` validates one-liner install scripts on Linux/macOS/Windows
across `x64` and `arm64` runners.

## Development

```bash
dart pub get
dart analyze
dart test
```

### Coverage

```bash
dart test --coverage=coverage
dart run coverage:format_coverage --packages=.dart_tool/package_config.json --report-on=lib --in=coverage --out=coverage/lcov.info --lcov --fail-under=80
dart run tool/check_coverage.dart 80 coverage/lcov.info
```

The repository enforces 80%+ line coverage for `lib/`.
