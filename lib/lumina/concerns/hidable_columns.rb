# frozen_string_literal: true

module Lumina
  # Column-level visibility control concern.
  # Mirrors the Laravel HidableColumns trait.
  #
  # Base hidden columns: password, remember_token, created_at, updated_at,
  #   deleted_at, discarded_at, email_verified_at
  #
  # Usage:
  #   class User < ApplicationRecord
  #     include Lumina::HidableColumns
  #
  #     lumina_additional_hidden :secret_field, :internal_notes
  #   end
  #
  # Policy-based hiding:
  #   class UserPolicy < Lumina::ResourcePolicy
  #     def hidden_attributes_for_show(user)
  #       has_role?(user, 'admin') ? [] : ['email', 'phone']
  #     end
  #
  #     def permitted_attributes_for_show(user)
  #       has_role?(user, 'admin') ? ['*'] : ['id', 'name', 'avatar']
  #     end
  #   end
  module HidableColumns
    extend ActiveSupport::Concern

    BASE_HIDDEN_COLUMNS = %w[
      password
      password_digest
      remember_token
      created_at
      updated_at
      deleted_at
      discarded_at
      email_verified_at
    ].freeze

    included do
      class_attribute :additional_hidden_columns, default: []
    end

    class_methods do
      def lumina_additional_hidden(*columns)
        self.additional_hidden_columns = columns.map(&:to_s)
      end
    end

    # Get the list of columns to hide for a given user.
    # Merges base + static + policy-defined hidden columns.
    #
    # @param user [Object, nil] The authenticated user
    # @return [Array<String>] Column names to hide
    def hidden_columns_for(user)
      columns = BASE_HIDDEN_COLUMNS.dup
      columns.concat(additional_hidden_columns)
      columns.concat(policy_hidden_columns(user))
      columns.uniq
    end

    # Serialize to JSON excluding hidden columns and respecting policy whitelist.
    #
    # Computed attributes (defined via +as_json+ overrides) are fully supported:
    # they can be hidden via +hidden_attributes_for_show+ or filtered via
    # +permitted_attributes_for_show+ just like database columns.
    #
    # @param user [Object, nil] The authenticated user
    # @return [Hash]
    def as_lumina_json(user = nil)
      hidden = hidden_columns_for(user)
      result = as_json(except: hidden)

      # Re-apply blacklist to the final hash. This catches computed attributes
      # added via as_json overrides that bypass the :except option.
      hidden_set = Set.new(hidden)
      result.reject! { |key, _| hidden_set.include?(key) }

      # Apply whitelist to the final hash (covers computed attributes too)
      permitted = policy_permitted_attributes(user)
      if permitted && permitted != ['*']
        permitted_set = Set.new(permitted.map(&:to_s))
        permitted_set.add('id') # id is always allowed
        result.select! { |key, _| permitted_set.include?(key) }
      end

      result
    end

    private

    # Returns the permitted attributes list from the policy, or nil if no policy.
    def policy_permitted_attributes(user)
      policy_class = Pundit::PolicyFinder.new(self).policy
      return nil unless policy_class

      policy = policy_class.new(user, self)
      if policy.respond_to?(:permitted_attributes_for_show)
        policy.permitted_attributes_for_show(user)
      end
    rescue StandardError
      nil
    end

    def policy_hidden_columns(user)
      policy_class = Pundit::PolicyFinder.new(self).policy
      return [] unless policy_class

      policy = policy_class.new(user, self)
      hidden = []

      # Blacklist: hidden_attributes_for_show
      if policy.respond_to?(:hidden_attributes_for_show)
        hidden.concat(policy.hidden_attributes_for_show(user))
      end

      # Whitelist: permitted_attributes_for_show
      # Hide DB columns not in permitted list (computed attributes handled in as_lumina_json)
      if policy.respond_to?(:permitted_attributes_for_show)
        permitted = policy.permitted_attributes_for_show(user)
        if permitted != ['*']
          all_columns = self.class.column_names
          not_permitted = all_columns - permitted.map(&:to_s)
          hidden.concat(not_permitted)
        end
      end

      hidden
    rescue StandardError
      []
    end
  end
end
