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

    # Serialize to JSON excluding hidden columns.
    #
    # @param user [Object, nil] The authenticated user
    # @return [Hash]
    def as_lumina_json(user = nil)
      hidden = hidden_columns_for(user)
      as_json(except: hidden)
    end

    private

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
