# frozen_string_literal: true

require "lumina/version"
require "lumina/configuration"

if defined?(Rails::Engine)
  require "lumina/engine"
end

if defined?(Rails::Railtie)
  require "lumina/railtie"
end

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
