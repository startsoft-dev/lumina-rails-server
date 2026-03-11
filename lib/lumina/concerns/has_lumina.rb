# frozen_string_literal: true

module Lumina
  # Main model concern that provides the DSL for configuring query builder options.
  #
  # Usage:
  #   class Post < ApplicationRecord
  #     include Lumina::HasLumina
  #
  #     lumina_filters :status, :user_id
  #     lumina_sorts :title, :created_at
  #     lumina_default_sort '-created_at'
  #     lumina_includes :user, :comments
  #     lumina_fields :id, :title, :status, :created_at
  #     lumina_search :title, :content, 'user.name'
  #     lumina_per_page 25
  #     lumina_pagination_enabled true
  #     lumina_middleware 'throttle:60,1'
  #     lumina_middleware_actions store: ['verified'], update: ['verified']
  #     lumina_except_actions :destroy
  #   end
  module HasLumina
    extend ActiveSupport::Concern

    included do
      class_attribute :allowed_filters, default: []
      class_attribute :allowed_sorts, default: []
      class_attribute :default_sort_field, default: nil
      class_attribute :allowed_includes, default: []
      class_attribute :allowed_fields, default: []
      class_attribute :allowed_search, default: []
      class_attribute :lumina_per_page_count, default: 25
      class_attribute :pagination_enabled, default: false
      class_attribute :lumina_model_middleware, default: []
      class_attribute :lumina_middleware_actions_map, default: {}
      class_attribute :lumina_except_actions_list, default: []
    end

    class_methods do
      def lumina_filters(*fields)
        self.allowed_filters = fields.map(&:to_s)
      end

      def lumina_sorts(*fields)
        self.allowed_sorts = fields.map(&:to_s)
      end

      def lumina_default_sort(field)
        self.default_sort_field = field.to_s
      end

      def lumina_includes(*relations)
        self.allowed_includes = relations.map(&:to_s)
      end

      def lumina_fields(*fields)
        self.allowed_fields = fields.map(&:to_s)
      end

      def lumina_search(*fields)
        self.allowed_search = fields.map(&:to_s)
      end

      def lumina_per_page(count)
        self.lumina_per_page_count = count
      end

      def lumina_pagination_enabled(enabled = true)
        self.pagination_enabled = enabled
      end

      def lumina_middleware(*middleware)
        self.lumina_model_middleware = middleware.map(&:to_s)
      end

      def lumina_middleware_actions(actions_hash)
        self.lumina_middleware_actions_map = actions_hash.transform_keys(&:to_s)
      end

      def lumina_except_actions(*actions)
        self.lumina_except_actions_list = actions.map(&:to_s)
      end

      # Check if model uses soft deletes (Discard gem)
      def uses_soft_deletes?
        column_names.include?("discarded_at") || column_names.include?("deleted_at")
      rescue ActiveRecord::StatementInvalid
        false
      end
    end
  end
end
