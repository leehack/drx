# drx

`drx` runs CLI tools on demand, similar to `npx` / `uvx`.

- Use `pub.dev` packages when Dart SDK is available.
- Use GitHub release binaries when Dart SDK is not available.

## Install

### With Dart SDK (pub.dev)

```bash
dart pub global activate drx
drx --version
```

If PATH is not set for pub executables:

```bash
dart pub global run drx:drx --version
```

### Without Dart SDK (precompiled binary)

Linux / macOS:

```bash
curl -fsSL "https://raw.githubusercontent.com/leehack/drx/main/tool/install.sh" | DRX_REPO=leehack/drx sh
```

Windows (PowerShell):

```powershell
$env:DRX_REPO = "leehack/drx"
iwr "https://raw.githubusercontent.com/leehack/drx/main/tool/install.ps1" -UseBasicParsing | iex
```

Both installers verify checksums before installing.

## Quick Usage

Default source is `pub`:

```bash
drx <package[@version]> [--] [args...]
drx <package:executable[@version]> [--] [args...]
```

Explicit source selection:

```bash
drx --from pub:<package[@version]> <command> [--] [args...]
drx --from gh:<owner>/<repo[@tag]> <command> [--] [args...]
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

# Some repos do not publish checksums:
drx --allow-unsigned --from gh:sharkdp/fd fd -- --version
```

## Useful Commands

```bash
drx cache list
drx cache clean
drx cache prune --max-age-days 30 --max-size-mb 2048

drx versions melos --limit 5
drx versions gh:cli/cli --limit 10

drx --json versions gh:cli/cli
drx --json cache list
```

## Runtime Modes (pub source)

- `--runtime auto` (default): prefer AOT, fallback to JIT
- `--runtime jit`: `dart run`
- `--runtime aot`: compile and run native executable

## Security Defaults

- GitHub assets require checksum verification by default.
- Unsigned assets are blocked unless you pass `--allow-unsigned`.

## Platform Support

- Linux: `x64`, `arm64`
- macOS: `x64` (Intel), `arm64` (Apple Silicon)
- Windows: `x64`, `arm64`

## More Docs

- Tool maintainer compatibility guide: [`doc/compatibility.md`](https://github.com/leehack/drx/blob/main/doc/compatibility.md)
- Project maintenance / release notes: [`doc/maintainers.md`](https://github.com/leehack/drx/blob/main/doc/maintainers.md)
