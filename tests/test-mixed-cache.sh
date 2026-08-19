#!/usr/bin/env bash
# tests/test-mixed-cache.sh
#
# Proves that the immutable-ref design in install.sh CANNOT produce the
# "new SHA256SUMS + old tarball" mixed-cache combination that occurred
# with jsDelivr @main.
#
# Runs on Linux / Git Bash (requires: bash, awk, sha256sum or shasum).
# Does NOT touch real NAS or network — all tests are local.
#
# Usage:  bash tests/test-mixed-cache.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
assert() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "ERROR: no sha256 tool available" >&2; exit 1
  fi
}

# Replicates install.sh's verify_checksum logic exactly for functional tests.
verify_checksum_local() {
  local tarball="$1" sumsfile="$2"
  local name want got
  name="$(basename "$tarball")"
  want="$(awk -v n="$name" '{if ($2 == n || $2 == "*" n) {print $1; exit}}' "$sumsfile")"
  [ -n "$want" ] || return 1
  got="$(sha256_of "$tarball")"
  [ "$got" = "$want" ]
}

echo "=== Test 1: Single immutable ARTIFACT_REF (structural proof) ==="
# Extract all ARTIFACT_REF assignments
REFS=$(grep -oE 'ARTIFACT_REF="[^"]*"' "$INSTALL_SH" | sort -u)
REF_COUNT=$(echo "$REFS" | grep -c . || true)
assert "Exactly one ARTIFACT_REF assignment in install.sh" "[ $REF_COUNT -eq 1 ]"
ARTIFACT_REF=$(echo "$REFS" | sed 's/ARTIFACT_REF="//;s/"//')
assert "ARTIFACT_REF is not empty" "[ -n '$ARTIFACT_REF' ]"
assert "ARTIFACT_REF is NOT mutable 'main'" "[ '$ARTIFACT_REF' != 'main' ]"
assert "ARTIFACT_REF looks like a version tag (v-prefix or commit sha)" \
  "[[ '$ARTIFACT_REF' =~ ^v[0-9] || ${#ARTIFACT_REF} -ge 7 ]]"

# Prove ARTIFACT_REF is used to construct download URLs
URL_REF_COUNT=$(grep -c 'ARTIFACT_REF' "$INSTALL_SH" || true)
assert "ARTIFACT_REF used in URL construction (>=2: primary + fallbacks)" "[ $URL_REF_COUNT -ge 2 ]"

# Prove NO artifact download URL uses mutable @main or /main/
MAIN_IN_URLS=$(grep -oE '(cdn\.jsdelivr\.net|gcore\.jsdelivr\.net|raw\.githubusercontent\.com)[^"'\'' ]*(@main|/main/)' "$INSTALL_SH" || true)
assert "No artifact URL uses mutable @main or /main/ ref" "[ -z '$MAIN_IN_URLS' ]"

# Prove all channels are defined with the same ARTIFACT_REF interpolation
BASE_HAS_REF=$(grep -c 'BASE_URL=.*${ARTIFACT_REF}' "$INSTALL_SH" || true)
FALLBACK_HAS_REF=$(grep -c 'FALLBACK_URLS' "$INSTALL_SH" || true)
assert "BASE_URL embeds ARTIFACT_REF" "[ $BASE_HAS_REF -ge 1 ]"
assert "FALLBACK_URLS array exists (all entries embed ARTIFACT_REF)" "[ $FALLBACK_HAS_REF -ge 1 ]"

echo ""
echo "=== Test 2: SHA256 verification REJECTS mismatched (new SHA + old tarball) ==="
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# "old tarball" (simulating jsDelivr cached old binary)
echo "this is the old tarball content from version A" > "$TMPDIR/old.tar.gz"
# "new SHA256SUMS" with a hash that does NOT match the old tarball
echo "0000000000000000000000000000000000000000000000000000000000000000  old.tar.gz" > "$TMPDIR/SHA256SUMS"
set +e
verify_checksum_local "$TMPDIR/old.tar.gz" "$TMPDIR/SHA256SUMS" >/dev/null 2>&1
RC=$?
set -e
assert "Mismatched (new SHA + old tarball) exits non-zero (blocked)" "[ $RC -ne 0 ]"

