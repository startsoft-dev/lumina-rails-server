# Tests

## Running Tests

```bash
# Run all tests
bundle exec rspec

# Run a specific suite
bundle exec rspec spec/unit/
bundle exec rspec spec/feature/
bundle exec rspec spec/middleware/

# Run a specific test file
bundle exec rspec spec/unit/has_permissions_spec.rb

# Run a specific test by line number
bundle exec rspec spec/unit/resource_policy_spec.rb:55
```

## Test Suites

| Suite | Directory | Description |
|-------|-----------|-------------|
| Unit | `spec/unit/` | Unit tests for individual concerns, policies, and models |
| Feature | `spec/feature/` | Feature tests for integrated behavior (pagination, search, soft delete, route groups, etc.) |
| Middleware | `spec/middleware/` | Tests for multi-tenant Rack middleware and organization resolution |

## Test Environment

- **Database**: SQLite `:memory:` (configured in `spec/spec_helper.rb`)
- **Framework**: RSpec with in-memory ActiveRecord (no full Rails app required)
- **Schema**: Defined inline in `spec_helper.rb` — organizations, roles, users (with `global_permissions`), user_roles, posts, blogs, comments, audit_logs, organization_invitations
- **Test Models**: Defined inline in `spec_helper.rb` (Organization, Role, UserRole, User, Post, Blog, Comment) and within individual spec files
- **Test Policies**: Defined inline in spec files (PostPolicy, BlogPolicy, and per-test policies)
- **Default Config**: Each test starts with `Lumina.reset_configuration!` followed by a default config with `:posts`, `:blogs` models and a `:default` route group
- **Transaction Rollback**: Each test runs inside an `ActiveRecord::Base.transaction` that rolls back, keeping the database clean

---

## Unit Tests

### `configuration_spec.rb`

Tests for `Lumina::Configuration` DSL — model registration, route group DSL, slug resolution, tenant/public group detection, model-in-group queries.

| Test | What it verifies |
|------|-----------------|
| `initializes with defaults` | Config starts with empty models, empty route_groups, default multi_tenant |
| `registers a model` | `c.model :posts, 'Post'` stores the mapping |
| `converts slug to symbol` | String slug converted to symbol |
| `registers route group with config` | `c.route_group :tenant, prefix: ':organization'` stores group config |
| `defaults to empty prefix, no middleware, all models` | `c.route_group :default` uses sensible defaults |
| `accepts array of model slugs` | `c.route_group :driver, models: [:trips]` stores array |
| `public_model? for public group models` | Returns true for models in `:public` route group |
| `public_model? false without public group` | Returns false when no `:public` group exists |
| `public_model? converts strings to symbols` | String slug works for `public_model?` lookup |
| `resolves model from slug` | `resolve_model('posts')` returns the `Post` class |
| `raises error for unknown slug` | `resolve_model('nonexistent')` raises `ActiveRecord::RecordNotFound` |
| `raises error for invalid class` | Invalid class name raises `ActiveRecord::RecordNotFound` |
| `slug_for with class` | `slug_for(Post)` returns `:posts` |
| `slug_for with instance` | `slug_for(Post.new)` returns `:posts` |
| `slug_for unregistered returns nil` | Unregistered model returns `nil` |
| `has_tenant_group? false by default` | No tenant group returns false |
| `has_tenant_group? true when configured` | `c.route_group :tenant` detected |
| `has_public_group? false by default` | No public group returns false |
| `has_public_group? true when configured` | `c.route_group :public` detected |
| `models_for_group with :all` | Returns all registered model slugs |
| `models_for_group with '*'` | String wildcard returns all models |
| `models_for_group with array` | Returns only specified slugs |
| `models_for_group filters unregistered` | Unregistered slugs excluded |
| `models_for_group for unknown group` | Returns empty array |
| `model_in_group? true when present` | Model slug found in group |
| `model_in_group? false when absent` | Model slug not in group |

### `query_builder_spec.rb`

Tests for `Lumina::QueryBuilder` — filtering, sorting, search, pagination, sparse fieldsets, eager loading.

#### Filtering

| Test | What it verifies |
|------|-----------------|
| `filters by single value` | `?filter[status]=published` returns matching records |
| `filters by comma-separated OR` | `?filter[status]=published,draft` returns records matching either |
| `ignores non-allowed filters` | Filters not in `allowed_filters` are ignored |
| `handles empty filter` | Empty filter value returns all records |

