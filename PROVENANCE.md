# Nas Companion Delivery Provenance

## v2.0.3 (CURRENT - final immutable release candidate)

- **Source repository**: w876499651-ctrl/nas-companion
- **Source branch**: codex/hub-foundation
- **Source commit**: c8060af (Merge PR #75 - install progress)
- **Delivery commit**: see git tag `v2.0.3`
- **Delivery tag**: v2.0.3
- **Build date**: 2026-08-20
- **amd64 SHA256**: be2c402e954f401af2d646cd8d66a32a4ae4aabe0d41a53ddb9a83a4c8bad7e0
- **arm64 SHA256**: 7e9669bd529fe5cf08ecfecaf9f362d58ab3d0cddadbf5c865c5ad0a6a153dc6
- **Go version**: 1.26.5
- **Build command**: CGO_ENABLED=0 go build -trimpath
- **install.sh encoding**: UTF-8 no BOM
- **Launch fix**: `exec sudo "$INSTALLER_BIN" </dev/tty` / `exec "$INSTALLER_BIN" </dev/tty` (preserves curl|bash TTY reconnection, Issue #61)
- **Tag history**: v2.0.3 is a brand-new tag, never deleted, never moved, never reused.

### Included fixes
- #66/#67: Installer single-instance flock lock
- #63/#65: GOPROXY build config + menu 14
- #68/#69: Hub device admin docker exec fix
- #70/#71: Container restart policy (unless-stopped)
- #72/#73: Menu service status + health latency
- #74/#75: Install progress stage labels

## v2.0.2 (FUNCTIONALLY_PASS_BUT_TAG_MOVED - not final)

- **Status**: Code functionally correct and real-NAS one-line install verified PASS, but the tag was deleted and recreated once during release (first push pointed to wrong commit due to a PowerShell variable-expansion commit failure). This violates the immutable-ref guarantee, so v2.0.2 cannot be used as the final immutable release.
- **Delivery commit**: c61adc3
- **Source commit**: c8060af
- **Fix**: Same launch fix as v2.0.3.
- **Action**: Retained as historical record. Never deleted, never moved again.

## v2.0.1 (INVALID - do not use)

- **Status**: INVALID_FOR_FINAL_ACCEPTANCE
- **Reason**: install.sh ends with `exec run_priv "$INSTALL_DIR/bin/nas-installer"`. `run_priv` is a shell function; `exec` cannot execute shell functions, causing `bash: exec: run_priv: not found`. One-line install downloads and extracts successfully but cannot auto-launch the interactive installer.
- **Action**: Retained as historical record. Never use for installation.

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
