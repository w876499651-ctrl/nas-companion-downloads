#!/usr/bin/env bash
# Nas Companion V2 鈥?one-line NAS installer.
#
#   curl -fsSL https://cdn.jsdelivr.net/gh/w876499651-ctrl/nas-companion-downloads@v1.0.0/install.sh | bash
#
# Automatically: detects the Linux architecture, downloads the matching
# Nas Companion package, verifies its SHA-256 checksum, extracts it, and
# launches the nas-installer which enters the Xiaoya-style install menu.
# No Git clone, no Go toolchain, no manual compilation.
#
# --- Immutable artifact ref (critical for delivery consistency) ---
# ALL artifacts (tarball + SHA256SUMS) are downloaded from the SAME
# immutable git tag defined by ARTIFACT_REF. This prevents the jsDelivr
# @main mixed-cache problem where a new SHA256SUMS could be paired with
# an old tarball from a different commit. Every download channel
# (primary and fallbacks) uses this exact same ref 鈥?switching from
# primary to fallback can never mix versions.
#
# Download channels (all use the same ARTIFACT_REF):
#   1. cdn.jsdelivr.net      鈥?jsDelivr anycast CDN (primary)
#   2. gcore.jsdelivr.net    鈥?jsDelivr G-Core backend (trusted second
#                              channel; different CDN provider, bypasses
#                              anycast routing issues on some NAS)
#   3. raw.githubusercontent.com 鈥?GitHub Raw (last resort; known
#                              unstable on some NAS with OpenSSL
#                              SSL_ERROR_SYSCALL, but safe with immutable ref)
#
# Configuration (env overrides, all optional):
#   NAS_COMPANION_BASE_URL      base URL of the artifacts (must include
#                               the immutable ref, e.g. ...@v1.0.0);
#                               when set, no fallbacks are added
#   NAS_COMPANION_INSTALL_DIR   install directory
#                               (default: /opt/nas-companion; script
#                               elevates via sudo itself when needed)
#   NAS_COMPANION_NO_LAUNCH=1   install but do not auto-launch the menu
#   NAS_COMPANION_KEEP_TMP=1    keep the temp dir (test hook only)
set -euo pipefail

# ============================================================================
# Immutable artifact ref 鈥?THE single source of truth for the version.
# tarball and SHA256SUMS are ALWAYS downloaded from this same ref.
# To release a new version: update this value, commit, then run
# scripts/release.sh <new-version>.
# ============================================================================
ARTIFACT_REF="v2.0.0"
REPO="w876499651-ctrl/nas-companion-downloads"

if [ -n "${NAS_COMPANION_BASE_URL:-}" ]; then
  # An explicit user override is used as-is, without extra fallbacks.
  BASE_URL="$NAS_COMPANION_BASE_URL"
  FALLBACK_URLS=()
else
  # All channels use the SAME ARTIFACT_REF 鈥?no mixed versions possible.
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
# one-line command works for a plain user 鈥?no manual sudo/env/install-dir
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
die() { printf '\033[1;31m[NasCompanion] 閿欒:\033[0m %b\n' "$*" >&2; exit 1; }

# --- 1. OS / architecture detection -------------------------------------
detect_os_arch() {
  local os machine
  os="$(uname -s)"
  [ "$os" = "Linux" ] || die "浠呮敮鎸?Linux锛堝綋鍓? $os锛夈€?
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64|x64) ARCH="amd64" ;;
    aarch64|arm64)    ARCH="arm64" ;;
    *) die "涓嶆敮鎸佺殑鏋舵瀯 $machine锛堟敮鎸?amd64 / arm64锛夈€? ;;
  esac
  log "妫€娴嬪埌 Linux / $machine -> 浣跨敤 $ARCH 瀹夎鍖?
}

# --- 2. download ---------------------------------------------------------
fetch() { # $1 url  $2 out
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    die "闇€瑕?curl 鎴?wget 鎵嶈兘涓嬭浇銆?
  fi
}

# fetch_any downloads a relative artifact from the primary base URL and,
# on failure, from each fallback source in order. EVERY source embeds the
# same ARTIFACT_REF, so a primary/fallback switch can never mix versions.
fetch_any() { # $1 relative path  $2 out
  local rel="$1" out="$2" url fb
  url="$BASE_URL/$rel"
  if fetch "$url" "$out"; then
    return 0
  fi
  for fb in "${FALLBACK_URLS[@]:-}"; do
    [ -n "$fb" ] || continue
    log "涓讳笅杞芥簮涓嶅彲鐢紝姝ｅ湪鍥為€€鍒板鐢ㄦ簮: $fb"
    url="$fb/$rel"
    if fetch "$url" "$out"; then
      return 0
    fi
  done
  die "涓嬭浇澶辫触: $rel锛堜富婧?$BASE_URL 涓庡叏閮ㄥ鐢ㄦ簮鍧囧け璐ワ級銆傝妫€鏌?NAS 缃戠粶鍚庨噸璇曘€?
}