#### Sorting

| Test | What it verifies |
|------|-----------------|
| `sorts ascending` | `?sort=title` sorts A-Z |
| `sorts descending` | `?sort=-title` sorts Z-A |
| `sorts by multiple fields` | `?sort=-status,title` applies compound sort |
| `uses default sort when no param` | `lumina_default_sort '-created_at'` applied when no `?sort` |

#### Search

| Test | What it verifies |
|------|-----------------|
| `finds matching records` | `?search=Rails` returns matching rows |
| `is case-insensitive` | LOWER() matching works |
| `excludes non-matching` | Non-matching rows excluded |
| `returns all when empty` | Empty/nil search returns all records |
| `composes with filters` | Search + filter narrow results together |
| `relationship dot notation` | `user.name` search joins through association |

#### Pagination

| Test | What it verifies |
|------|-----------------|
| `returns pagination metadata` | `current_page`, `last_page`, `per_page`, `total` present |
| `navigates pages` | `?page=2` returns correct offset |
| `last page has remaining items` | Partial last page returns correct count |
| `clamps per_page minimum to 1` | `per_page=0` clamped to 1 |
| `clamps per_page maximum to 100` | `per_page=500` clamped to 100 |
| `clamps negative per_page` | Negative values clamped to 1 |
| `empty results` | Empty table returns `total: 0`, `last_page: 1` |

#### Sparse Fieldsets

| Test | What it verifies |
|------|-----------------|
| `selects requested fields` | `?fields[posts]=title` selects only title |
| `always includes primary key` | Primary key auto-included in select |
| `ignores invalid fields` | Fields not in `allowed_fields` ignored |

#### Includes

| Test | What it verifies |
|------|-----------------|
| `eager loads valid includes` | `?include=user` calls `.includes(:user)` |
| `ignores invalid includes` | Non-allowed includes skipped |
| `handles Count suffix` | `commentsCount` resolves to `comments` base |

---

### `has_validation_spec.rb`

Tests for `Lumina::HasValidation` — role-based validation rules, legacy format, presence merging, update validation.

#### Legacy Format

| Test | What it verifies |
|------|-----------------|
| `validates store with base rules` | `*` rules validate required fields |
| `fails when required field missing` | Missing required field returns errors |
| `fails when required field blank` | Blank string fails required validation |

#### Role-Keyed Format

| Test | What it verifies |
|------|-----------------|
| `admin rules with extra fields` | Admin role gets all fields in validated data |
| `wildcard fallback` | Unknown role falls back to `*` rules |
| `admin-only fields not in wildcard` | `is_published` excluded for non-admin roles |

#### Update Validation

| Test | What it verifies |
|------|-----------------|
| `allows partial updates` | `sometimes` modifier allows missing fields |
| `validates type rules on update` | Max length still enforced on update |

#### Individual Rules

| Test | What it verifies |
|------|-----------------|
| `validates string type` | Non-string input fails string validation |
| `validates max length` | String exceeding max length fails |

#### Full Rule Override

| Test | What it verifies |
|------|-----------------|
| `full override replaces base` | Pipe-delimited role value replaces base rule entirely |

---

### `has_permissions_spec.rb`

Tests for `Lumina::HasPermissions` concern on User model — exact permissions, wildcards, organization scoping, global permissions fallback.

#### Basic Permission Checks

| Test | What it verifies |
|------|-----------------|
| `returns true with exact permission` | `has_permission?('posts.index', org)` with matching permission |
| `returns false without matching` | Different permission denied |
| `returns false for nil user` | No user_roles returns false |
| `returns false for blank permission` | Empty/nil permission string returns false |

#### Wildcard Permissions

| Test | What it verifies |
|------|-----------------|
| `grants all access with *` | `['*']` grants any `resource.action` |
| `grants all actions with resource.*` | `['posts.*']` grants all post actions, denies blog actions |

#### Individual Action Permissions

| Test | What it verifies |
|------|-----------------|
| `maps each action to correct permission` | Each of 5 CRUD permissions granted individually, others denied |

#### Multiple Permissions

| Test | What it verifies |
|------|-----------------|
| `allows granted actions, denies others` | Subset of permissions checked correctly |

#### Organization-Scoped Permissions

