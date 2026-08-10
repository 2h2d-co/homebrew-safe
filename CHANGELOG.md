# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Add `brew safe-install` for installing release-age-gated Homebrew/core formula versions.

### Fixed

- Prevent formula upgrades from bypassing the safety gate by installing a too-new dependency.
- Verify each selected target version before including it in the upgrade summary.
