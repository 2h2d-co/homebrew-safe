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
# List safe-to-upgrade packages (30-day default from config)
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

# Include auto-updating casks
brew safe-outdated --cask --greedy

# Check specific packages
brew safe-outdated node jq curl
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

# Only formulae
brew safe-upgrade --formula
```

## Configuration

Create `~/.config/brew-safe/config.yaml`:

```yaml
# Global default — required (no hardcoded fallback)
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

**Supported `before` formats:**
- Relative: `7d`, `30d`, `6m`, `1y`
- Absolute: `2026-01-01`, `2026-01-01T00:00:00Z`

## How it works

### Formulae

Looks up the bottle publication date from GHCR (GitHub Container Registry) manifest annotations. This is the date the bottle was published, not when the source was tagged.

If the newest Homebrew/core formula release is too new, `safe-outdated` and `safe-upgrade`
can walk recent formula history and select the latest safe intermediate bottle instead.

### Casks

Looks up the last commit date for the cask's source file via the GitHub API. Set `HOMEBREW_GITHUB_API_TOKEN` or `GITHUB_TOKEN` to avoid rate limits.

### Safety logic

A package is "safe to upgrade" when its publication date is older than the configured cutoff. For Homebrew/core formulae, this may be the newest available version or the latest safe intermediate version. Packages with unknown dates (custom taps, non-GHCR bottles) are skipped with a warning.

## License

MIT