| Test | What it verifies |
|------|-----------------|
| `checks permissions in correct organization` | Same user has `['*']` in org A but read-only in org B |

#### Role Slug

| Test | What it verifies |
|------|-----------------|
| `returns the role slug` | `role_slug_for_validation(org)` returns the role slug string |
| `returns nil when no roles` | User without roles returns nil |

#### Global Permissions Fallback

| Test | What it verifies |
|------|-----------------|
| `grants access via global_permissions` | User without org roles uses `global_permissions` JSON attribute |
| `supports wildcard * in global_permissions` | `['*']` grants all access globally |
| `supports resource wildcard` | `['posts.*']` grants all post actions globally |
| `does not use global_permissions when user has org roles` | Org-scoped roles take precedence over global_permissions |
| `does not use global_permissions when organization is provided` | Explicit org context bypasses global_permissions |
| `falls back to global_permissions without org context` | No org + no user_roles triggers global_permissions check |
| `returns false for nil global_permissions` | Nil attribute returns false |
| `returns false for empty global_permissions` | Empty array returns false |
| `prefers org-scoped role over global_permissions` | User with both org role and global_permissions uses org role |

---

### `resource_policy_spec.rb`

Tests for `Lumina::ResourcePolicy` — Pundit policy base class with `{slug}.{action}` permission checking.

#### Basic Permission Checks

| Test | What it verifies |
|------|-----------------|
| `allows user with exact permission` | `posts.index` -> `index?` returns true |
| `denies user without matching` | `posts.index` -> `create?` returns false |
| `denies guest user (nil)` | All 5 CRUD methods return false for nil user |

#### Wildcard Permissions

| Test | What it verifies |
|------|-----------------|
| `* grants all access` | All 5 CRUD methods return true |
| `resource.* grants all actions` | `posts.*` grants all post methods |

#### Action -> Permission Mapping

| Test | What it verifies |
|------|-----------------|
| `maps each method correctly` | `index?->posts.index`, `show?->posts.show`, `create?->posts.store`, `update?->posts.update`, `destroy?->posts.destroy` |

#### Soft Delete Permissions

| Test | What it verifies |
|------|-----------------|
| `checks trashed permission` | `posts.trashed` -> `view_trashed?` |
| `checks restore permission` | `posts.restore` -> `restore?` |
| `checks forceDelete permission` | `posts.forceDelete` -> `force_delete?` |

#### Policy Override Patterns

| Test | What it verifies |
|------|-----------------|
| `override with parent composition` | Custom `destroy?` calls `super` AND checks ownership |
| `full override ignores permissions` | Overridden `index?` checks auth only, not permissions |

#### Auto-Resolution and Aliases

| Test | What it verifies |
|------|-----------------|
| `resolves slug from config` | Policy resolves slug from `Lumina.config` |
| `attribute permission defaults` | Returns `['*']` / `[]` by default |
| `aliases view_any?/view?/delete?` | Method aliases work correctly |

---

### `hidable_columns_spec.rb`

Tests for `Lumina::HidableColumns` — base hidden columns, additional hiding, policy-based hiding, JSON serialization.

| Test | What it verifies |
|------|-----------------|
| `BASE_HIDDEN_COLUMNS includes sensitive columns` | `password`, `password_digest`, `created_at`, `updated_at`, etc. |
| `returns base hidden for model without policy` | Base columns hidden even without a policy |
| `includes additional hidden columns` | `lumina_additional_hidden` adds columns |
| `includes policy-based hidden for guest` | Policy `hidden_attributes_for_show(nil)` adds to hidden set |
| `includes fewer hidden for admin` | Admin (policy returns `[]`) sees all non-base columns |
| `deduplicates column names` | No duplicate entries in hidden columns list |
| `as_lumina_json excludes hidden` | JSON output omits hidden columns |
| `handles missing policy gracefully` | No errors when policy not found |
| `handles policy without attribute permission methods` | Falls back to base columns |

---

### `organization_invitation_spec.rb`

Tests for `Lumina::OrganizationInvitation` model — token generation, expiration, scopes, accept flow, validations.

#### Token Generation

| Test | What it verifies |
|------|-----------------|
| `auto-generates 64-character token` | Token is present and 64 chars long |
| `generates unique tokens` | Two invitations have different tokens |

#### Expiration

