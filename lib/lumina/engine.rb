# frozen_string_literal: true

require "pundit"
require "pagy"
require "discard"

module Lumina
  class Engine < ::Rails::Engine
    isolate_namespace Lumina

    rake_tasks do
      load File.expand_path("tasks/lumina.rake", __dir__)
    end

    initializer "lumina.autoloads" do
      # Concerns
      require "lumina/concerns/has_lumina"
      require "lumina/concerns/has_validation"
      require "lumina/concerns/has_permissions"
      require "lumina/concerns/has_audit_trail"
      require "lumina/concerns/belongs_to_organization"
      require "lumina/concerns/hidable_columns"
      require "lumina/concerns/has_uuid"
      require "lumina/concerns/has_auto_scope"

      # Policies
      require "lumina/policies/resource_policy"
      require "lumina/policies/invitation_policy"

      # Query builder and routes
      require "lumina/query_builder"
      require "lumina/routes"

      # Controllers
      require "lumina/controllers/resources_controller"
      require "lumina/controllers/auth_controller"
      require "lumina/controllers/invitations_controller"

      # Mailers (only if ActionMailer is available)
      require "lumina/mailers/invitation_mailer" if defined?(ActionMailer)
    end

    # Models that inherit from ApplicationRecord must be loaded after
    # ActiveRecord is fully initialized
    initializer "lumina.models", after: :load_active_record do
      ActiveSupport.on_load(:active_record) do
        require "lumina/models/lumina_model"
        require "lumina/models/audit_log"
        require "lumina/models/organization_invitation"
      end
    end

    initializer "lumina.routes", after: :load_config_initializers do |app|
      app.routes.append do
        Lumina::Routes.draw(self)
      end
    end

    initializer "lumina.pundit" do
      ActiveSupport.on_load(:action_controller) do
        include Pundit::Authorization if defined?(Pundit)
      end
    end
  end
end
