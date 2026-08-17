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
# Download sources: jsDelivr CDN by default (raw.githubusercontent.com
# returns OpenSSL SSL_ERROR_SYSCALL on some real NAS), with the public
# GitHub Raw repo as an automatic fallback — no manual env var required.
#
# Configuration (env overrides, all optional):
#   NAS_COMPANION_BASE_URL      base URL of the artifacts
#                               (default: jsDelivr CDN + GitHub Raw fallback)
#   NAS_COMPANION_INSTALL_DIR   install directory (default: $HOME/.nas-companion)
#   NAS_COMPANION_NO_LAUNCH=1   install but do not auto-launch the menu
#   NAS_COMPANION_KEEP_TMP=1    keep the temp dir (test hook only)
set -euo pipefail

JS_DELIVR_URL="https://cdn.jsdelivr.net/gh/w876499651-ctrl/nas-companion-downloads@main"
GITHUB_RAW_URL="https://raw.githubusercontent.com/w876499651-ctrl/nas-companion-downloads/main"

if [ -n "${NAS_COMPANION_BASE_URL:-}" ]; then
  # An explicit user override is used as-is, without extra fallbacks.
  BASE_URL="$NAS_COMPANION_BASE_URL"
  FALLBACK_URLS=()
else
  BASE_URL="$JS_DELIVR_URL"
  FALLBACK_URLS=("$GITHUB_RAW_URL")
fi
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

# fetch_any downloads a relative artifact from the primary base URL and,
# on failure, from each fallback source in order (GitHub Raw by default).
fetch_any() { # $1 relative path  $2 out
  local rel="$1" out="$2" url fb
  url="$BASE_URL/$rel"
  if fetch "$url" "$out"; then
    return 0
  fi
  for fb in "${FALLBACK_URLS[@]:-}"; do
    url="$fb/$rel"
    log "主下载源不可用（$BASE_URL），正在回退到备用源: $fb"
    if fetch "$url" "$out"; then
      return 0
    fi
  done
  die "下载失败: $rel（主源 $BASE_URL 与全部备用源均失败）。请检查 NAS 网络后重试。"
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

TMP="$(mktemp -d)"
# MSYS/Git Bash dev boxes mix a native Windows curl with GNU tar; give curl
# a Windows-native path when cygpath is available (no-op on real Linux).
if command -v cygpath >/dev/null 2>&1; then
  TMP_NATIVE="$(cygpath -w "$TMP")"
else
  TMP_NATIVE="$TMP"
fi
# NAS_COMPANION_KEEP_TMP=1 keeps the temp dir (explicit test hook for the
# automated install.sh verification; normal installs always clean up).
if [ "${NAS_COMPANION_KEEP_TMP:-0}" = "1" ]; then
  trap - EXIT
else
  trap 'rm -rf "$TMP"' EXIT
fi

log "下载 $tarball（主源 $BASE_URL）"
fetch_any "$tarball" "$TMP_NATIVE/$tarball"
log "下载 SHA256SUMS"
fetch_any "SHA256SUMS" "$TMP_NATIVE/SHA256SUMS"

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
# `curl ... | bash` leaves the exec'd installer with the (already-consumed)
# curl pipe as stdin, so it would look like a non-interactive run and fail.
# Reconnect the controlling terminal when present: one single command then
# goes straight into the interactive menu (no second command needed). When
# /dev/tty exists but cannot be opened (rare headless run), fall back to a
# plain exec so the install is not aborted by the redirect.
if [ -r /dev/tty ] && [ -w /dev/tty ] && exec ./bin/nas-installer < /dev/tty 2>/dev/null; then
  :
fi
exec ./bin/nas-installer
