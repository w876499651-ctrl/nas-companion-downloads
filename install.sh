#!/usr/bin/env bash
# Nas Companion V2 — one-line NAS installer.
#
#   curl -fsSL <BASE_URL>/install.sh | bash
#
# Automatically: detects the Linux architecture, downloads the matching
# Nas Companion package, verifies its SHA-256 checksum, extracts it, and
# launches the nas-installer which enters the Xiaoya-style install menu.
# No Git clone, no Go toolchain, no manual compilation.
#
# Configuration (env overrides, all optional):
#   NAS_COMPANION_BASE_URL      base URL of the artifacts
#                               (default: public delivery repo)
#   NAS_COMPANION_INSTALL_DIR   install directory (default: $HOME/.nas-companion)
#   NAS_COMPANION_NO_LAUNCH=1   install but do not auto-launch the menu
set -euo pipefail

BASE_URL="${NAS_COMPANION_BASE_URL:-https://raw.githubusercontent.com/w876499651-ctrl/nas-companion-downloads/main}"
INSTALL_DIR="${NAS_COMPANION_INSTALL_DIR:-$HOME/.nas-companion}"

log() { printf '\033[1;32m[NasCompanion]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[NasCompanion] 错误:\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. OS / architecture detection -------------------------------------
detect_os_arch() {
  local os machine
  os="$(uname -s)"
  [ "$os" = "Linux" ] || die "仅支持 Linux（当前: $os）。"
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64|x64) ARCH="amd64" ;;
    aarch64|arm64)    ARCH="arm64" ;;
    *) die "不支持的架构 $machine（支持 amd64 / arm64）。" ;;
  esac
  log "检测到 Linux / $machine -> 使用 $ARCH 安装包"
}

# --- 2. download ---------------------------------------------------------
fetch() { # $1 url  $2 out
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    die "需要 curl 或 wget 才能下载。"
  fi
}

# --- 3. SHA-256 verification ---------------------------------------------
sha256_of() { # $1 file -> hex
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "需要 sha256sum 或 shasum 进行校验。"
  fi
}

verify_checksum() { # $1 tarball  $2 sumsfile
  local name want got
  name="$(basename "$1")"
  # SHA256SUMS lines are "<hash>  <name>" or "<hash> *<name>" (GNU binary
  # marker) — accept both.
  want="$(awk -v n="$name" '{if ($2 == n || $2 == "*" n) {print $1; exit}}' "$2")"
  [ -n "$want" ] || die "SHA256SUMS 中找不到 $name 的校验值。"
  got="$(sha256_of "$1")"
  if [ "$got" != "$want" ]; then
    die "SHA-256 校验失败（期望 $want，实际 $got）。已中止安装，未写入任何文件。"
  fi
  log "SHA-256 校验通过（$want）"
}

# --- main ----------------------------------------------------------------
detect_os_arch

tarball="nas-companion-linux-${ARCH}.tar.gz"
url="$BASE_URL/$tarball"
sums_url="$BASE_URL/SHA256SUMS"

TMP="$(mktemp -d)"
# MSYS/Git Bash dev boxes mix a native Windows curl with GNU tar; give curl
# a Windows-native path when cygpath is available (no-op on real Linux).
if command -v cygpath >/dev/null 2>&1; then
  TMP_NATIVE="$(cygpath -w "$TMP")"
else
  TMP_NATIVE="$TMP"
fi
trap 'rm -rf "$TMP"' EXIT

log "下载 $url"
fetch "$url" "$TMP_NATIVE/$tarball"
log "下载 $sums_url"
fetch "$sums_url" "$TMP_NATIVE/SHA256SUMS"

# Verification/extraction use the native (non-backslash) path so sha256sum
# and tar never escape the file name.
verify_checksum "$TMP/$tarball" "$TMP/SHA256SUMS"

mkdir -p "$INSTALL_DIR"
log "解压到 $INSTALL_DIR"
tar -xzf "$TMP/$tarball" -C "$INSTALL_DIR" --strip-components=1

# Guarantee the exec bit regardless of the mode recorded in the tarball
# (a tarball packed on a platform without POSIX mode bits may carry 0644).
chmod +x "$INSTALL_DIR/bin/nas-installer" 2>/dev/null || true
[ -x "$INSTALL_DIR/bin/nas-installer" ] || die "安装包缺少可执行文件 bin/nas-installer。"
[ -f "$INSTALL_DIR/hub/Dockerfile" ] || die "安装包缺少 Hub 构建上下文 hub/（无法本地构建 V2 Hub）。"

log "安装完成。启动器: $INSTALL_DIR/bin/nas-installer"
if [ "${NAS_COMPANION_NO_LAUNCH:-0}" = "1" ]; then
  log "未自动启动（NAS_COMPANION_NO_LAUNCH=1）。可手动运行: $INSTALL_DIR/bin/nas-installer"
  exit 0
fi
cd "$INSTALL_DIR"
exec ./bin/nas-installer
