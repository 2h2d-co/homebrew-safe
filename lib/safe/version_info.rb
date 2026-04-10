# frozen_string_literal: true

module Safe
  module VersionInfo
    module_function

    def formula_installed_version(formula, fetch_head: false)
      versions = formula.outdated_kegs(fetch_head: fetch_head).map { |keg| keg.version.to_s }.uniq
      return versions.join(", ") unless versions.empty?

      formula.pkg_version.to_s
    end
  end
end
