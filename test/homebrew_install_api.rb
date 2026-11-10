# frozen_string_literal: true

# Run through `brew ruby`; never installs packages.
# Historical formula files are installed in-process through the steps `brew install`
# runs. Check that this Homebrew version still accepts the arguments we pass.
require "formulary"
require "install"

def keywords(owner, method_name)
  raise "#{owner}.#{method_name} is missing" unless owner.respond_to?(method_name)

  owner.method(method_name).parameters.filter_map { |type, name| name if %i[key keyreq].include?(type) }
end

{
  install_formula?:              %i[installed_on_request],
  formula_installers:            %i[installed_on_request verbose],
  fetch_formulae:                [],
  perform_preinstall_checks_once: [],
  install_formulae:              %i[verbose cleanup],
  finish_installation:           %i[formulae casks],
}.each do |method_name, expected|
  missing = expected - keywords(Homebrew::Install, method_name)
  raise "Homebrew::Install.#{method_name} lacks keywords: #{missing.join(", ")}" if missing.any?
end

raise "Formulary.from_path is missing" unless Formulary.respond_to?(:from_path)

puts "Homebrew install API checks passed"