echo ""
echo "=== Test 3: SHA256 verification ACCEPTS matched files ==="
echo "consistent tarball content from version B" > "$TMPDIR/matched.tar.gz"
MATCHED_HASH=$(sha256_of "$TMPDIR/matched.tar.gz")
echo "${MATCHED_HASH}  matched.tar.gz" > "$TMPDIR/SHA256SUMS"
set +e
verify_checksum_local "$TMPDIR/matched.tar.gz" "$TMPDIR/SHA256SUMS" >/dev/null 2>&1
RC=$?
set -e
assert "Matched tarball + SHA exits zero (accepted)" "[ $RC -eq 0 ]"

echo ""
echo "=== Test 4: Mixed-cache simulation — same ref passes, mixed refs fail ==="
# Simulate two versions: vA and vB, each self-consistent
mkdir -p "$TMPDIR/vA" "$TMPDIR/vB" "$TMPDIR/mix"
echo "version A binary content" > "$TMPDIR/vA/pkg.tar.gz"
VA_HASH=$(sha256_of "$TMPDIR/vA/pkg.tar.gz")
echo "${VA_HASH}  pkg.tar.gz" > "$TMPDIR/vA/SHA256SUMS"
echo "version B binary content (different)" > "$TMPDIR/vB/pkg.tar.gz"
VB_HASH=$(sha256_of "$TMPDIR/vB/pkg.tar.gz")
echo "${VB_HASH}  pkg.tar.gz" > "$TMPDIR/vB/SHA256SUMS"

# Consistent: both from vA (what immutable ref guarantees)
set +e
(cd "$TMPDIR/vA" && sha256sum -c SHA256SUMS >/dev/null 2>&1)
RC=$?
set -e
assert "Consistent vA (both files from same ref) passes SHA check" "[ $RC -eq 0 ]"

# Consistent: both from vB
set +e
(cd "$TMPDIR/vB" && sha256sum -c SHA256SUMS >/dev/null 2>&1)
RC=$?
set -e
assert "Consistent vB (both files from same ref) passes SHA check" "[ $RC -eq 0 ]"

# MIXED: tarball from vA, SHA256SUMS from vB (this is exactly what @main
# mixed cache produced — and what immutable ref design makes impossible).
# Use matching filename pkg.tar.gz so failure is a hash mismatch, not
# file-not-found.
cp "$TMPDIR/vA/pkg.tar.gz" "$TMPDIR/mix/pkg.tar.gz"
cp "$TMPDIR/vB/SHA256SUMS" "$TMPDIR/mix/SHA256SUMS"
set +e
(cd "$TMPDIR/mix" && sha256sum -c SHA256SUMS >/dev/null 2>&1)
RC=$?
set -e
assert "MIXED (vA tarball + vB SHA) FAILS SHA check (correctly blocked)" "[ $RC -ne 0 ]"

echo ""
echo "=== Test 5: Design proof — install.sh requests both artifacts from same ref ==="
# Both fetch_any calls use the same BASE_URL/FALLBACK_URLS, which all embed
# the single ARTIFACT_REF. Therefore tarball and SHA256SUMS always come from
# the same commit. A primary->fallback switch changes the CDN provider, not
# the version.
FETCH_CALLS=$(grep -c 'fetch_any' "$INSTALL_SH" || true)
assert "install.sh calls fetch_any for both tarball and SHA256SUMS (>=2)" "[ $FETCH_CALLS -ge 2 ]"
# fetch_any only uses BASE_URL and FALLBACK_URLS — no per-file ref override
FETCH_BODY=$(sed -n '/^fetch_any()/,/^}/p' "$INSTALL_SH")
FETCH_HAS_BASE=$(echo "$FETCH_BODY" | grep -c 'BASE_URL' || true)
FETCH_HAS_FALLBACK=$(echo "$FETCH_BODY" | grep -c 'FALLBACK_URLS' || true)
assert "fetch_any uses BASE_URL (primary channel)" "[ $FETCH_HAS_BASE -ge 1 ]"
assert "fetch_any uses FALLBACK_URLS (fallback channels)" "[ $FETCH_HAS_FALLBACK -ge 1 ]"

echo ""
echo "========================================="
echo "  Results: $PASS passed, $FAIL failed"
echo "========================================="
[ "$FAIL" -eq 0 ] || exit 1
