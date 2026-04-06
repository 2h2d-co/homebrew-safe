# homebrew-safe

Supply-chain safety commands for Homebrew. Prevents upgrading to versions released too recently — giving the community time to discover compromised or broken releases.

## Install

```sh
brew tap 2h2d-co/safe
```

## Commands

### `brew safe-outdated`

List outdated formulae and casks that are safe to upgrade based on release date.

```sh
# List safe-to-upgrade packages (30-day default from config)
brew safe-outdated

# Override cutoff
brew safe-outdated --before=7d

# Verbose: shows safe, too-new, date-unknown, and pinned sections
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

### Casks

Looks up the last commit date for the cask's source file via the GitHub API. Set `HOMEBREW_GITHUB_API_TOKEN` or `GITHUB_TOKEN` to avoid rate limits.

### Safety logic

A package is "safe to upgrade" when its publication date is older than the configured cutoff. Packages with unknown dates (custom taps, non-GHCR bottles) are skipped with a warning.

## License

MIT
