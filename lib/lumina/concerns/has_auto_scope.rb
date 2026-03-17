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

    class_methods do
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@_lumina_auto_scope_applied, false)
      end

      def lumina_auto_scope_class
        return @lumina_auto_scope_class if instance_variable_defined?(:@lumina_auto_scope_class)

        result = find_auto_scope_class
        # Only cache non-nil results to avoid permanently caching nil
        # when the scope class hasn't been autoloaded yet (Zeitwerk)
        @lumina_auto_scope_class = result if result
        result
      end

      # Apply the auto scope as a default_scope on this specific class.
      # Called lazily on first query to ensure Zeitwerk has loaded the scope class.
      def apply_lumina_auto_scope!
        return if @_lumina_auto_scope_applied
        @_lumina_auto_scope_applied = true

        scope_class = lumina_auto_scope_class
        if scope_class
          default_scope lambda {
            scope_class.apply(where(nil))
          }
        end
      end

      private

      def find_auto_scope_class
        return nil if name.nil?

        model_name = name.demodulize
        "Scopes::#{model_name}Scope".safe_constantize ||
          "ModelScopes::#{model_name}Scope".safe_constantize
      end
    end

    included do
      # Hook into relation building to lazily apply auto scopes.
      # This ensures scopes are applied after Zeitwerk has loaded all classes.
      class << self
        def default_scopes
          apply_lumina_auto_scope! if respond_to?(:apply_lumina_auto_scope!)
          super
        end
      end
    end
  end
end
