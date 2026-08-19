# Nas Companion Delivery Provenance

## v2.0.1 (CURRENT - valid immutable release)

- **Source repository**: w876499651-ctrl/nas-companion
- **Source branch**: codex/hub-foundation
- **Source commit**: c8060af (Merge PR #75 - install progress)
- **Delivery tag**: v2.0.1
- **Build date**: 2026-08-19
- **amd64 SHA256**: be2c402e954f401af2d646cd8d66a32a4ae4aabe0d41a53ddb9a83a4c8bad7e0
- **arm64 SHA256**: 7e9669bd529fe5cf08ecfecaf9f362d58ab3d0cddadbf5c865c5ad0a6a153dc6
- **Go version**: 1.26.5
- **Build command**: CGO_ENABLED=0 go build -trimpath
- **install.sh encoding**: UTF-8 no BOM, verified
- **Note**: This release replaces v2.0.0 which was invalidated due to a tag-move incident and encoding corruption in install.sh.

### Included fixes
- #66/#67: Installer single-instance flock lock
- #63/#65: GOPROXY build config + menu 14
- #68/#69: Hub device admin docker exec fix
- #70/#71: Container restart policy (unless-stopped)
- #72/#73: Menu service status + health latency
- #74/#75: Install progress stage labels

### Release process (must follow exactly)
1. Source PR merged and all tests PASS
2. Build amd64 + arm64 from merged commit
3. Generate SHA256SUMS
4. Update install.sh ARTIFACT_REF (UTF-8 no BOM)
5. Update PROVENANCE.md
6. Commit + push to main
7. Create NEW tag (never reuse, never move, never delete)
8. Push tag
9. Verify remote download consistency across all 3 channels

## v2.0.0 (INVALID - do not use)

- **Status**: INVALID_FOR_FINAL_ACCEPTANCE
- **Reason**: Tag was created, pushed, then deleted and recreated due to a commit failure. This violates the immutable ref guarantee. CDN may have cached old content.
- **Additional issue**: install.sh had UTF-8 double-encoding corruption (Chinese text garbled).
- **Action**: Retained as historical record. Never use for installation.

## Historical (pre-immutable, @main based)

- 2626c58: V2 packages with GOPROXY (Issue #63) - released before source PR merged (process violation)
- 3a9be2c: Operation results stay visible until Enter
- e1e7975: Rebuild without Hub Dockerfile GOPROXY
- 503da72: Docker registry Bearer token + Hub build GOPROXY
- ea4ec64: Default install dir /opt/nas-companion with sudo
- 8600ad2: jsDelivr default + GitHub Raw fallback
- 8d24c92: Initial V2 delivery
