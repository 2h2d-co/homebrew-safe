# homebrew-safe

Supply-chain safety commands for Homebrew. Prevents upgrading to versions released too recently — giving the community time to discover compromised or broken releases.

## Install

```sh
brew tap 2h2d-co/safe
```

## Commands

### `brew safe-outdated`

List outdated formulae and casks that are safe to upgrade based on release date.
Like `brew outdated`, this auto-updates Homebrew first unless `HOMEBREW_NO_AUTO_UPDATE=1` is set.

```sh
# List safe-to-upgrade packages using the configured cutoff, e.g. before: "30d".
# There is no hardcoded default cutoff.
# For Homebrew/core formulae, this can surface the latest safe intermediate version
# if the newest available version is still too new.
brew safe-outdated

# Override cutoff
brew safe-outdated --before=7d

# Verbose: shows safe, too-new, date-unknown, and pinned sections.
# Safe entries also show both the chosen safe target and the latest available version
# when they differ.
brew safe-outdated --verbose

# JSON output
brew safe-outdated --json

# Only formulae or casks
brew safe-outdated --formula
brew safe-outdated --cask

# Include auto-updating casks and casks with version :latest
brew safe-outdated --cask --greedy

# More selective cask inclusion
brew safe-outdated --cask --greedy-latest
brew safe-outdated --cask --greedy-auto-updates

# Check specific packages
brew safe-outdated node jq curl firefox
```

### `brew safe-upgrade`

Upgrade only the packages that pass the release date safety gate.
Like `brew upgrade`, this auto-updates Homebrew first unless `HOMEBREW_NO_AUTO_UPDATE=1` is set.
For Homebrew/core formulae, this can upgrade to the latest safe intermediate version
when the newest version is still too new.

```sh
# Upgrade safe packages
brew safe-upgrade

# Dry run
brew safe-upgrade --dry-run

# Override cutoff
brew safe-upgrade --before=14d

# Only formulae or casks
brew safe-upgrade --formula
brew safe-upgrade --cask

# Include auto-updating casks and casks with version :latest
brew safe-upgrade --cask --greedy

# More selective cask inclusion
brew safe-upgrade --cask --greedy-latest
brew safe-upgrade --cask --greedy-auto-updates

# Show detailed skipped/safe output
brew safe-upgrade --verbose

# Upgrade specific packages only if they are safe
brew safe-upgrade node jq firefox
```

## Configuration

Create `~/.config/brew-safe/config.yaml`:

```yaml
# Global default — recommended (no hardcoded fallback)
before: "30d"

# Per-formula overrides (use full_name for non-core taps)
formula:
  node:
    before: "7d"
  "python@3.13":
    before: "90d"
  "user/tap/custom-formula":
    before: "60d"

# Per-cask overrides
cask:
  firefox:
    before: "14d"
```

**Resolution order:** `--before` CLI flag > per-item config > global config.

A global `before` is recommended. If omitted, only items with per-item `before`
values can be evaluated; other known-date items are skipped as `no_cutoff`.

**Supported `before` formats:**
- Relative: `7d`, `30d`, `6m`, `1y`
- Absolute: `2026-01-01`, `2026-01-01T00:00:00Z`

## How it works

### Formulae

Looks up the bottle publication date from GHCR (GitHub Container Registry) manifest annotations. This is the date the bottle was published, not when the source was tagged.

If the newest Homebrew/core formula release is too new, `safe-outdated` and `safe-upgrade`
can walk recent formula history and select the latest safe intermediate bottle instead.
This historical lookup is limited to `homebrew/core`, searches recent commit history,
depends on Homebrew's formula commit message patterns, and requires GHCR bottle metadata
for the historical target.

### Casks

Looks up the last commit date for the cask's source file via the GitHub API. Set `HOMEBREW_GITHUB_API_TOKEN` or `GITHUB_TOKEN` to avoid rate limits.

For casks, this date is a proxy for release age. It is not the upstream vendor's
actual release date.

### Safety logic

A package is "safe to upgrade" when its publication date is older than the configured cutoff. For Homebrew/core formulae, this may be the newest available version or the latest safe intermediate version.

Packages with unknown dates (custom taps, non-GHCR bottles, casks whose GitHub
lookup fails) are skipped. Use `brew safe-outdated --verbose` or
`brew safe-outdated --json` to see skipped `date_unknown` and `no_cutoff` items.
`brew safe-upgrade --dry-run` also shows skipped items.

## Development

Run the tests with:

```sh
for t in test/*_test.rb; do ruby -Itest -Ilib "$t"; done
```

Useful local tap helpers:

```sh
mise run tap:local   # tap this working tree
mise run tap:remote  # tap from the GitHub remote
```

## License

MIT
