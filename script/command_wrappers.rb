# frozen_string_literal: true

# Run through `brew ruby`.
#
# The Homebrew formula installs each command as a `bin/brew-<command>.rb` wrapper.
# Homebrew builds `--help` output for such a wrapper from its `#:` comment lines,
# not from the command's parser. These wrappers therefore carry each command's
# full parser help as `#:` lines.
require "pathname"

module CommandWrappers
  ROOT = Pathname(__dir__).parent
  COMMANDS = {
    "safe-install" => "SafeInstall",
    "safe-outdated" => "SafeOutdated",
    "safe-upgrade" => "SafeUpgrade",
  }.freeze

  module_function

  def path(command)
    ROOT/"bin"/"brew-#{command}.rb"
  end

  def command_class(command)
    require (ROOT/"cmd"/command).to_s
    Homebrew::Cmd.const_get(COMMANDS.fetch(command))
  end

  def render(command)
    # Homebrew renders `#:` lines with the same formatter it applies to the
    # parser's raw help text, so copying that raw text reproduces the parser help.
    raw_help = command_class(command).parser.instance_variable_get(:@parser).to_s
    lines = raw_help.lines.map(&:rstrip)
    lines.pop while lines.last&.empty?
    lines[0] = "* #{lines[0]}"
    help_comments = lines.map { |line| line.empty? ? "#:" : "#:  #{line}" }

    <<~RUBY
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      # Generated from cmd/#{command}.rb by `mise run wrappers`. Do not edit.
      #{help_comments.join("\n")}
      require File.expand_path("../libexec/cmd/#{command}", __dir__)
      Homebrew::Cmd::#{COMMANDS.fetch(command)}.new.run
    RUBY
  end

  def write
    COMMANDS.each_key do |command|
      path(command).dirname.mkpath
      path(command).write(render(command))
      path(command).chmod(0755)
    end
  end
end