| Test | What it verifies |
|------|-----------------|
| `auto-sets expires_at from config` | `expires_at` is set and in the future |
| `uses configured expires_days` | Custom `expires_days` respected |
| `detects expired invitations` | `expired?` returns true for past `expires_at` |
| `detects non-expired invitations` | `expired?` returns false, `pending?` returns true |

#### Scopes

| Test | What it verifies |
|------|-----------------|
| `filters pending invitations` | `pending` scope returns only pending |
| `filters expired invitations` | `expired` scope returns only expired |

#### Accept

| Test | What it verifies |
|------|-----------------|
| `updates status to accepted` | `accept!` sets status and accepted_at |

#### Validations

| Test | What it verifies |
|------|-----------------|
| `requires email` | Nil email raises validation error |
| `requires unique token` | Duplicate token fails validation |

#### Statuses

| Test | What it verifies |
|------|-----------------|
| `defines valid statuses` | `STATUSES = %w[pending accepted expired cancelled]` |
| `defaults to pending status` | New invitation has `status: 'pending'` |

---

### `export_postman_command_spec.rb`

Tests for `Lumina::Commands::ExportPostmanCommand` — Postman collection generation, action folders, URL construction with route group prefixes.

| Test | What it verifies |
|------|-----------------|
| `creates standard CRUD folders` | Index, Show, Store, Update, Destroy folders generated |
| `includes soft delete folders` | Trashed, Restore, Force Delete when model uses soft deletes |
| `excludes folders listed in except_actions` | Excepted actions omitted from output |
| `includes org prefix in URLs when needed` | Group prefix with `:organization` produces `{{organization}}` in URL |
| `builds index requests with filters/sorts/search` | Query params generated from model introspection |
| `builds show requests with includes` | Show folder includes variant with `?include=` |
| `builds auth folder` | Authentication requests folder generated |
| `builds invitation folder` | Invitation requests folder generated for tenant configs |
| `builds collection variables` | `baseUrl`, `modelId`, `token` variables present |
| `introspects model metadata` | Except actions, soft deletes, filters, sorts, fields, includes extracted |

---

### `generate_command_spec.rb`

Tests for `Lumina::Commands::GenerateCommand` — model, policy, scope generation, column validation rules, config registration.

| Test | What it verifies |
|------|-----------------|
| `multi_tenant_enabled? detects tenant route group` | Returns true when config has `route_group :tenant` |
| `multi_tenant_enabled? false without tenant group` | Returns false with other route groups |
| `multi_tenant_enabled? false when no config` | Returns false when config file missing |
| `registers model in config` | Adds `c.model :articles, 'Article'` to config file |
| `does not duplicate registration` | Skips if slug already present |
| `column_to_validation_rule` | Generates correct validation rule strings |
| `get_existing_models` | Lists model files excluding ApplicationRecord |

---

### `install_command_spec.rb`

Tests for `Lumina::Commands::InstallCommand` — config publishing, multi-tenant migrations/models/factories/policies/seeders, audit trail migration.

| Test | What it verifies |
|------|-----------------|
| `publishes config` | Creates `config/initializers/lumina.rb` |
| `publishes routes` | Creates `config/routes/lumina.rb` |
| `creates multi-tenant migrations` | 3 migration files created (organizations, roles, user_roles) |
| `creates multi-tenant models` | Organization, Role, UserRole model files created |
| `creates factories` | 3 factory files in `spec/factories/` |
| `creates policies` | OrganizationPolicy and RolePolicy created |
| `creates seeders` | Role and organization seeders with correct content |
| `updates org identifier column in config` | `organization_identifier_column` updated |
| `creates audit trail migration` | `create_audit_logs` migration created |
| `skips if audit migration exists` | Existing migration not overwritten |

---

## Feature Tests

### `pagination_spec.rb`

Tests for pagination through `Lumina::QueryBuilder#paginate` — metadata, page navigation, per_page clamping, model defaults.

