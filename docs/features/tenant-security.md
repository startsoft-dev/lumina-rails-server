# Tenant Security (Rails)

Lumina Rails automatically prevents cross-tenant data leakage at the framework level. When a request runs in tenant context (via `ResolveOrganizationFromRoute` middleware), several security layers activate to ensure users can never read, create, or update resources that belong to another organization.

## Security Layers

| Threat | Protection | Response |
|--------|-----------|----------|
| Update `organization_id` on a resource | Rejected before validation | **403 Forbidden** |
| Supply `organization_id` on create | Stripped from request, set from route context | Auto-corrected |
| FK reference to a directly org-scoped table | ActiveRecord existence check with org_id WHERE | **422 Validation Error** |
| FK reference through indirect chain | SQL subquery through FK chain to verify org ownership | **422 Validation Error** |

All protections only activate in **tenant context** (when organization is resolved from the route). Non-tenant routes are unaffected.

---

## Organization Context

The middleware stores the resolved organization in Rack `env` and `RequestStore`:

```ruby
# Middleware sets:
env["lumina.organization"] = organization
RequestStore.store[:lumina_organization] = organization

# Access it in controller:
current_organization  # => Organization instance or nil
```

---

## organization_id Protection

### On Store (POST)

Any user-supplied `organization_id` is **silently stripped** from the request data. The correct value is auto-set by `add_organization_to_data`:

```ruby
# In ResourcesController#store:
data = params_hash
data.delete("organization_id") if current_organization
# ... validation ...
add_organization_to_data(validated)  # Sets org_id from context
```

### On Update (PUT/PATCH)

Attempting to change `organization_id` returns **403 Forbidden**:

```ruby
# In ResourcesController#update:
if current_organization && data.key?("organization_id")
  render json: { message: "You are not allowed to change the organization_id." }, status: :forbidden
end
```

---

## Cross-Tenant Foreign Key Validation

### How It Works

The `HasValidation` concern validates FK references during `validate_for_action`. When an `organization` is passed, it introspects the model's `belongs_to` associations and verifies each FK value belongs to the current org.

```ruby
# In your model:
class TenantPost < ApplicationRecord
  include Lumina::HasValidation
  belongs_to :tenant_blog  # FK: tenant_blog_id
end

# Controller passes organization to validation:
model_instance.validate_for_action(
  data, permitted_fields: permitted_fields, organization: current_organization
)
```

### Direct Scoping (Table Has organization_id)

When the FK's target table has `organization_id`, a simple query verifies ownership:

```ruby
related_class.where(primary_key => fk_value, organization_id: org_id).exists?
```

### Indirect FK Chain Scoping

When the target table does **not** have `organization_id`, Lumina walks the FK chain via `ActiveRecord::Base.connection.foreign_keys(table)`:

```
TenantComment.tenant_post_id -> TenantPost.tenant_blog_id -> TenantBlog.organization_id
```

This produces a SQL query with nested subqueries:

```sql
SELECT 1 FROM "tenant_posts"
WHERE "id" = ?
AND "tenant_blog_id" IN (
    SELECT "id" FROM "tenant_blogs" WHERE organization_id = ?
)
```

### Depth & Caching

- Maximum chain depth: **5 levels**
- Cycle detection prevents infinite loops
- Results are cached in class-level variables (`@@fk_chain_cache`, `@@org_column_cache`)

---

## Removed: lumina_owner

The `lumina_owner` / `lumina_owner_path` pattern has been removed. Organization path discovery is now fully automatic via `belongs_to` introspection. Remove any `lumina_owner` calls from your models.

---

## Integer Filter Coercion

The `QueryBuilder` now coerces string filter values to the correct type based on column metadata:

```ruby
# ?filter[user_id]=5 — "5" is coerced to integer 5
# ?filter[status]=active — stays as string
```

Supported coercions: integer, float/decimal, boolean. This prevents type mismatches in WHERE clauses.

---

## Requirements

The FK chain walker relies on **database-level foreign keys**. Your migrations must define proper FK constraints:

```ruby
# Good — FK constraint defined, chain is discoverable
t.references :tenant_blog, null: false, foreign_key: true

# Bad — no FK constraint, chain walker can't find the relationship
t.integer :tenant_blog_id
```

---

## Tests

See `spec/feature/tenant_security_spec.rb` for the complete test suite covering:

- `organization_id` stripping on store
- Direct cross-tenant FK validation (reject/allow)
- 2-level indirect FK chain (comment -> post -> blog -> org)
- 3-level indirect FK chain (reply -> comment -> post -> blog -> org)
- Non-org-scoped tables left unchanged
- No-tenant context passthrough
- Integer filter coercion

---

## Related

- See the [Laravel tenant-security docs](../../lumina-server/docs/features/tenant-security.md) for the canonical reference including cross-framework parity table.
