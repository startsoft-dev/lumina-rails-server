# frozen_string_literal: true

module Lumina
  # Auto-detect and apply global scopes by convention.
  # Mirrors the Laravel HasAutoScope trait.
  #
  # Looks for a scope class at `ModelScopes::{ModelName}Scope`
  # (e.g., `ModelScopes::PostScope` for `Post` model).
  #
  # Usage:
  #   class Post < ApplicationRecord
  #     include Lumina::HasAutoScope
  #   end
  #
  #   # app/model_scopes/post_scope.rb
  #   module ModelScopes
  #     class PostScope
  #       def self.apply(scope)
  #         scope.where(active: true)
  #       end
  #     end
  #   end
  module HasAutoScope
    extend ActiveSupport::Concern

    included do
      scope_class = find_auto_scope_class
      if scope_class
        default_scope lambda {
          scope_class.apply(all)
        }
      end
    end

    class_methods do
      def find_auto_scope_class
        scope_name = "ModelScopes::#{name}Scope"
        scope_name.constantize
      rescue NameError
        nil
      end
    end
  end
end