| Test | What it verifies |
|------|-----------------|
| `returns flat array when no pagination params` | All items returned |
| `returns pagination metadata` | `current_page`, `last_page`, `per_page`, `total` correct |
| `navigates to second page` | Correct offset for page 2 |
| `returns last page correctly` | Partial last page has remaining items |
| `clamps per_page to minimum of 1` | `per_page=0` clamped |
| `clamps per_page to maximum of 100` | `per_page=500` clamped |
| `uses model default per_page` | Model's `lumina_per_page_count` used |
| `per_page param overrides model default` | Query param takes precedence |
| `pagination metadata has expected keys` | All 4 keys present |
| `empty results with correct metadata` | `total: 0`, `last_page: 1` |
| `paginates filtered results` | Filter + pagination work together |
| `paginates search results` | Search + pagination work together |
| `paginates sorted results` | Sort + pagination work together |

---

### `search_spec.rb`

Tests for `?search=` query parameter — matching, case-insensitivity, composition with filters, relationship dot notation.

| Test | What it verifies |
|------|-----------------|
| `returns matching rows` | Matching rows included |
| `is case-insensitive` | LOWER matching works |
| `excludes non-matching rows` | Non-matching excluded |
| `searches across multiple columns` | Title and content both searched |
| `returns all when search empty` | Empty/nil/missing returns all |
| `composes with filters` | Search + filter narrow results |
| `relationship dot notation` | `user.name` joins through named `SearchablePostWithUser` model |
| `paginates search results` | Pagination works with search |
| `sorts search results` | Sorting works with search |
| `returns all when no search columns` | Model without `lumina_search` returns all |

---

### `soft_delete_spec.rb`

Tests for soft delete behavior using the Discard gem — detection, trashed listing, restore, force delete, lifecycle, permissions.

| Test | What it verifies |
|------|-----------------|
| `detects soft deletes on model` | `uses_soft_deletes?` returns true for models with `discarded_at` |
| `returns only discarded records` | `discarded` scope filters correctly |
| `restores a discarded record` | `undiscard!` clears `discarded_at` |
| `permanently removes with destroy` | `destroy!` removes from database entirely |
| `discard soft-deletes not permanent` | `discard!` sets `discarded_at`, record still exists |
| `full soft delete lifecycle` | Create -> discard -> trashed -> restore -> discard -> destroy |
| `checks trashed/restore/forceDelete permissions` | Policy permission checks for soft delete actions |
| `wildcard grants all soft delete actions` | `['*']` and `['posts.*']` grant all soft delete permissions |

---

### `route_registration_spec.rb`

Tests for route configuration, model registration, middleware, except actions, and route group configuration.

| Test | What it verifies |
|------|-----------------|
| `registers models in config` | `c.model :posts, 'Post'` works |
| `registers multiple models` | Multiple `c.model` calls stored |
| `generates correct slug-based paths` | Slug stored correctly in config |
| `detects soft delete model` | `uses_soft_deletes?` for route registration |
| `non-soft-delete model returns false` | `uses_soft_deletes?` false for Blog |
| `stores model middleware` | `lumina_middleware` class attribute set |
| `stores per-action middleware` | `lumina_middleware_actions_map` set correctly |
| `model without middleware has empty arrays` | Defaults to empty |
| `stores excepted actions` | `lumina_except_actions_list` set correctly |
| `model without except has empty array` | Defaults to empty |
| `configures tenant route group with prefix` | `c.route_group :tenant` with prefix detected |
| `configures multiple route groups` | 3 groups registered |
| `marks models as public via public route group` | `public_model?` returns true for `:public` group models |
| `non-public models not in public group` | `public_model?` returns false |
| `resolves model from slug` | `resolve_model` works |
| `raises error for unknown slug` | `resolve_model('nonexistent')` raises error |
| `empty config` | No models when none configured |

---

### `route_groups_spec.rb`

Tests for the route groups feature — configuration DSL, tenant/public group detection, multiple groups, hybrid platform config, middleware, backward compatibility.

#### Configuration

| Test | What it verifies |
|------|-----------------|
| `registers route groups via DSL` | `c.route_group :default` stores config correctly |
| `supports :all wildcard` | `models: :all` resolves to all registered models |
| `supports '*' string wildcard` | `models: '*'` resolves to all registered models |
| `supports array of model slugs` | `models: [:posts]` returns only specified models |
| `filters out unregistered slugs` | Unregistered model slugs excluded from group |

#### Tenant Group Detection

| Test | What it verifies |
|------|-----------------|
| `detects presence of tenant group` | `has_tenant_group?` returns true for `:tenant` |
| `returns false when no tenant group` | `has_tenant_group?` returns false for `:default` |

#### Public Group Detection

