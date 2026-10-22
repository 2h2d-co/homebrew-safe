# frozen_string_literal: true

# Run through `brew ruby`. Checks that Homebrew shows each formula-installed
# command's full parser help.
require "help"
require_relative "../script/command_wrappers"

CommandWrappers::COMMANDS.each_key do |command|
  path = CommandWrappers.path(command)
  raise "#{path.basename} is out of date; run `mise run wrappers`" unless path.read == CommandWrappers.render(command)

  expected = CommandWrappers.command_class(command).parser.generate_help_text
  shown = Homebrew::Help.send(:comment_help, path)
  next if shown == expected

  raise <<~EOS
    Homebrew shows different help for #{path.basename} than the #{command} parser.
    Expected:
    #{expected}
    Shown:
    #{shown}
  EOS
end

puts "Homebrew help checks passed"
