# frozen_string_literal: true

module Safe
  # Help paragraphs shared by the command descriptions.
  module Help
    GATE = <<~EOS.chomp
      A version passes the release-age gate when it was published before the cutoff.
      If the newest version is too new, the command can use the newest older
      Homebrew/core formula or cask version that passes.
    EOS

    CUTOFF = <<~EOS.chomp
      The cutoff comes from `--before`, then the package's own `before` in
      `~/.config/brew-safe/config.yaml`, then the global `before` in that file.
      There is no built-in default. A cutoff is an age such as `7d`, `6m`, or `1y`,
      or a date such as `2026-01-01` or `2026-01-01T00:00:00Z`.
    EOS

    DATES = <<~EOS.chomp
      A formula's date is when its bottle was published to GHCR. A cask's date is
      when the Homebrew commit that added the version was made. Cask lookups use
      the GitHub API, so authenticate with `gh auth login` or set
      `HOMEBREW_GITHUB_API_TOKEN` to avoid rate limits.
    EOS

    AUTO_UPDATE = "Homebrew is updated first unless `HOMEBREW_NO_AUTO_UPDATE` is set."

    BEFORE_OPTION = "Use this cutoff instead of the configured ones, such as `7d` or `2026-01-01`."
  end
end
