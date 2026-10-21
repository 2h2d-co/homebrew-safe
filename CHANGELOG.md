# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- Check formula runtime dependencies in `safe-outdated` and `safe-upgrade` before listing an
  upgrade as safe. A formula whose target needs a dependency that is not installed, or one
  newer than its installed version or safe target, falls back to an older safe version
  whose dependencies are met. Otherwise it is reported as blocked by dependencies and
  `safe-upgrade` does not attempt it.

## [0.2.2] - 2026-09-08

### Fixed

- Use Homebrew's current subprocess API for auto-update, formula installs and upgrades,
  and cask upgrades instead of calling the removed command-instance `safe_system` helper.

### Security

- Require repository-wide code ownership and place credentialed GitHub release creation behind the
  tag-restricted release environment.
- Update GitHub-owned checkout and artifact-attestation actions to their current pinned releases.
- Require an exact HTTPS `ghcr.io` bottle root before deriving GHCR repository paths.

## [0.2.1] - 2026-08-10

### Fixed

- Run release automation with a mise version compatible with the checked-in lockfile.

## [0.2.0] - 2026-08-10

### Added

- Add `brew safe-install` for installing release-age-gated Homebrew/core formula versions.

### Fixed

- Prevent formula upgrades from bypassing the safety gate by installing a too-new dependency.
- Refresh Homebrew's in-process package state after each dependency or target installation.
- Verify each selected target version before including it in the upgrade summary.
