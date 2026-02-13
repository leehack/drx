## 0.3.0

- Rename package and CLI naming to `drx`.
- Prepare package for publication with license metadata and docs cleanup.
- Add pub metadata links and executable mapping for publish readiness.
- Simplify CLI surface by removing unused reserved flags.
- Improve runtime logging for `--verbose` and reduce internal duplication.
- Default to pub source for unprefixed package commands.
- Add cross-platform binary release workflow and checksum-verifying installers.
- Add `drx cache list|clean` and `drx versions` utility commands.
- Show help output when `drx` runs without arguments.
- Expand docs with GH binary examples and compatibility guidance.
- Add `drx cache prune` with age/size controls.
- Add `--json` output mode for cache and versions commands.
- Support global utility flags before command verbs (for example `--json versions`).
- Add GH version-list fallback to repository tags when releases are absent.
- Add one-liner installer smoke tests across Linux/macOS/Windows.
- Expand binary build matrix to include Intel macOS and ARM Linux/Windows.

## 0.1.0

- Add `drx` CLI with `pub` and `gh` source parsing.
- Implement pub execution with `jit`, `aot`, and `auto` fallback behavior.
- Implement GitHub Releases binary execution with checksum enforcement.
- Add cache path management, locking, and full unit test suite.
