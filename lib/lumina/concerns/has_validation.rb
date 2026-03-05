# frozen_string_literal: true

module Lumina
  # Format validation concern for models.
  #
  # This concern runs ActiveModel validations on request data before
  # it reaches the database. Field permissions (which fields each role
  # can write) are controlled by the policy, not the model.
  #
  # Usage:
  #   class Post < ApplicationRecord
  #     include Lumina::HasValidation
  #
  #     # Standard Rails validations for type/format (use allow_nil: true)
  #     validates :title, length: { maximum: 255 }, allow_nil: true
  #     validates :status, inclusion: { in: %w[draft published] }, allow_nil: true
  #   end
  #
  # Field permissions are defined on the policy:
  #   class PostPolicy < Lumina::ResourcePolicy
  #     def permitted_attributes_for_create(user)
  #       has_role?(user, 'admin') ? ['*'] : ['title', 'content']
  #     end
  #   end
  module HasValidation
    extend ActiveSupport::Concern

    # Validate data for a given action.
    # Filters to only permitted fields, then runs ActiveModel validations.
    #
    # @param params [Hash] The request data
    # @param permitted_fields [Array<String>] Fields the user is allowed to set (['*'] for all)
    # @return [Hash] { valid: Boolean, errors: Hash, validated: Hash }
    def validate_for_action(params, permitted_fields:)
      # Filter to only permitted fields
      if permitted_fields == ['*']
        filtered = params.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
      else
        permitted = permitted_fields.map(&:to_s)
        filtered = params.each_with_object({}) do |(k, v), h|
          h[k.to_s] = v if permitted.include?(k.to_s)
        end
      end

      # Run ActiveModel validations on a temp instance
      temp = self.class.new
      safe_attrs = filtered.select { |k, _| temp.respond_to?("#{k}=") }
      temp.assign_attributes(safe_attrs)

      errors = {}
      unless temp.valid?
        temp.errors.each do |error|
          field_name = error.attribute.to_s
          if filtered.key?(field_name)
            errors[field_name] ||= []
            errors[field_name] << error.message
          end
        end
      end

      if errors.any?
        { valid: false, errors: errors, validated: {} }
      else
        { valid: true, errors: {}, validated: filtered }
      end
    end
  end
end