| Test | What it verifies |
|------|-----------------|
| `detects presence of public group` | `has_public_group?` returns true for `:public` |
| `marks models in public group as public` | `public_model?` true for `:public` group models only |

#### Same Model in Multiple Groups

| Test | What it verifies |
|------|-----------------|
| `allows the same model in different groups` | `model_in_group?` true for model in tenant, admin, and public |

#### Hybrid Logistics Platform Config

| Test | What it verifies |
|------|-----------------|
| `has 4 route groups` | tenant + driver + admin + public registered |
| `tenant group includes all models` | `:all` wildcard resolves both models |
| `driver group includes only specified` | Subset of models returned |
| `admin group includes all models` | `:all` wildcard resolves both models |
| `public group includes only specified` | Subset of models returned |
| `only specified models are public` | `public_model?` correct for each |
| `has tenant group detected` | `has_tenant_group?` returns true |
| `has public group detected` | `has_public_group?` returns true |
| `organization_identifier_column is slug` | multi_tenant config preserved |

#### Middleware Configuration

| Test | What it verifies |
|------|-----------------|
| `stores middleware array for each group` | Multiple middleware classes stored per group |
| `wraps single middleware in array` | Single middleware string wrapped in array |

#### Backward Compatibility

| Test | What it verifies |
|------|-----------------|
| `works with simple single default group` | Single `:default` group behaves like pre-route-groups config |

---

### `role_based_validation_spec.rb`

Tests for role-keyed validation — legacy format, role-keyed fields, full rule overrides, wildcard fallback, presence merging, integration with real user/organization.

| Test | What it verifies |
|------|-----------------|
| `legacy flat array validates` | Static rules work for store |
| `admin receives all fields` | Admin role gets all role-defined fields |
| `assistant receives limited fields` | Non-admin gets restricted fields |
| `wildcard fallback` | Unknown role uses `*` rules |
| `no match returns empty` | No matching role and no wildcard -> empty |
| `presence merging fails blank` | Required + blank string fails |
| `full rule override` | Pipe-delimited override replaces base |
| `user without role falls back` | Nil user uses wildcard |
| `integration with real user` | User->UserRole->Role chain resolves correctly |

---

### `audit_trail_spec.rb`

Tests for `Lumina::HasAuditTrail` concern — event logging, excluded columns, metadata, relationships, lifecycle.

| Test | What it verifies |
|------|-----------------|
| `logs created event` | "created" log with `new_values` |
| `logs updated with dirty fields only` | Only changed fields in `old_values`/`new_values` |
| `does not log when nothing changed` | No log for no-op save |
| `logs deleted event` | "force_deleted" log on `destroy!` |
| `logs soft-deleted (discarded) event` | Discard produces audit log entry |
| `excluded columns not logged on create` | `lumina_audit_exclude` fields omitted from create log |
| `excluded columns not logged on update` | `lumina_audit_exclude` fields omitted from update log |
| `nil user for unauthenticated` | `user_id` is nil |
| `audit_logs relationship` | `post.audit_logs` returns correct collection |
| `full lifecycle audit trail` | Create + update produces correct trail |
| `default audit exclusions` | Default `password`, `remember_token` excluded |
| `custom audit exclusions` | Custom `lumina_audit_exclude` adds fields |

---

### `nested_endpoint_spec.rb`

Tests for nested atomic operations — structure validation, per-operation validation, model resolution, transaction rollback, max operations, allowed models.

| Test | What it verifies |
|------|-----------------|
| `validates operation structure` | Missing operations, missing id for update, missing data |
| `validates each operation's data` | Store/update validation per operation |
| `resolves known model from slug` | `resolve_model` works for nested operations |
| `creates records through nested operations` | Record creation in transaction |
| `updates records through nested operations` | Record update in transaction |
| `rolls back on failure` | Transaction rollback on error |
| `enforces max operations limit` | Config `max_operations` check |
| `filters based on allowed models` | Config `allowed_models` restriction |

---

### `include_authorization_spec.rb`

Tests for `?include=` authorization — eager loading, Count/Exists suffix resolution, policy-based authorization.

