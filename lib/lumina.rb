# frozen_string_literal: true

require "lumina/version"
require "lumina/configuration"
require "lumina/resource_scope"
require "lumina/middleware/resolve_organization_from_route"
require "rails"
require "lumina/engine"

module Lumina
  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    alias_method :config, :configuration

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
