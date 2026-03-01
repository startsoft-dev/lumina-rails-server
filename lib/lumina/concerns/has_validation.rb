# frozen_string_literal: true

module Lumina
  # Role-based validation concern for models.
  # Mirrors the Laravel HasValidation trait behavior exactly.
  #
  # Usage:
  #   class Post < ApplicationRecord
  #     include Lumina::HasValidation
  #
  #     lumina_validation_rules(
  #       title: 'string|max:255',
  #       content: 'string',
  #       status: 'string|max:50'
  #     )
  #
  #     # Legacy format (flat array of field names)
  #     lumina_store_rules :title, :content
  #
  #     # Role-keyed format
  #     lumina_store_rules(
  #       admin: { title: :required, status: :nullable },
  #       editor: { title: :required },
  #       '*': { title: :required }
  #     )
  #
  #     lumina_update_rules(
  #       admin: { title: :nullable, status: :nullable },
  #       '*': { title: :nullable }
  #     )
  module HasValidation
    extend ActiveSupport::Concern

    included do
      class_attribute :lumina_base_rules, default: {}
      class_attribute :lumina_store_rules_config, default: {}
      class_attribute :lumina_update_rules_config, default: {}
      class_attribute :lumina_validation_messages, default: {}
    end

    class_methods do
      def lumina_validation_rules(rules = {})
        self.lumina_base_rules = rules.transform_keys(&:to_s)
      end

      def lumina_store_rules(*args)
        if args.length == 1 && args.first.is_a?(Hash)
          # Role-keyed format: { admin: { title: :required }, '*': { title: :required } }
          self.lumina_store_rules_config = normalize_role_rules(args.first)
        else
          # Legacy format: :title, :content (flat list of field names)
          self.lumina_store_rules_config = args.map(&:to_s)
        end
      end

      def lumina_update_rules(*args)
        if args.length == 1 && args.first.is_a?(Hash)
          self.lumina_update_rules_config = normalize_role_rules(args.first)
        else
          self.lumina_update_rules_config = args.map(&:to_s)
        end
      end

      def lumina_messages(messages = {})
        self.lumina_validation_messages = messages.transform_keys(&:to_s)
      end

      private

      def normalize_role_rules(hash)
        hash.each_with_object({}) do |(role, fields), result|
          role_key = role.to_s
          result[role_key] = fields.transform_keys(&:to_s).transform_values(&:to_s)
        end
      end
    end

    # Validate for store (create) action.
    # Returns { valid: true/false, errors: {}, validated: {} }
    def validate_store(params, user: nil, organization: nil)
      rules = resolve_store_rules(user, organization)
      validate_with_rules(params, rules)
    end

    # Validate for update action.
    # Returns { valid: true/false, errors: {}, validated: {} }
    def validate_update(params, user: nil, organization: nil)
      rules = resolve_update_rules(user, organization)
      validate_with_rules(params, rules)
    end

    private

    def resolve_store_rules(user, organization)
      config = self.class.lumina_store_rules_config
      base_rules = self.class.lumina_base_rules
      resolve_rules(config, base_rules, user, organization)
    end

    def resolve_update_rules(user, organization)
      config = self.class.lumina_update_rules_config
      base_rules = self.class.lumina_base_rules
      resolve_rules(config, base_rules, user, organization)
    end

    def resolve_rules(config, base_rules, user, organization)
      return {} if config.blank? || base_rules.blank?

      # Legacy format: flat array of field names
      if legacy_format?(config)
        return base_rules.slice(*config)
      end

      # Role-keyed format
      role_fields = resolve_fields_for_role(config, user, organization)
      return {} if role_fields.blank?

      merge_rules_with_presence(role_fields, base_rules)
    end

    def legacy_format?(config)
      config.is_a?(Array)
    end

    def resolve_fields_for_role(role_keyed_config, user, organization)
      role_slug = nil

      if user.respond_to?(:role_slug_for_validation)
        role_slug = user.role_slug_for_validation(organization)
      end

      if role_slug.present? && role_keyed_config.key?(role_slug)
        return role_keyed_config[role_slug]
      end

      if role_keyed_config.key?("*")
        return role_keyed_config["*"]
      end

      {}
    end

    # Merge role field config with base rules.
    # If the modifier contains '|', it's treated as a full rule override.
    # Otherwise it's prepended to the base rule.
    def merge_rules_with_presence(role_fields, base_rules)
      merged = {}

      role_fields.each do |field, modifier|
        modifier = modifier.to_s

        if modifier.include?("|")
          merged[field] = modifier
          next
        end

        base = base_rules[field] || ""
        merged[field] = base.present? ? "#{modifier}|#{base}" : modifier
      end

      merged
    end

    # Validate params against resolved rules.
    # Rules use Laravel-style pipe-delimited format: "required|string|max:255"
    def validate_with_rules(params, rules)
      errors = {}
      validated = {}

      rules.each do |field, rule_string|
        value = params[field]
        rule_parts = rule_string.to_s.split("|").map(&:strip)

        is_required = rule_parts.include?("required")
        is_nullable = rule_parts.include?("nullable")

        # Check presence
        if is_required && (value.nil? || (value.is_a?(String) && value.blank?))
          errors[field] = ["The #{field} field is required."]
          next
        end

        # Skip validation if nullable and value is nil
        if is_nullable && value.nil?
          validated[field] = value
          next
        end

        # Skip if field not present and not required
        next if value.nil? && !is_required

        # Validate individual rules
        field_errors = validate_field(field, value, rule_parts)
        if field_errors.any?
          errors[field] = field_errors
        else
          validated[field] = value
        end
      end

      { valid: errors.empty?, errors: errors, validated: validated }
    end

    def validate_field(field, value, rule_parts)
      errors = []

      rule_parts.each do |rule|
        case rule
        when "string"
          unless value.is_a?(String)
            errors << "The #{field} field must be a string."
          end
        when /\Amax:(\d+)\z/
          max = ::Regexp.last_match(1).to_i
          if value.is_a?(String) && value.length > max
            errors << "The #{field} field must not be greater than #{max} characters."
          end
        when /\Amin:(\d+)\z/
          min = ::Regexp.last_match(1).to_i
          if value.is_a?(String) && value.length < min
            errors << "The #{field} field must be at least #{min} characters."
          end
        when "integer"
          unless value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A-?\d+\z/))
            errors << "The #{field} field must be an integer."
          end
        when "numeric"
          unless value.is_a?(Numeric) || (value.is_a?(String) && value.match?(/\A-?\d+(\.\d+)?\z/))
            errors << "The #{field} field must be a number."
          end
        when "boolean"
          unless [true, false, 0, 1, "0", "1", "true", "false"].include?(value)
            errors << "The #{field} field must be true or false."
          end
        when "date"
          begin
            Date.parse(value.to_s)
          rescue ArgumentError, TypeError
            errors << "The #{field} field must be a valid date."
          end
        when "array"
          unless value.is_a?(Array) || value.is_a?(Hash)
            errors << "The #{field} field must be an array."
          end
        when "uuid"
          unless value.is_a?(String) && value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
            errors << "The #{field} field must be a valid UUID."
          end
        when /\Aunique:(\w+),(\w+)\z/
          table = ::Regexp.last_match(1)
          column = ::Regexp.last_match(2)
          if ActiveRecord::Base.connection.table_exists?(table)
            if ActiveRecord::Base.connection.execute("SELECT 1 FROM #{table} WHERE #{column} = #{ActiveRecord::Base.connection.quote(value)} LIMIT 1").any?
              errors << "The #{field} has already been taken."
            end
          end
        when /\Aexists:(\w+),(\w+)\z/
          table = ::Regexp.last_match(1)
          column = ::Regexp.last_match(2)
          if ActiveRecord::Base.connection.table_exists?(table)
            unless ActiveRecord::Base.connection.execute("SELECT 1 FROM #{table} WHERE #{column} = #{ActiveRecord::Base.connection.quote(value)} LIMIT 1").any?
              errors << "The selected #{field} is invalid."
            end
          end
        when "required", "nullable", "sometimes"
          # Handled above
        end
      end

      errors
    end
  end
end
