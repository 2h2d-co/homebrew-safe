# frozen_string_literal: true

# Run through `brew ruby`; never update Homebrew or install packages.
require "system_command"
require_relative "../lib/safe/auto_update"

original_env = ENV.to_h
begin
  %w[HOMEBREW_NO_AUTO_UPDATE HOMEBREW_AUTO_UPDATING HOMEBREW_AUTO_UPDATE_CHECKED].each { |key| ENV.delete(key) }
  reexecuted = false
  Safe::AutoUpdate.run_if_needed!(
    runner: SystemCommand,
    brew_file: "/usr/bin/false",
    command: "safe-outdated",
    reexec: ->(*) { reexecuted = true },
  )
  raise "Failed subprocess did not raise"
rescue ErrorDuringExecution
  raise "Reexecuted after failure" if reexecuted
  raise "Marked failed update as checked" if ENV["HOMEBREW_AUTO_UPDATE_CHECKED"]
end

begin
  reexec_args = nil
  Safe::AutoUpdate.run_if_needed!(
    runner: SystemCommand,
    brew_file: "/usr/bin/true",
    command: "safe-outdated",
    argv: ["--verbose", "--formula"],
    reexec: ->(*args) { reexec_args = args },
  )
  raise "Missing reexecution" unless reexec_args
  raise "Incorrect arguments" unless reexec_args.drop(1) == ["/usr/bin/true", "safe-outdated", "--formula"]
  raise "Lost verbosity" unless reexec_args.first["HOMEBREW_SAFE_COMMAND_VERBOSE"] == "1"

  SystemCommand.safe_system(
    RUBY_PATH, "-e",
    'abort "Environment not passed" unless ENV["BREW_SAFE_TEST"] == "1"',
    env: { "BREW_SAFE_TEST" => "1" },
  )
ensure
  ENV.replace(original_env)
end

Dir[File.expand_path("../cmd/*.rb", __dir__)].sort.each { |file| require file }
class CommandRunnerChecked < StandardError; end

# Stop each real command at its first subprocess boundary.
Safe::AutoUpdate.define_singleton_method(:run_if_needed!) do |runner:, brew_file:, command:|
  raise "Wrong runner for #{command}" unless runner.equal?(SystemCommand)
  raise "Wrong brew executable" unless brew_file == HOMEBREW_BREW_FILE

  raise CommandRunnerChecked
end

[Homebrew::Cmd::SafeOutdated, Homebrew::Cmd::SafeUpgrade, Homebrew::Cmd::SafeInstall].each do |command|
  command.allocate.run
  raise "#{command} skipped auto-update"
rescue CommandRunnerChecked
  # Expected: no package resolution or mutation.
end

puts "Homebrew subprocess regression checks passed"
