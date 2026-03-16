# frozen_string_literal: true

require "lumina/commands/install_command"
require "lumina/commands/generate_command"
require "lumina/commands/blueprint_command"
require "lumina/commands/export_postman_command"
require "lumina/commands/invitation_link_command"

module Lumina
  class Railtie < ::Rails::Railtie
    railtie_name :lumina
  end
end
