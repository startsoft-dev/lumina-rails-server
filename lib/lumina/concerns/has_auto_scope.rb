# frozen_string_literal: true

module Lumina
  # Auto-detect and apply global scopes by convention.
  # Mirrors the Laravel HasAutoScope trait.
  #
  # Looks for a scope class at `Scopes::{ModelName}Scope`
  # (e.g., `Scopes::PostScope` for `Post` model).
  #
  # The scope class can either:
  #
  # 1. Extend +Lumina::ResourceScope+ (recommended) — provides access to
  #    +user+, +organization+, and +role+ inside the +apply+ instance method:
  #
  #   module Scopes
  #     class PostScope < Lumina::ResourceScope
  #       def apply(relation)
  #         if role == "viewer"
  #           relation.where(published: true)
  #         else
  #           relation
  #         end
  #       end
  #     end
  #   end
  #
  # 2. Implement +self.apply(relation)+ as a class method (legacy/simple):
  #
  #   module Scopes
  #     class PostScope
  #       def self.apply(relation)
  #         relation.where(active: true)
  #       end
  #     end
  #   end
  #
  module HasAutoScope
    extend ActiveSupport::Concern

    included do
      default_scope lambda {
        model = is_a?(ActiveRecord::Relation) ? self.klass : self
        if model.respond_to?(:lumina_auto_scope_class)
          scope_class = model.lumina_auto_scope_class
          if scope_class
            model.apply_lumina_scope(scope_class, where(nil))
          else
            where(nil)
          end
        else
          where(nil)
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

      # Apply the scope class to a relation.
      # Supports both ResourceScope subclasses (instance method) and
      # plain classes with self.apply (class method).
      def apply_lumina_scope(scope_class, relation)
        if scope_class < Lumina::ResourceScope
          scope_class.new.apply(relation)
        elsif scope_class.respond_to?(:apply)
          scope_class.apply(relation)
        else
          relation
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
  end
end
