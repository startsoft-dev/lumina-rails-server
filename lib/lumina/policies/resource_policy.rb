# frozen_string_literal: true

module Lumina
  # Base policy for all Lumina resources.
  # Mirrors the Laravel ResourcePolicy exactly.
  #
  # Permission format: '{slug}.{action}' (e.g., 'posts.index', 'blogs.store')
  # Supports wildcards:
  #   - '*' grants access to everything
  #   - 'posts.*' grants access to all actions on posts
  #
  # Usage:
  #   class PostPolicy < Lumina::ResourcePolicy
  #     # Override for custom logic:
  #     def update?(user, record)
  #       super && record.user_id == user.id
  #     end
  #
  #     # Column-level visibility:
  #     def hidden_columns(user)
  #       user_is_admin?(user) ? [] : ['internal_notes']
  #     end
  #   end
  class ResourcePolicy
    attr_reader :user, :record

    def initialize(user, record)
      @user = user
      @record = record
    end

    # The resource slug used for permission checks.
    # Override in child policies, or it will be auto-resolved from config.
    def self.resource_slug
      @resource_slug
    end

    def self.resource_slug=(slug)
      @resource_slug = slug
    end

    # ------------------------------------------------------------------
    # Convention-based CRUD authorization
    # ------------------------------------------------------------------

    def index?
      check_permission("index")
    end

    alias_method :view_any?, :index?

    def show?
      check_permission("show")
    end

    alias_method :view?, :show?

    def create?
      check_permission("store")
    end

    def update?
      check_permission("update")
    end

    def destroy?
      check_permission("destroy")
    end

    alias_method :delete?, :destroy?

    # ------------------------------------------------------------------
    # Soft Delete authorization
    # ------------------------------------------------------------------

    def view_trashed?
      check_permission("trashed")
    end

    def restore?
      check_permission("restore")
    end

    def force_delete?
      check_permission("forceDelete")
    end

    # ------------------------------------------------------------------
    # Column hiding
    # ------------------------------------------------------------------

    # Override in child policies to define role-based column visibility.
    # Return an array of column names to hide from the response.
    #
    # @param user [Object, nil] The authenticated user
    # @return [Array<String>]
    def hidden_columns(user)
      []
    end

    private

    # Check if the user has the given permission for this resource.
    def check_permission(action)
      return false unless user

      slug = resolve_resource_slug
      return false unless slug

      permission = "#{slug}.#{action}"

      if user.respond_to?(:has_permission?)
        organization = current_organization
        user.has_permission?(permission, organization)
      else
        # Fallback: if the user model doesn't implement has_permission?, allow
        true
      end
    end

    def resolve_resource_slug
      # 1. Explicit resource_slug on the policy class
      return self.class.resource_slug if self.class.resource_slug

      # 2. Auto-resolve from Lumina config
      model_class = record.is_a?(Class) ? record : record.class
      slug = Lumina.config.slug_for(model_class)

      # Cache for subsequent calls
      self.class.resource_slug = slug if slug
      slug
    end

    def current_organization
      if defined?(RequestStore)
        RequestStore.store[:lumina_organization]
      end
    end
  end
end
