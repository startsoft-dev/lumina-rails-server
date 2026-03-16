# frozen_string_literal: true

require "tty-prompt"

module Lumina
  module Commands
    # Lightweight base for Lumina CLI commands.
    # Uses tty-prompt for interactive, navigable terminal UI.
    class BaseCommand
      def initialize
        @prompt = TTY::Prompt.new(
          active_color: :cyan,
          help_color: :dim
        )
      end

      private

      def say(message = "", color = nil)
        if color
          message = @prompt.decorate(message, color)
        end
        puts message
      end

      def ask(message, **options)
        @prompt.ask(message, **options)
      end

      def yes?(message)
        @prompt.yes?(message)
      end

      def select(label, choices, **options)
        @prompt.select(label, choices, **options)
      end

      def multi_select(label, choices, **options)
        @prompt.multi_select(label, choices, **options)
      end

      def task(description)
        print "  → #{@prompt.decorate(description + '...', :cyan)}"
        yield
        puts "\r  ✓ #{@prompt.decorate(description, :green)}    "
      end
    end
  end
end
