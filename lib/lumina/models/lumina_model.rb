# frozen_string_literal: true

module Lumina
  # LuminaModel -- Pre-composed base class for Lumina-powered ActiveRecord models.
  #
  # Extends +ApplicationRecord+ and includes the most commonly needed concerns
  # for Lumina's automatic REST API generation. Subclass this instead of
  # +ApplicationRecord+ to get query building, validation, column hiding,
  # and auto-scopes out of the box.
  #
  # == Quick Start
  #
  #   class Post < Lumina::LuminaModel
  #     lumina_filters :status, :user_id
  #     lumina_sorts :created_at, :title
  #     lumina_default_sort '-created_at'
  #     lumina_includes :user, :comments
  #     lumina_search :title, :content
  #
  #     lumina_validation_rules(
  #       title: 'required|string|max:255',
  #       content: 'string',
  #       status: 'string|in:draft,published'
  #     )
  #
  #     lumina_store_rules(
  #       '*': { title: :required, content: :required }
  #     )
  #
  #     lumina_update_rules(
  #       '*': { title: :nullable, content: :nullable }
  #     )
  #
  #     belongs_to :user
  #     has_many :comments
  #   end
  #
  # == Included Concerns
  #
  #   Concern           | Purpose
  #   ------------------|-----------------------------------------------------------
  #   HasLumina         | Query builder DSL (filters, sorts, includes, etc.)
  #   HasValidation     | Role-based validation rules (pipe-delimited format)
  #   HidableColumns    | Dynamic column hiding from API responses
  #   HasAutoScope      | Auto-discovery of ModelScopes::{Model}Scope classes
  #
  # == Optional Concerns (add manually when needed)
  #
  # These concerns are NOT included in LuminaModel because they require
  # additional database columns, gems, or relationships. Include them in
  # your model subclass as needed:
  #
  #   Concern                     | Purpose
  #   ----------------------------|---------------------------------------------------
  #   Lumina::HasAuditTrail       | Automatic change logging to +audit_logs+ table
  #   Lumina::HasUuid             | Auto-generated UUID on creation
  #   Lumina::BelongsToOrganization | Multi-tenant organization scoping
  #   Lumina::HasPermissions      | Permission checking (User model only)
  #   Discard::Model              | Soft deletes via the Discard gem
  #
  #   class Invoice < Lumina::LuminaModel
  #     include Lumina::HasAuditTrail
  #     include Lumina::BelongsToOrganization
  #     include Discard::Model
  #
  #     lumina_filters :status, :client_id
  #     lumina_sorts :created_at, :amount
  #
  #     lumina_validation_rules(
  #       amount: 'required|numeric|min:0',
  #       client_id: 'required|integer|exists:clients,id'
  #     )
  #
  #     lumina_store_rules(
  #       admin: { amount: :required, client_id: :required, status: :nullable },
  #       '*':   { amount: :required, client_id: :required }
  #     )
  #   end
  #
  # @see Lumina::HasLumina       Query builder configuration
  # @see Lumina::HasValidation   Validation rules and role-based overrides
  # @see Lumina::HidableColumns  Column visibility control
  # @see Lumina::HasAutoScope    Automatic scope discovery
  #
  class LuminaModel < ::ApplicationRecord
    self.abstract_class = true

    include Lumina::HasLumina
    include Lumina::HasValidation
    include Lumina::HidableColumns
    include Lumina::HasAutoScope

    # =========================================================================
    # QUERY BUILDER -- Filtering, Sorting, Search, Includes, Fields
    # =========================================================================
    # Provided by: Lumina::HasLumina
    #
    # All class_attributes below are set via DSL methods. You can also
    # override them directly using +self.attribute_name = value+ in the
    # class body if you prefer a declarative style.
    # =========================================================================

    # @!attribute [rw] allowed_filters
    #   Filterable columns.
    #
    #   Controls which fields can be filtered via +?filter[field]=value+.
    #   Only whitelisted fields are accepted -- unlisted fields are silently ignored.
    #
    #   Set via DSL: +lumina_filters :status, :user_id, :category_id+
    #
    #   Query: +GET /api/posts?filter[status]=published&filter[user_id]=5+
    #
    #   @return [Array<String>]
    #   @example
    #     lumina_filters :status, :user_id, :category_id, :is_published
    #   @example Direct assignment
    #     self.allowed_filters = %w[status user_id category_id]
    self.allowed_filters = []

    # @!attribute [rw] allowed_sorts
    #   Sortable columns.
    #
    #   Controls which fields can be used for sorting via +?sort=field+.
    #   Prefix with +-+ for descending order.
    #
    #   Set via DSL: +lumina_sorts :created_at, :title, :status+
    #
    #   Query: +GET /api/posts?sort=-created_at+ or +GET /api/posts?sort=title+
    #
    #   @return [Array<String>]
    #   @example
    #     lumina_sorts :created_at, :title, :status, :updated_at
    self.allowed_sorts = []

    # @!attribute [rw] default_sort_field
    #   Default sort expression applied when no explicit +?sort+ is given.
    #   Prefix with +-+ for descending. Set to +nil+ for database insertion order.
    #
    #   Set via DSL: +lumina_default_sort '-created_at'+
    #
    #   @return [String, nil]
    #   @example
    #     lumina_default_sort '-created_at'   # newest first
    #     lumina_default_sort 'title'          # alphabetical ascending
    self.default_sort_field = nil

    # @!attribute [rw] allowed_fields
    #   Selectable columns (sparse fieldsets).
    #
    #   Controls which columns can be selected via +?fields[model]=field1,field2+.
    #   Limits the payload size by returning only requested columns.
    #
    #   Set via DSL: +lumina_fields :id, :title, :status, :created_at+
    #
    #   Query: +GET /api/posts?fields[posts]=id,title,status+
    #
    #   @return [Array<String>]
    #   @example
    #     lumina_fields :id, :title, :status, :created_at, :user_id
    self.allowed_fields = []

    # @!attribute [rw] allowed_includes
    #   Eager-loadable relationships.
    #
    #   Controls which relationships can be included via +?include=relation+.
    #   Must correspond to defined ActiveRecord associations on the model.
    #   Supports nested includes: +'comments.user'+.
    #
    #   Set via DSL: +lumina_includes :user, :comments, :tags+
    #
    #   Query: +GET /api/posts?include=user,comments+
    #
    #   @return [Array<String>]
    #   @example
    #     lumina_includes :user, :comments, :tags, 'comments.user'
    self.allowed_includes = []

    # @!attribute [rw] allowed_search
    #   Searchable columns (full-text search across multiple fields).
    #
    #   When +?search=term+ is used, Lumina performs a case-insensitive LIKE
    #   search across all listed fields. Supports dot notation for relationships.
    #
    #   Set via DSL: +lumina_search :title, :content, 'user.name'+
    #
    #   Query: +GET /api/posts?search=rails+
    #
    #   @return [Array<String>]
    #   @example
    #     lumina_search :title, :content, :excerpt, 'user.name'
    self.allowed_search = []

    # =========================================================================
    # PAGINATION
    # =========================================================================

    # @!attribute [rw] pagination_enabled
    #   Whether pagination is enabled for the index endpoint.
    #
    #   When +true+, responses include X-* pagination headers:
    #   +X-Current-Page+, +X-Last-Page+, +X-Per-Page+, +X-Total+.
    #
    #   When +false+, the API returns all records. Clients can still
    #   request pagination via +?per_page=N+.
    #
    #   Set via DSL: +lumina_pagination_enabled true+
    #
    #   @return [Boolean]
    #   @example
    #     lumina_pagination_enabled true
    #     lumina_pagination_enabled false  # disable to return all records
    self.pagination_enabled = false

    # @!attribute [rw] lumina_per_page_count
    #   Default number of records per page.
    #
    #   Override on your model to change the default. The +?per_page+ query
    #   parameter overrides this value per-request (clamped 1-100).
    #
    #   Set via DSL: +lumina_per_page 25+
    #
    #   @return [Integer]
    #   @example
    #     lumina_per_page 25
    #     lumina_per_page 50
    self.lumina_per_page_count = 25

    # =========================================================================
    # MIDDLEWARE
    # =========================================================================

    # @!attribute [rw] lumina_model_middleware
    #   Middleware names applied to every action on this model.
    #
    #   Set via DSL: +lumina_middleware 'throttle:60,1', 'auth'+
    #
    #   @return [Array<String>]
    #   @example
    #     lumina_middleware 'throttle:60,1', 'auth'
    self.lumina_model_middleware = []

    # @!attribute [rw] lumina_middleware_actions_map
    #   Per-action middleware.
    #
    #   Keys are action names: +'index'+, +'show'+, +'store'+, +'update'+,
    #   +'destroy'+, +'trashed'+, +'restore'+, +'force_delete'+.
    #
    #   Set via DSL: +lumina_middleware_actions store: ['verified']+
    #
    #   @return [Hash{String => Array<String>}]
    #   @example
    #     lumina_middleware_actions(
    #       store: ['verified'],
    #       update: ['verified'],
    #       destroy: ['admin']
    #     )
    self.lumina_middleware_actions_map = {}

    # =========================================================================
    # ROUTE EXCLUSION
    # =========================================================================

    # @!attribute [rw] lumina_except_actions_list
    #   Actions to exclude from route registration.
    #
    #   Available actions: +'index'+, +'show'+, +'store'+, +'update'+,
    #   +'destroy'+, +'trashed'+, +'restore'+, +'force_delete'+.
    #
    #   Set via DSL: +lumina_except_actions :destroy, :force_delete+
    #
    #   @return [Array<String>]
    #   @example
    #     # Disable delete endpoints entirely
    #     lumina_except_actions :destroy, :force_delete
    #   @example Read-only API
    #     lumina_except_actions :store, :update, :destroy
    self.lumina_except_actions_list = []

    # =========================================================================
    # OWNERSHIP / MULTI-TENANCY
    # =========================================================================

    # @!attribute [rw] lumina_owner_path
    #   Dot-notation relationship path to the organization owner.
    #
    #   Used when this model doesn't have +organization_id+ directly but
    #   belongs to a parent that does. Lumina traverses the chain to find
    #   the organization.
    #
    #   Set via DSL: +lumina_owner 'post.blog'+
    #
    #   @return [String, nil]
    #   @example
    #     # Comment -> Post -> Organization
    #     lumina_owner 'post'
    #   @example
    #     # Comment -> Post -> Blog -> Organization
    #     lumina_owner 'post.blog'
    self.lumina_owner_path = nil

    # =========================================================================
    # VALIDATION (provided by Lumina::HasValidation)
    # =========================================================================

    # @!attribute [rw] lumina_base_rules
    #   Base validation rules for all fields (pipe-delimited, Laravel-compatible format).
    #
    #   These format rules are applied for every action & role. Store/update
    #   rules layer on top of these.
    #
    #   Supported rules: +required+, +nullable+, +sometimes+, +string+,
    #   +integer+, +numeric+, +boolean+, +email+, +date+, +max:N+, +min:N+,
    #   +in:val1,val2+, +exists:table,column+, +unique:table,column+,
    #   +uuid+, +array+.
    #
    #   Set via DSL: +lumina_validation_rules(title: 'required|string|max:255')+
    #
    #   @return [Hash{String => String}]
    #   @example
    #     lumina_validation_rules(
    #       title:   'required|string|max:255',
    #       body:    'required|string',
    #       status:  'string|in:draft,published,archived',
    #       email:   'email|max:255',
    #       score:   'integer|min:0|max:100'
    #     )
    self.lumina_base_rules = {}

    # @!attribute [rw] lumina_store_rules_config
    #   Store (create) validation -- controls which fields are accepted on POST.
    #
    #   Supports two formats:
    #
    #   *Legacy format* (flat array of field names -- picks from base rules):
    #     lumina_store_rules :title, :content
    #
    #   *Role-keyed format* (per-role overrides with +'*'+ wildcard fallback):
    #     lumina_store_rules(
    #       admin:  { title: :required, content: :required, status: :nullable },
    #       editor: { title: :required, content: :required },
    #       '*':    { title: :required }
    #     )
    #
    #   Role resolution uses +HasPermissions#role_slug_for_validation+.
    #   If the role matches a key, those rules are used. Otherwise +'*'+ is used.
    #
    #   @return [Hash, Array]
    #   @example Legacy format
    #     lumina_store_rules :title, :content
    #   @example Role-keyed format
    #     lumina_store_rules(
    #       admin:  { title: :required, content: :required, status: :nullable, is_published: :nullable },
    #       editor: { title: :required, content: :required },
    #       '*':    { title: :required }
    #     )
    self.lumina_store_rules_config = {}

    # @!attribute [rw] lumina_update_rules_config
    #   Update validation -- controls which fields are accepted on PUT/PATCH.
    #
    #   Same format options as +lumina_store_rules_config+.
    #
    #   @return [Hash, Array]
    #   @example Legacy format
    #     lumina_update_rules :title, :content, :status
    #   @example Role-keyed format
    #     lumina_update_rules(
    #       admin: { title: :sometimes, status: :nullable, is_published: :nullable },
    #       '*':   { title: :sometimes, content: :sometimes }
    #     )
    self.lumina_update_rules_config = {}

    # @!attribute [rw] lumina_validation_messages
    #   Custom validation error messages (optional).
    #
    #   Follows the +field.rule+ format for targeted messages.
    #
    #   Set via DSL: +lumina_messages('title.required' => 'Every post needs a title.')+
    #
    #   @return [Hash{String => String}]
    #   @example
    #     lumina_messages(
    #       'title.required' => 'Every post needs a title.',
    #       'title.max'      => 'Post title cannot exceed 255 characters.',
    #       'status.in'      => 'Status must be one of: draft, published, archived.'
    #     )
    self.lumina_validation_messages = {}

    # =========================================================================
    # HIDDEN COLUMNS (provided by Lumina::HidableColumns)
    # =========================================================================

    # @!attribute [rw] additional_hidden_columns
    #   Additional columns to hide from API responses (on top of base defaults).
    #
    #   Base hidden columns (always hidden): +password+, +password_digest+,
    #   +remember_token+, +created_at+, +updated_at+, +deleted_at+,
    #   +discarded_at+, +email_verified_at+.
    #
    #   For per-user column hiding, implement +hidden_columns+ on your Policy.
    #
    #   Set via DSL: +lumina_additional_hidden :api_token, :stripe_id+
    #
    #   @return [Array<String>]
    #   @example
    #     lumina_additional_hidden :api_token, :stripe_id, :internal_notes
    self.additional_hidden_columns = []

    # =========================================================================
    # SOFT DELETES (requires Discard gem)
    # =========================================================================
    # Add +include Discard::Model+ to enable soft deletes.
    # Requires a +discarded_at+ datetime column in your migration.
    #
    # When enabled, unlocks trash/restore/force-delete API endpoints.
    #
    #   class Post < Lumina::LuminaModel
    #     include Discard::Model
    #   end
    # =========================================================================

    # =========================================================================
    # AUDIT TRAIL (requires Lumina::HasAuditTrail concern)
    # =========================================================================
    # When including +Lumina::HasAuditTrail+, every create/update/delete
    # is logged to the +audit_logs+ table via ActiveRecord callbacks.
    #
    # Exclude sensitive fields from audit snapshots:
    #   lumina_audit_exclude :password, :remember_token, :api_key
    #
    # Access audit logs:
    #   post.audit_logs.order(created_at: :desc)
    #
    #   class Post < Lumina::LuminaModel
    #     include Lumina::HasAuditTrail
    #     lumina_audit_exclude :password, :secret_token
    #   end
    # =========================================================================

    # =========================================================================
    # MULTI-TENANCY (requires Lumina::BelongsToOrganization concern)
    # =========================================================================
    # When including +Lumina::BelongsToOrganization+:
    # - +organization_id+ is auto-set from the request on create
    # - A default scope filters queries by the current organization
    # - +belongs_to :organization+ is set up automatically
    #
    #   class Project < Lumina::LuminaModel
    #     include Lumina::BelongsToOrganization
    #   end
    #
    # For nested ownership (e.g. Task -> Project -> Organization):
    #   lumina_owner 'project'
    # =========================================================================

    # =========================================================================
    # UUID (requires Lumina::HasUuid concern)
    # =========================================================================
    # When including +Lumina::HasUuid+, a UUID is auto-generated on
    # creation if the model has a +uuid+ column.
    #
    #   class Post < Lumina::LuminaModel
    #     include Lumina::HasUuid
    #   end
    # =========================================================================

    # =========================================================================
    # PERMISSIONS (requires Lumina::HasPermissions -- User model only)
    # =========================================================================
    # When including +Lumina::HasPermissions+:
    # - +has_permission?(permission, organization)+ checks permissions
    # - +role_slug_for_validation(organization)+ resolves the role slug
    #
    # Permission format: +{slug}.{action}+ e.g. +'posts.index'+
    # Wildcards: +'*'+ (all) or +'posts.*'+ (all actions on posts)
    #
    #   class User < Lumina::LuminaModel
    #     include Lumina::HasPermissions
    #     has_many :user_roles
    #   end
    # =========================================================================
  end
end
