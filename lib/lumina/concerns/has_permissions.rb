# frozen_string_literal: true

module Lumina
  # Permission checking concern for the User model.
  # Mirrors the Laravel HasPermissions trait.
  #
  # Usage:
  #   class User < ApplicationRecord
  #     include Lumina::HasPermissions
  #
  #     has_many :user_roles
  #   end
  #
  # Permission format: '{slug}.{action}' (e.g., 'posts.index', 'blogs.store')
  # Wildcard support:
  #   - '*' grants access to everything
  #   - 'posts.*' grants access to all actions on posts
  #
  # Global permissions fallback:
  #   Users without organization-scoped roles can have a `global_permissions`
  #   JSON attribute on the user model for non-org-scoped authorization.
  module HasPermissions
    extend ActiveSupport::Concern

    # Check if the user has a specific permission in the given organization.
    #
    # @param permission [String] Permission string like 'posts.index'
    # @param organization [Object, nil] Organization to check permissions for
    # @return [Boolean]
    def has_permission?(permission, organization = nil)
      return false if permission.blank?

      user_role = find_user_role(organization)

      if user_role
        role = user_role.respond_to?(:role) ? user_role.role : nil
        return false unless role

        permissions = role_permissions(role)
        return false if permissions.blank?

        return matches_permission?(permission, permissions)
      end

      # Fallback: check global_permissions when no org context and no user_roles found
      if !organization && has_global_permissions?
        global_perms = parse_global_permissions
        return matches_permission?(permission, global_perms)
      end

      false
    end

    # Get the role slug for validation purposes.
    #
    # @param organization [Object, nil] Organization context
    # @return [String, nil] Role slug or nil
    def role_slug_for_validation(organization = nil)
      user_role = find_user_role(organization)
      return nil unless user_role

      role = user_role.respond_to?(:role) ? user_role.role : nil
      return nil unless role

      role.respond_to?(:slug) ? role.slug : nil
    end

    private

    def matches_permission?(permission, granted_permissions)
      return true if granted_permissions.include?(permission)
      return true if granted_permissions.include?("*")

      resource = permission.split(".").first
      return true if granted_permissions.include?("#{resource}.*")

      false
    end

    def has_global_permissions?
      respond_to?(:global_permissions) && !global_permissions.nil?
    end

    def parse_global_permissions
      perms = global_permissions
      return [] if perms.blank?

      if perms.is_a?(String)
        begin
          JSON.parse(perms)
        rescue JSON::ParserError
          []
        end
      elsif perms.is_a?(Array)
        perms
      else
        []
      end
    end

    def find_user_role(organization)
      return nil unless respond_to?(:user_roles)

      if organization
        user_roles.find_by(organization_id: organization.id)
      else
        user_roles.first
      end
    end

    def role_permissions(role)
      return [] unless role.respond_to?(:permissions)

      perms = role.permissions
      return [] if perms.blank?

      if perms.is_a?(String)
        begin
          JSON.parse(perms)
        rescue JSON::ParserError
          []
        end
      elsif perms.is_a?(Array)
        perms
      else
        []
      end
    end
  end
end
