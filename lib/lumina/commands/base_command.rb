# frozen_string_literal: true

require "thor"

module Lumina
  module Commands
    # Lightweight base for Lumina CLI commands.
    # Provides Thor's say/ask/yes? helpers without relying on Rails::Command::Base,
    # which cannot be discovered by Rails when defined inside a gem.
    class BaseCommand
      include Thor::Shell

      def initialize(shell = Thor::Shell::Color.new)
        @shell = shell
      end

      private

      def say(message = "", color = nil)
        @shell.say(message, color)
      end

      def ask(message, *args)
        @shell.ask(message, *args)
      end

      def yes?(message, *args)
        @shell.yes?(message, *args)
      end
    end
  end
end
