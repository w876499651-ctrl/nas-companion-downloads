#!/usr/bin/env bash
# Nas Companion V2 - one-line NAS installer.
#
#   curl -fsSL https://cdn.jsdelivr.net/gh/w876499651-ctrl/nas-companion-downloads@v2.0.1/install.sh | bash
#
# Automatically: detects the Linux architecture, downloads the matching
# Nas Companion package, verifies its SHA-256 checksum, extracts it, and
# launches the nas-installer which enters the interactive install menu.
# No Git clone, no Go toolchain, no manual compilation.
#
# --- Immutable artifact ref (critical for delivery consistency) ---
# ALL artifacts (tarball + SHA256SUMS) are downloaded from the SAME
# immutable git tag defined by ARTIFACT_REF. This prevents the jsDelivr
# @main mixed-cache problem where a new SHA256SUMS could be paired with
# an old tarball from a different commit. Every download channel
# (primary and fallbacks) uses this exact same ref - switching from
# primary to fallback can never mix versions.
#
# Download channels (all use the same ARTIFACT_REF):
#   1. cdn.jsdelivr.net       - jsDelivr anycast CDN (primary)
#   2. gcore.jsdelivr.net     - jsDelivr G-Core backend (trusted second
#                               channel; different CDN provider, bypasses
#                               anycast routing issues on some NAS)
#   3. raw.githubusercontent.com - GitHub Raw (last resort; known
#                               unstable on some NAS with OpenSSL
#                               SSL_ERROR_SYSCALL, but safe with immutable ref)
#
# Configuration (env overrides, all optional):
#   NAS_COMPANION_BASE_URL      base URL of the artifacts (must include
#                               the immutable ref, e.g. ...@v2.0.1);
#                               when set, no fallbacks are added
#   NAS_COMPANION_INSTALL_DIR   install directory
#                               (default: /opt/nas-companion; script
#                               elevates via sudo itself when needed)
#   NAS_COMPANION_NO_LAUNCH=1   install but do not auto-launch the menu
#   NAS_COMPANION_KEEP_TMP=1    keep the temp dir (test hook only)
set -euo pipefail

# ============================================================================
# Immutable artifact ref - THE single source of truth for the version.
# tarball and SHA256SUMS are ALWAYS downloaded from this same ref.
# To release a new version: update this value, commit, then run
# scripts/release.sh <new-version>.
# ============================================================================
ARTIFACT_REF="v2.0.3"
REPO="w876499651-ctrl/nas-companion-downloads"

if [ -n "${NAS_COMPANION_BASE_URL:-}" ]; then
  # An explicit user override is used as-is, without extra fallbacks.
  BASE_URL="$NAS_COMPANION_BASE_URL"
  FALLBACK_URLS=()
else
  # All channels use the SAME ARTIFACT_REF - no mixed versions possible.
  BASE_URL="https://cdn.jsdelivr.net/gh/${REPO}@${ARTIFACT_REF}"
  FALLBACK_URLS=(
    "https://gcore.jsdelivr.net/gh/${REPO}@${ARTIFACT_REF}"
    "https://raw.githubusercontent.com/${REPO}/${ARTIFACT_REF}"
  )
fi

# --- install directory + privilege ----------------------------------------
# On many NAS the user's $HOME (e.g. /home/<user>) does not exist or is not
# writable (NAS user homes usually live under the data volume), so the old
# default "$HOME/.nas-companion" failed with a raw "mkdir: Permission
# denied". The default install directory is /opt/nas-companion (NAS
# convention). The script elevates via sudo itself when needed, so the
# one-line command works for a plain user - no manual sudo/env/install-dir
# required. NAS_COMPANION_INSTALL_DIR stays as an explicit override.
INSTALL_DIR="${NAS_COMPANION_INSTALL_DIR:-/opt/nas-companion}"

# SUDO is empty when already root (never sudo again); otherwise the script
# uses sudo for the privileged steps (mkdir / extract / chmod / launch).
# sudo reads the password from the real controlling terminal itself, which
# works even though `curl ... | bash` consumed stdin.
SUDO=""
if [ "$(id -u)" != "0" ]; then
  SUDO="sudo"
fi

# run_priv runs a command with sudo when needed (no-op when already root).
run_priv() {
  if [ -n "$SUDO" ]; then
    $SUDO "$@"
  else
    "$@"
  fi
}

log() { printf '\033[1;32m[NasCompanion]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[NasCompanion] 错误:\033[0m %b\n' "$*" >&2; exit 1; }

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
    [ -z "$fb" ] && continue
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
  # marker) - accept both.
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

# The privileged steps below (create /opt/nas-companion, extract, chmod,
# launch) run through run_priv, which uses sudo when the caller is not root.
log "安装到 $INSTALL_DIR"
run_priv mkdir -p "$INSTALL_DIR"
run_priv tar -xzf "$TMP/$tarball" -C "$INSTALL_DIR"
run_priv chmod +x "$INSTALL_DIR/bin/nas-installer"

log "安装完成: $INSTALL_DIR"
log "  二进制: $INSTALL_DIR/bin/nas-installer"
log "  Hub 源码: $INSTALL_DIR/hub/"

if [ "${NAS_COMPANION_NO_LAUNCH:-0}" = "1" ]; then
  log "NAS_COMPANION_NO_LAUNCH=1，跳过自动启动。"
  log "手动运行: sudo $INSTALL_DIR/bin/nas-installer"
  exit 0
fi

log "启动 Nas Companion Installer..."

# --- launch: exec the real binary (never exec a shell function) ---
# `exec run_priv ...` is a bug: exec replaces the shell with an external
# command, but run_priv is a shell function, so bash reports
# "exec: run_priv: not found". We must exec the real binary directly.
#
# curl | bash consumed stdin (the script pipe), so the interactive
# installer would have no controlling terminal for menu input. Reconnect
# /dev/tty when available (Issue #61). sudo reads its password from the
# real terminal, which also requires /dev/tty.
INSTALLER_BIN="$INSTALL_DIR/bin/nas-installer"

if [ -r /dev/tty ] && [ -w /dev/tty ]; then
  if [ -n "$SUDO" ]; then
    exec sudo "$INSTALLER_BIN" </dev/tty
  else
    exec "$INSTALLER_BIN" </dev/tty
  fi
else
  # Headless / no controlling terminal: exec without tty redirection.
  if [ -n "$SUDO" ]; then
    exec sudo "$INSTALLER_BIN"
  else
    exec "$INSTALLER_BIN"
  fi
fi
