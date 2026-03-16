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

      # Models
      require "lumina/query_builder"
      require "lumina/routes"
      require "lumina/models/lumina_model"
      require "lumina/models/audit_log"
      require "lumina/models/organization_invitation"

      # Controllers
      require "lumina/controllers/resources_controller"
      require "lumina/controllers/auth_controller"
      require "lumina/controllers/invitations_controller"

      # Mailers
      require "lumina/mailers/invitation_mailer"
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
