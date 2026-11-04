# frozen_string_literal: true

# Run through `brew ruby`. Checks the receipt rewrite against Homebrew's `Cask::Tab`
# using temporary receipt files only.
require "json"
require "tmpdir"
require "cask/tab"
require_relative "../lib/safe/cask_receipt"

TEMP_TAP = "2h2d-co/safe-temp-1-abcdef"

def write_receipt(dir, tap: TEMP_TAP, version: "3.5.1")
  tab = Cask::Tab.empty
  tab.tabfile = Pathname(dir)/Cask::Tab::FILENAME
  tab.installed_on_request = true
  tab.time = 1_700_000_000
  tab.uninstall_artifacts = [{ "font" => ["SymbolsNerdFont-Regular.ttf"] }]
  tab.source = {
    "tap" => tap,
    "tap_git_head" => nil,
    "version" => version,
    "path" => "/opt/homebrew/Library/Taps/#{tap.sub("/", "/homebrew-")}/Casks/f/font.rb",
  }
  tab.write
  tab.tabfile
end

def retarget(tabfile)
  Safe::CaskReceipt.retarget!(
    tabfile: tabfile,
    from_tap: TEMP_TAP,
    version: "3.5.1",
    to_tap: "homebrew/cask",
    path: "/opt/homebrew/Library/Taps/homebrew/homebrew-cask/Casks/f/font.rb",
    tap_git_head: "fb0b862b48",
  )
end

Dir.mktmpdir do |dir|
  tabfile = write_receipt(dir)
  before = JSON.parse(tabfile.read)
  retarget(tabfile)
  after = JSON.parse(tabfile.read)

  expected_source = {
    "tap" => "homebrew/cask",
    "tap_git_head" => "fb0b862b48",
    "version" => "3.5.1",
    "path" => "/opt/homebrew/Library/Taps/homebrew/homebrew-cask/Casks/f/font.rb",
  }
  raise "Wrong source: #{after["source"]}" unless after["source"] == expected_source
  raise "Changed fields other than source" unless after.except("source") == before.except("source")
  raise "Homebrew reads a different tap" unless Cask::Tab.from_file(tabfile).tap.name == "homebrew/cask"
end

{ "a different tap" => { tap: "homebrew/cask" }, "a different version" => { version: "3.5.0" } }.each do |label, args|
  Dir.mktmpdir do |dir|
    tabfile = write_receipt(dir, **args)
    original = tabfile.read
    begin
      retarget(tabfile)
      raise "Rewrote a receipt with #{label}"
    rescue Safe::CaskReceipt::Mismatch
      raise "Changed a receipt with #{label}" unless tabfile.read == original
    end
  end
end

Dir.mktmpdir do |dir|
  retarget(Pathname(dir)/Cask::Tab::FILENAME)
  raise "Accepted a missing receipt"
rescue Safe::CaskReceipt::Mismatch
  # Expected.
end

puts "Homebrew cask receipt checks passed"
