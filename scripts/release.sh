#!/usr/bin/env bash
# scripts/release.sh — Immutable release flow for nas-companion-downloads.
#
# Creates an immutable git tag, pushes it, purges CDN (safety), and
# verifies that remote downloads are self-consistent (tarball == SHA256SUMS).
#
# Usage:
#   ./scripts/release.sh v1.0.0
#
# Prerequisites:
#   - Artifacts (nas-companion-linux-{amd64,arm64}.tar.gz) are committed
#   - SHA256SUMS matches the artifacts (sha256sum -c SHA256SUMS)
#   - install.sh ARTIFACT_REF matches the target version
#   - Working tree is clean
#   - git push access to origin
set -euo pipefail

REPO="w876499651-ctrl/nas-companion-downloads"
VERSION="${1:?Usage: release.sh <version-tag>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

log() { printf '\033[1;32m[release]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[release] 错误:\033[0m %s\n' "$*" >&2; exit 1; }

sha256_tool() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$@"
  else
    die "需要 sha256sum 或 shasum。"
  fi
}

# --- 1. Verify local consistency ------------------------------------------
log "[1/5] 校验本地 SHA256SUMS 与 tarball 一致..."
sha256_tool -c SHA256SUMS || die "本地校验失败：SHA256SUMS 与 tarball 不匹配。请重新生成 SHA256SUMS。"

# --- 2. Verify install.sh ARTIFACT_REF matches version --------------------
log "[2/5] 校验 install.sh ARTIFACT_REF = $VERSION ..."
REF_IN_SCRIPT=$(sed -n 's/^ARTIFACT_REF="\([^"]*\)".*/\1/p' install.sh)
[ -n "$REF_IN_SCRIPT" ] || die "install.sh 中未找到 ARTIFACT_REF 定义。"
[ "$REF_IN_SCRIPT" = "$VERSION" ] || die "install.sh ARTIFACT_REF=$REF_IN_SCRIPT 与目标版本 $VERSION 不一致。请先更新 install.sh 中的 ARTIFACT_REF 并 commit。"

# --- 3. Check working tree is clean ---------------------------------------
if [ -n "$(git status --porcelain)" ]; then
  die "工作区有未提交变更。请先 commit 或 stash，再打 tag。"
fi

# --- 4. Create and push tag -----------------------------------------------
log "[3/5] 创建并推送不可变 tag $VERSION ..."
git tag "$VERSION" || die "创建 tag $VERSION 失败（可能已存在；不可变 tag 禁止重复使用）。"
git push origin "$VERSION" || die "推送 tag $VERSION 失败。"

# --- 5. Purge jsDelivr CDN (safety; new tags normally auto-fetch) ---------
log "[4/5] 刷新 jsDelivr CDN 缓存（保险措施）..."
for file in install.sh SHA256SUMS nas-companion-linux-amd64.tar.gz nas-companion-linux-arm64.tar.gz; do
  curl -s -X POST https://purge.jsdelivr.net/ \
    -H "Content-Type: application/json" \
    -d "{\"path\":[\"/gh/${REPO}@${VERSION}/${file}\"]}" >/dev/null 2>&1 || true
done
log "  CDN purge 请求已发送。新 tag 首次访问会自动回源，purge 仅为保险。"

# --- 6. Verify remote download consistency --------------------------------
log "[5/5] 验证远程下载一致性（jsDelivr @$VERSION）..."
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
for arch in amd64 arm64; do
  tb="nas-companion-linux-${arch}.tar.gz"
  log "  下载 $tb ..."
  curl -fsSL --retry 3 --retry-delay 2 \
    "https://cdn.jsdelivr.net/gh/${REPO}@${VERSION}/${tb}" \
    -o "$TMPDIR/$tb" || die "远程下载 $tb 失败。"
done
curl -fsSL --retry 3 --retry-delay 2 \
  "https://cdn.jsdelivr.net/gh/${REPO}@${VERSION}/SHA256SUMS" \
  -o "$TMPDIR/SHA256SUMS" || die "远程下载 SHA256SUMS 失败。"
(cd "$TMPDIR" && sha256_tool -c SHA256SUMS) || die "远程校验失败：下载的 tarball 与 SHA256SUMS 不一致！"

log ""
log "============================================"
log "  发布完成: $VERSION"
log "============================================"
log ""
log "唯一安装命令："
log ""
log "  curl -fsSL https://cdn.jsdelivr.net/gh/${REPO}@${VERSION}/install.sh | bash"
log ""
log "旧的 @main 安装命令已废弃，请勿继续使用。"
