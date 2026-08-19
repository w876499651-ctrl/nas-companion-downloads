# Nas Companion Delivery Provenance

## v2.0.0

- **Source repository**: w876499651-ctrl/nas-companion
- **Source branch**: codex/hub-foundation
- **Source commit**: c8060af (Merge PR #75 — install progress)
- **Delivery tag**: v2.0.0
- **Build date**: 2026-08-19
- **amd64 SHA256**: 4e9daa7c0578eed10dd27c8e030a9eabeadfb8342c6a0a5f952e94296599cdbd
- **arm64 SHA256**: dea1bc32e38d6c18d43d44f216e5e51efd62f0bfbbd297a5fe1eb9d97765db43
- **Go version**: 1.26.5
- **Build command**: CGO_ENABLED=0 go build -trimpath

### Included fixes (since previous delivery 2626c58)
- #66/#67: Installer single-instance flock lock
- #63/#65: GOPROXY build config + menu 14
- #68/#69: Hub device admin docker exec fix
- #70/#71: Container restart policy (unless-stopped)
- #72/#73: Menu service status + health latency
- #74/#75: Install progress stage labels

### Release process
1. Source PR merged and tests PASS
2. Build amd64 + arm64 from merged commit
3. Generate SHA256SUMS
4. Update install.sh ARTIFACT_REF
5. Commit + push
6. Tag immutable version
7. Verify remote download consistency