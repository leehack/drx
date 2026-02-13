#!/usr/bin/env sh
set -eu

REPO="${DRX_REPO:-}"
VERSION="latest"
INSTALL_DIR="${DRX_INSTALL_DIR:-$HOME/.local/bin}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -r|--repo)
      REPO="$2"
      shift 2
      ;;
    -v|--version)
      VERSION="$2"
      shift 2
      ;;
    -d|--dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$REPO" ]; then
  cat >&2 <<'EOF'
DRX_REPO is not set.
Usage:
  DRX_REPO=<owner>/<repo> sh install.sh
or
  sh install.sh --repo <owner>/<repo>
EOF
  exit 2
fi

OS_RAW="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH_RAW="$(uname -m | tr '[:upper:]' '[:lower:]')"

case "$OS_RAW" in
  linux*) OS="linux" ;;
  darwin*) OS="macos" ;;
  *)
    echo "Unsupported OS: $OS_RAW" >&2
    exit 1
    ;;
esac

case "$ARCH_RAW" in
  x86_64|amd64) ARCH="x64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *)
    echo "Unsupported architecture: $ARCH_RAW" >&2
    exit 1
    ;;
esac

ASSET="drx-${OS}-${ARCH}"

if [ "$VERSION" = "latest" ]; then
  URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"
else
  URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
fi
CHECKSUM_URL="${URL}.sha256"

TMP_FILE="$(mktemp)"
TMP_SUM="$(mktemp)"
trap 'rm -f "$TMP_FILE" "$TMP_SUM"' EXIT INT TERM

echo "Downloading ${URL}"
curl -fsSL "$URL" -o "$TMP_FILE"

echo "Downloading ${CHECKSUM_URL}"
curl -fsSL "$CHECKSUM_URL" -o "$TMP_SUM"

EXPECTED_HASH="$(awk 'NF { print $1; exit }' "$TMP_SUM")"
EXPECTED_HASH="$(printf '%s' "$EXPECTED_HASH" | tr '[:upper:]' '[:lower:]')"

if [ -z "$EXPECTED_HASH" ]; then
  echo "Could not parse checksum file: ${CHECKSUM_URL}" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_HASH="$(sha256sum "$TMP_FILE" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  ACTUAL_HASH="$(shasum -a 256 "$TMP_FILE" | awk '{print $1}')"
elif command -v openssl >/dev/null 2>&1; then
  ACTUAL_HASH="$(openssl dgst -sha256 "$TMP_FILE" | awk '{print $NF}')"
else
  echo "No SHA-256 tool found (sha256sum/shasum/openssl)." >&2
  exit 1
fi

ACTUAL_HASH="$(printf '%s' "$ACTUAL_HASH" | tr '[:upper:]' '[:lower:]')"

if [ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
  echo "Checksum verification failed for ${ASSET}" >&2
  echo "Expected: $EXPECTED_HASH" >&2
  echo "Actual:   $ACTUAL_HASH" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
TARGET="${INSTALL_DIR}/drx"
install "$TMP_FILE" "$TARGET"
chmod +x "$TARGET"

echo "Installed drx to ${TARGET}"
echo "Run: ${TARGET} --version"