# --- 3. SHA-256 verification ---------------------------------------------
sha256_of() { # $1 file -> hex
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "闇€瑕?sha256sum 鎴?shasum 杩涜鏍￠獙銆?
  fi
}

verify_checksum() { # $1 tarball  $2 sumsfile
  local name want got
  name="$(basename "$1")"
  # SHA256SUMS lines are "<hash>  <name>" or "<hash> *<name>" (GNU binary
  # marker) 鈥?accept both.
  want="$(awk -v n="$name" '{if ($2 == n || $2 == "*" n) {print $1; exit}}' "$2")"
  [ -n "$want" ] || die "SHA256SUMS 涓壘涓嶅埌 $name 鐨勬牎楠屽€笺€?
  got="$(sha256_of "$1")"
  if [ "$got" != "$want" ]; then
    die "SHA-256 鏍￠獙澶辫触锛堟湡鏈?$want锛屽疄闄?$got锛夈€傚凡涓瀹夎锛屾湭鍐欏叆浠讳綍鏂囦欢銆?
  fi
  log "SHA-256 鏍￠獙閫氳繃锛?want锛?
}

# --- main ----------------------------------------------------------------
detect_os_arch

tarball="nas-companion-linux-${ARCH}.tar.gz"

log "浣跨敤涓嶅彲鍙樹骇鐗╃増鏈? $ARTIFACT_REF锛坱arball 涓?SHA256SUMS 鍧囦粠姝ょ増鏈幏鍙栵紝绂佹娣峰悎锛?

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

log "涓嬭浇 $tarball锛堜富婧?$BASE_URL锛?
fetch_any "$tarball" "$TMP_NATIVE/$tarball"
log "涓嬭浇 SHA256SUMS"
fetch_any "SHA256SUMS" "$TMP_NATIVE/SHA256SUMS"

# Verification/extraction use the native (non-backslash) path so sha256sum
# and tar never escape the file name.
verify_checksum "$TMP/$tarball" "$TMP/SHA256SUMS"

# The privileged steps below (create /opt/nas-companion, extract, chmod,
# launch) run through run_priv, which uses sudo when the caller is not root.
log "鍒涘缓瀹夎鐩綍 $INSTALL_DIR锛堥渶瑕佹潈闄愭椂鑷姩浣跨敤 sudo锛?
run_priv mkdir -p "$INSTALL_DIR" || die "鏃犳硶鍒涘缓瀹夎鐩綍 $INSTALL_DIR锛堟潈闄愪笉瓒筹級銆傝剼鏈凡鑷姩灏濊瘯 sudo锛涜嫢浠嶆湭鎴愬姛锛岃纭褰撳墠鐢ㄦ埛鏈?sudo 鏉冮檺銆?
log "瑙ｅ帇鍒?$INSTALL_DIR"
run_priv tar -xzf "$TMP/$tarball" -C "$INSTALL_DIR" --strip-components=1 || die "瑙ｅ帇瀹夎鍖呭埌 $INSTALL_DIR 澶辫触銆?

# Guarantee the exec bit regardless of the mode recorded in the tarball
# (a tarball packed on a platform without POSIX mode bits may carry 0644).
run_priv chmod +x "$INSTALL_DIR/bin/nas-installer" 2>/dev/null || true
run_priv test -x "$INSTALL_DIR/bin/nas-installer" || die "瀹夎鍖呯己灏戝彲鎵ц鏂囦欢 bin/nas-installer銆?
run_priv test -f "$INSTALL_DIR/hub/Dockerfile" || die "瀹夎鍖呯己灏?Hub 鏋勫缓涓婁笅鏂?hub/锛堟棤娉曟湰鍦版瀯寤?V2 Hub锛夈€?

log "瀹夎瀹屾垚銆傚惎鍔ㄥ櫒: $INSTALL_DIR/bin/nas-installer"
if [ "${NAS_COMPANION_NO_LAUNCH:-0}" = "1" ]; then
  log "鏈嚜鍔ㄥ惎鍔紙NAS_COMPANION_NO_LAUNCH=1锛夈€傚彲鎵嬪姩杩愯: $INSTALL_DIR/bin/nas-installer"
  exit 0
fi
cd "$INSTALL_DIR"
# `curl ... | bash` leaves the exec'd installer with the (already-consumed)
# curl pipe as stdin, so it would look like a non-interactive run and fail.
# Reconnect the controlling terminal when present: one single command then
# goes straight into the interactive menu (no second command needed). When
# /dev/tty exists but cannot be opened (rare headless run), fall back to a
# plain exec so the install is not aborted by the redirect. The installer
# runs elevated (sudo) like the steps above, and sudo reads its password
# from the real terminal itself.
if [ -r /dev/tty ] && [ -w /dev/tty ] && exec $SUDO ./bin/nas-installer < /dev/tty 2>/dev/null; then
  :
fi
exec $SUDO ./bin/nas-installer
