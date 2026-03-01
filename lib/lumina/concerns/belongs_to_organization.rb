# frozen_string_literal: true

module Lumina
  # Multi-tenant scoping concern.
  # Mirrors the Laravel BelongsToOrganization trait.
  #
  # Usage:
  #   class Post < ApplicationRecord
  #     include Lumina::BelongsToOrganization
  #   end
  #
  # For nested ownership (model doesn't have organization_id directly):
  #   class Comment < ApplicationRecord
  #     include Lumina::HasLumina
  #     lumina_owner 'post.blog'  # Comment -> Post -> Blog -> Organization
  #   end
  module BelongsToOrganization
    extend ActiveSupport::Concern

    included do
      belongs_to :organization

      # Auto-set organization_id on creation from request context
      before_create :set_organization_from_context

      # Default scope to filter by current organization
      default_scope lambda {
        if defined?(RequestStore) && RequestStore.store[:lumina_organization]
          where(organization_id: RequestStore.store[:lumina_organization].id)
        else
          all
        end
      }
    end

    class_methods do
      def for_organization(organization)
        unscoped.where(organization_id: organization.id)
      end
    end

    private

    def set_organization_from_context
      return if organization_id.present?
      return unless defined?(RequestStore)

      org = RequestStore.store[:lumina_organization]
      self.organization_id = org.id if org
    end
  end
end
