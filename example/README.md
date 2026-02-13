# drx CLI example

Install from pub.dev:

```sh
dart pub global activate drx
```

Use `drx` to run tools from pub.dev (default source):

```sh
drx melos -- --version
drx mason_cli:mason -- --help
```

Use `drx` with explicit sources:

```sh
drx --from pub:very_good_cli very_good -- --help
drx --from gh:cli/cli@v2.70.0 gh -- version
drx --from gh:BurntSushi/ripgrep rg -- --version
drx --from gh:junegunn/fzf fzf -- --version
drx --from gh:charmbracelet/gum gum -- --version
drx --allow-unsigned --from gh:sharkdp/fd fd -- --version
```

Use runtime controls for pub tools:

```sh
drx --runtime jit melos -- --version
drx --runtime auto melos -- --version
```

Inspect and manage cache:

```sh
drx cache list
drx cache prune --max-age-days 30 --max-size-mb 2048
```

List available versions:

```sh
drx versions melos --limit 5
drx versions gh:cli/cli --limit 10
drx --json versions gh:cli/cli --limit 3
```
