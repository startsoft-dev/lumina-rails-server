# frozen_string_literal: true

module Lumina
  class Railtie < ::Rails::Railtie
    # Register Thor-based Rails commands
    # This makes `rails lumina:install`, `rails lumina:generate`, etc. available
    railtie_name :lumina

    initializer "lumina.commands" do
      require "lumina/commands/install_command"
      require "lumina/commands/generate_command"
      require "lumina/commands/blueprint_command"
      require "lumina/commands/export_postman_command"
      require "lumina/commands/invitation_link_command"
    end
  end
end
