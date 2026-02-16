# drx Maintainer Guide

This document is for project maintainers and contributors.

## Local Development

```bash
dart pub get
dart analyze
dart test
```

Coverage check:

```bash
dart test --coverage=coverage
dart run coverage:format_coverage --packages=.dart_tool/package_config.json --report-on=lib --in=coverage --out=coverage/lcov.info --lcov --fail-under=80
dart run tool/check_coverage.dart 80 coverage/lcov.info
```

## CI and Release Workflows

- `/.github/workflows/ci.yml`
  - analyze + tests on Linux/macOS/Windows (`x64`, `arm64`) and coverage gate.
  - includes GH mode/runtime integration matrix coverage (`test/gh_integration_test.dart`).
- `/.github/workflows/installer-smoke.yml`
  - validates one-liner install scripts on Linux/macOS/Windows (`x64`, `arm64`).
- `/.github/workflows/live-gh-smoke.yml`
  - manual live-network smoke tests against real GitHub repos.
- `/.github/workflows/publish-pubdev.yml`
  - publishes to pub.dev when a tag like `vX.Y.Z` is pushed.
- `/.github/workflows/release-binaries.yml`
  - builds and uploads release binaries/checksums for `v*` tags.

## pub.dev Trusted Publishing Setup

Configure once on pub.dev package admin page:

1. Enable **Automated publishing from GitHub Actions**.
2. Repository: `leehack/drx`.
3. Tag pattern: `v{{version}}`.

No `PUB_TOKEN` is required when trusted publishing is configured correctly.

## Release Checklist

1. Update version in:
   - `pubspec.yaml`
   - `lib/src/engine.dart`
2. Add release notes to `CHANGELOG.md`.
3. Validate:
   - `dart analyze`
   - `dart test`
   - `dart pub publish --dry-run`
4. Commit and push `main`.
5. Create and push tag:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

Tag push triggers:

- pub.dev publish (`publish-pubdev.yml`)
- binary release (`release-binaries.yml`)

## Manual Binary Rebuild for Existing Tag

Use workflow dispatch on `Release Binaries` with input tag, for example `v0.3.1`.

This is useful if a previous binary job failed and source code fixes were applied
without changing the package version.

## Installer Smoke Testing Notes

- Installer scripts support `DRX_DOWNLOAD_BASE` override for local/test payloads.
- This is used by installer smoke workflow to test the one-liner flow end-to-end
  without depending on external GitHub release artifacts.

## Live GitHub Smoke Tests

- `test/gh_live_smoke_test.dart` is disabled by default and only runs when
  `DRX_ENABLE_LIVE_GH_TESTS=1`.
- Run locally:

```bash
DRX_ENABLE_LIVE_GH_TESTS=1 dart test test/gh_live_smoke_test.dart
```
