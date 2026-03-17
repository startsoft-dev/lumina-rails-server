# frozen_string_literal: true

module Lumina
  # Auto-detect and apply global scopes by convention.
  # Mirrors the Laravel HasAutoScope trait.
  #
  # Looks for a scope class at `Scopes::{ModelName}Scope`
  # (e.g., `Scopes::PostScope` for `Post` model).
  #
  # The scope class must implement `self.apply(relation)` which receives
  # the current ActiveRecord relation and returns a modified relation.
  #
  # Usage:
  #   class Post < ApplicationRecord
  #     include Lumina::HasAutoScope
  #   end
  #
  #   # app/models/scopes/post_scope.rb
  #   module Scopes
  #     class PostScope
  #       def self.apply(scope)
  #         scope.where(active: true)
  #       end
  #     end
  #   end
  module HasAutoScope
    extend ActiveSupport::Concern

    included do
      default_scope lambda {
        model = is_a?(ActiveRecord::Relation) ? self.klass : self
        if model.respond_to?(:lumina_auto_scope_class)
          scope_class = model.lumina_auto_scope_class
          scope_class ? scope_class.apply(all) : all
        else
          all
        end
      }
    end

    class_methods do
      def lumina_auto_scope_class
        return @lumina_auto_scope_class if instance_variable_defined?(:@lumina_auto_scope_class)

        result = find_auto_scope_class
        # Only cache non-nil results to avoid permanently caching nil
        # when the scope class hasn't been autoloaded yet (Zeitwerk)
        @lumina_auto_scope_class = result if result
        result
      end

      private

      def find_auto_scope_class
        return nil if name.nil?

        model_name = name.demodulize
        "Scopes::#{model_name}Scope".safe_constantize ||
          "ModelScopes::#{model_name}Scope".safe_constantize
      end
    end
  end
end
