# frozen_string_literal: true

module Lumina
  class Configuration
    attr_accessor :models, :public_models, :multi_tenant, :invitations, :nested, :test_framework

    def initialize
      @models = {}
      @public_models = []
      @multi_tenant = {
        enabled: false,
        use_subdomain: false,
        organization_identifier_column: "id",
        middleware: nil
      }
      @invitations = {
        expires_days: 7,
        allowed_roles: nil
      }
      @nested = {
        path: "nested",
        max_operations: 50,
        allowed_models: nil
      }
      @test_framework = "rspec"
    end

    # Register a model with its slug
    # Usage: config.model :posts, 'Post'
    def model(slug, klass_name)
      @models[slug.to_sym] = klass_name.to_s
    end

    # Mark models as public (no auth required)
    # Usage: config.public_model :posts
    def public_model(*slugs)
      slugs.each { |s| @public_models << s.to_sym }
    end

    # Resolve a model class from its slug
    def resolve_model(slug)
      klass_name = @models[slug.to_sym]
      raise ActiveRecord::RecordNotFound, "The #{slug} model does not exist" unless klass_name

      klass = klass_name.constantize
      raise ActiveRecord::RecordNotFound, "The #{slug} model does not exist" unless klass

      klass
    rescue NameError
      raise ActiveRecord::RecordNotFound, "The #{slug} model does not exist"
    end

    # Find the slug for a given model class
    def slug_for(model_class)
      class_name = model_class.is_a?(Class) ? model_class.name : model_class.class.name
      @models.each do |slug, klass_name|
        return slug if klass_name == class_name
      end
      nil
    end

    def multi_tenant_enabled?
      @multi_tenant[:enabled]
    end

    def use_subdomain?
      @multi_tenant[:use_subdomain]
    end

    def needs_org_prefix?
      multi_tenant_enabled? && !use_subdomain?
    end

    def public_model?(slug)
      @public_models.include?(slug.to_sym)
    end
  end
end
