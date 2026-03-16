# frozen_string_literal: true

module Lumina
  class Railtie < ::Rails::Railtie
    railtie_name :lumina

    rake_tasks do
      load File.expand_path("tasks/lumina.rake", __dir__)
    end
  end
end