| Test | What it verifies |
|------|-----------------|
| `eager loads allowed includes` | `?include=comments` loads association |
| `does not load unallowed includes` | Invalid includes ignored |
| `resolves Count suffix` | `commentsCount` -> `comments` base |
| `resolves Exists suffix` | `commentsExists` -> `comments` base |
| `returns nil for invalid includes` | Non-matching suffix returns nil |
| `authorized user can include` | Policy viewAny check passes |
| `unauthorized user denied` | Policy viewAny check fails |
| `multiple includes loaded` | `?include=comments,user` loads both |

---

### `invitation_link_command_spec.rb`

Tests for `Lumina::Commands::InvitationLinkCommand` — organization lookup, invitation creation, display, identifier column config, frontend URL.

| Test | What it verifies |
|------|-----------------|
| `returns error when organization not found` | Non-existent org slug -> error message |
| `returns error and suggests --create` | No pending invitation -> suggests `--create` flag |
| `returns error requiring role` | Creating without `--role` -> error |
| `returns error when role not found` | Non-existent role -> error |
| `creates invitation with --create` | New invitation created and link displayed |
| `looks up role by ID when numeric` | Numeric role string resolved by ID |
| `displays existing invitation` | Existing invitation details shown |
| `finds org by slug (configured)` | `organization_identifier_column: 'slug'` resolves correctly |
| `finds org by ID (configured)` | `organization_identifier_column: 'id'` resolves correctly |
| `fails to find org by slug when ID configured` | Mismatched identifier fails |
| `uses FRONTEND_URL env variable` | Custom frontend URL in output |
| `defaults to localhost:5173` | Default frontend URL used |

---

## Middleware Tests

### `resolve_organization_from_route_spec.rb`

Tests for the route-prefix multi-tenant Rack middleware (`/api/{org}/resource`).

| Test | What it verifies |
|------|-----------------|
| `passes through when no organization parameter` | No org param -> pass through |
| `returns 404 when organization not found` | Non-existent org slug -> 404 |
| `resolves organization by slug` | Valid slug -> org attached to env |
| `allows authenticated user in org` | User with membership -> pass through |
| `denies authenticated user not in org` | User without membership -> 404 |
| `uses configured identifier column` | Custom column (`slug`) used for lookup |

### `resolve_organization_from_subdomain_spec.rb`

Tests for the subdomain multi-tenant Rack middleware (`org.example.com/api/resource`).

| Test | What it verifies |
|------|-----------------|
| `passes through for localhost` | Localhost -> pass through |
| `passes through for www/app/api` | Reserved subdomains -> pass through |
| `passes through for IP addresses` | IP address -> pass through |
| `passes through for two-part domains` | `example.com` -> pass through |
| `resolves organization by subdomain` | `test-org.example.com` -> org attached |
| `returns 404 when not found` | Non-existent subdomain -> 404 |
| `allows authenticated user in org` | User with membership -> pass through |
| `denies authenticated user not in org` | User without membership -> 404 |
| `extracts subdomain correctly` | Three-part host -> first part |
| `detects IP addresses` | IPv4 and localhost detection |

---

## Test Summary

| Suite | File | Tests |
|-------|------|:-----:|
| Unit | `configuration_spec.rb` | 26 |
| Unit | `query_builder_spec.rb` | 22 |
| Unit | `has_validation_spec.rb` | 12 |
| Unit | `has_permissions_spec.rb` | 21 |
| Unit | `resource_policy_spec.rb` | 17 |
| Unit | `hidable_columns_spec.rb` | 9 |
| Unit | `organization_invitation_spec.rb` | 12 |
| Unit | `export_postman_command_spec.rb` | 10 |
| Unit | `generate_command_spec.rb` | 7 |
| Unit | `install_command_spec.rb` | 10 |
| Feature | `pagination_spec.rb` | 14 |
| Feature | `search_spec.rb` | 13 |
| Feature | `soft_delete_spec.rb` | 17 |
| Feature | `route_registration_spec.rb` | 17 |
| Feature | `route_groups_spec.rb` | 22 |
| Feature | `role_based_validation_spec.rb` | 13 |
| Feature | `audit_trail_spec.rb` | 12 |
| Feature | `nested_endpoint_spec.rb` | 10 |
| Feature | `include_authorization_spec.rb` | 10 |
| Feature | `invitation_link_command_spec.rb` | 12 |
| Middleware | `resolve_organization_from_route_spec.rb` | 6 |
| Middleware | `resolve_organization_from_subdomain_spec.rb` | 11 |
| | **Total** | **392** |
