# frozen_string_literal: true

# Application-level LuminaModel base class.
#
# This file was published from the lumina-rails gem. You can customise it
# to add concerns or configuration that apply to ALL your Lumina models.
#
# Published with:  rails lumina:install --publish-model
#
# To use:
#   class Post < LuminaModel
#     # ...
#   end
#
# The parent class already includes:
#   - Lumina::HasLumina, Lumina::HasValidation,
#     Lumina::HidableColumns, Lumina::HasAutoScope
#
# Add your own concerns or override defaults below.
class LuminaModel < Lumina::LuminaModel
  self.abstract_class = true

  #
  # Add application-wide concerns here. For example:
  #
  # include Lumina::HasAuditTrail
  # include Lumina::HasUuid
  # include Lumina::BelongsToOrganization

  # -----------------------------------------------------------------
  # Validation rules (pipe-delimited, Laravel-compatible)
  # -----------------------------------------------------------------
  #
  # lumina_validation_rules(
  #   title:   'required|string|max:255',
  #   content: 'string',
  #   status:  'string|in:draft,published,archived'
  # )
  #
  # # Flat format (wildcard role):
  # lumina_store_rules(
  #   '*': { title: :required, content: :required }
  # )
  # lumina_update_rules(
  #   '*': { title: :nullable, content: :nullable, status: :nullable }
  # )
  #
  # # Role-keyed format:
  # lumina_store_rules(
  #   admin:  { title: :required, content: :required, status: :nullable },
  #   editor: { title: :required, content: :required },
  #   '*':    { title: :required }
  # )
  #
  # lumina_validation_messages(
  #   'title.required': 'Every post needs a title.',
  #   'title.max':      'Post title cannot exceed 255 characters.'
  # )

  # -----------------------------------------------------------------
  # Query Builder — Filtering, Sorting, Search, Includes, Fields
  # -----------------------------------------------------------------
  #
  # lumina_filters :status, :user_id, :category_id
  # lumina_sorts   :created_at, :title, :updated_at
  # self.default_sort_field = '-created_at'
  # lumina_fields  :id, :title, :status, :created_at
  # lumina_includes :user, :comments, :tags
  # lumina_search  :title, :content, :excerpt

  # -----------------------------------------------------------------
  # Pagination
  # -----------------------------------------------------------------
  #
  # self.pagination_enabled = true
  # self.lumina_per_page_count = 25

  # -----------------------------------------------------------------
  # Middleware
  # -----------------------------------------------------------------
  #
  # self.lumina_model_middleware = ['throttle:60,1']
  #
  # self.lumina_middleware_actions_map = {
  #   'store'   => ['verified'],
  #   'update'  => ['verified'],
  #   'destroy' => ['admin'],
  # }

  # -----------------------------------------------------------------
  # Route Exclusion
  # -----------------------------------------------------------------
  #
  # # Disable delete endpoints entirely:
  # self.lumina_except_actions_list = ['destroy', 'force_delete']
  #
  # # Read-only API:
  # self.lumina_except_actions_list = ['store', 'update', 'destroy']

  # -----------------------------------------------------------------
  # Hidden Columns
  # -----------------------------------------------------------------
  #
  # self.additional_hidden_columns = ['api_token', 'stripe_id', 'internal_notes']

  # -----------------------------------------------------------------
  # Multi-Tenancy / Ownership
  # -----------------------------------------------------------------
  #
  # # Comment -> Post -> Organization
  # lumina_owner 'post'
  #
  # # Comment -> Post -> Blog -> Organization
  # lumina_owner 'post.blog'
end
