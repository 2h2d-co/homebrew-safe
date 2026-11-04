# frozen_string_literal: true

require "pathname"

module Safe
  # Points an installed cask's receipt at the tap its definition came from.
  #
  # `safe-upgrade` installs casks from a temporary tap, so Homebrew records that tap as the
  # receipt's source. The receipt is rewritten through Homebrew's own `Cask::Tab` API, which
  # Homebrew also uses when it moves receipts to a migrated tap.
  module CaskReceipt
    class Mismatch < RuntimeError; end

    module_function

    def tabfile(cask)
      require "cask/tab"

      cask.metadata_main_container_path/::Cask::Tab::FILENAME
    end

    def retarget!(tabfile:, from_tap:, version:, to_tap:, path:, tap_git_head:)
      require "cask/tab"

      tabfile = Pathname(tabfile)
      raise Mismatch, "no install receipt at #{tabfile}" unless tabfile.file?

      tab = ::Cask::Tab.from_file_content(tabfile.read, tabfile)
      source = tab.source
      unless source["tap"].to_s.casecmp?(from_tap)
        raise Mismatch, "the install receipt names tap #{source["tap"].inspect}, not #{from_tap}"
      end
      unless source["version"].to_s == version.to_s
        raise Mismatch, "the install receipt names version #{source["version"].inspect}, not #{version}"
      end

      source["tap"] = to_tap
      source["path"] = path.to_s
      source["tap_git_head"] = tap_git_head
      tab.write
    end
  end
end
