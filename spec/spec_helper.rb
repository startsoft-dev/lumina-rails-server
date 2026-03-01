# frozen_string_literal: true

require "bundler/setup"
require "active_record"
require "active_support/all"
require "action_controller"
require "pundit"
require "discard"

# Set up in-memory SQLite database
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Require the gem
require "lumina"
require "lumina/configuration"
require "lumina/query_builder"
require "lumina/concerns/has_lumina"
require "lumina/concerns/has_validation"
require "lumina/concerns/has_permissions"
require "lumina/concerns/has_audit_trail"
require "lumina/concerns/belongs_to_organization"
require "lumina/concerns/hidable_columns"
require "lumina/concerns/has_uuid"
require "lumina/concerns/has_auto_scope"
require "lumina/policies/resource_policy"
require "lumina/policies/invitation_policy"
require "lumina/models/audit_log"
require "lumina/models/organization_invitation"

# --------------------------------------------------------------------------
# Test Schema
# --------------------------------------------------------------------------

ActiveRecord::Schema.define do
  create_table :organizations, force: true do |t|
    t.string :name, null: false
    t.string :slug, null: false
    t.text :description
    t.timestamps
  end
  add_index :organizations, :slug, unique: true

  create_table :roles, force: true do |t|
    t.string :name, null: false
    t.string :slug, null: false
    t.text :description
    t.json :permissions, default: []
    t.timestamps
  end
  add_index :roles, :slug, unique: true

  create_table :users, force: true do |t|
    t.string :name, null: false
    t.string :email, null: false
    t.string :password_digest
    t.string :api_token
    t.string :reset_password_token
    t.datetime :reset_password_sent_at
    t.datetime :email_verified_at
    t.timestamps
  end
  add_index :users, :email, unique: true

  create_table :user_roles, force: true do |t|
    t.references :user, null: false, foreign_key: true
    t.references :organization, null: false, foreign_key: true
    t.references :role, null: false, foreign_key: true
    t.json :permissions, default: []
    t.timestamps
  end

  create_table :posts, force: true do |t|
    t.references :organization, foreign_key: true
    t.references :user, foreign_key: true
    t.string :title, null: false
    t.text :content
    t.boolean :is_published, default: false
    t.string :status
    t.datetime :discarded_at
    t.timestamps
  end
  add_index :posts, :discarded_at

  create_table :blogs, force: true do |t|
    t.references :organization, foreign_key: true
    t.string :title, null: false
    t.timestamps
  end

  create_table :comments, force: true do |t|
    t.references :post, foreign_key: true
    t.references :user, foreign_key: true
    t.text :body
    t.timestamps
  end

  create_table :audit_logs, force: true do |t|
    t.string :auditable_type, null: false
    t.bigint :auditable_id, null: false
    t.string :action, null: false
    t.json :old_values
    t.json :new_values
    t.bigint :user_id
    t.string :user_type
    t.string :ip_address
    t.string :user_agent
    t.bigint :organization_id
    t.timestamps
  end
  add_index :audit_logs, [:auditable_type, :auditable_id]

  create_table :organization_invitations, force: true do |t|
    t.references :organization, null: false, foreign_key: true
    t.string :email, null: false
    t.references :role, foreign_key: true
    t.bigint :invited_by
    t.string :token, null: false
    t.string :status, default: "pending"
    t.datetime :expires_at
    t.datetime :accepted_at
    t.timestamps
  end
  add_index :organization_invitations, :token, unique: true
end

# --------------------------------------------------------------------------
# Test Models
# --------------------------------------------------------------------------

class Organization < ActiveRecord::Base
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles
end

class Role < ActiveRecord::Base
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles

  # permissions stored as JSON array on the role
  # In test: used via user_role.role.permissions
end

class UserRole < ActiveRecord::Base
  belongs_to :user
  belongs_to :organization
  belongs_to :role
end

class User < ActiveRecord::Base
  include Lumina::HasPermissions

  has_secure_password validations: false

  has_many :user_roles, dependent: :destroy
  has_many :organizations, through: :user_roles
  has_many :posts

  def authenticate(password)
    password == "password" # simplified for testing
  end
end

class Post < ActiveRecord::Base
  include Lumina::HasLumina
  include Lumina::HasValidation
  include Lumina::HidableColumns
  include Lumina::HasAutoScope
  include Discard::Model

  belongs_to :organization, optional: true
  belongs_to :user, optional: true
  has_many :comments

  lumina_filters :title, :status, :is_published, :user_id
  lumina_sorts :title, :created_at, :status
  lumina_default_sort "-created_at"
  lumina_fields :id, :title, :content, :status, :is_published, :created_at
  lumina_includes :user, :comments
  lumina_search :title, :content

  lumina_validation_rules(
    title: "string|max:255",
    content: "string",
    status: "string|max:50",
    is_published: "boolean"
  )

  lumina_store_rules(
    "admin" => { "title" => "required", "content" => "required", "status" => "nullable", "is_published" => "nullable" },
    "*" => { "title" => "required", "content" => "required" }
  )

  lumina_update_rules(
    "admin" => { "title" => "sometimes", "content" => "sometimes", "status" => "nullable", "is_published" => "nullable" },
    "*" => { "title" => "sometimes", "content" => "sometimes" }
  )
end

class Blog < ActiveRecord::Base
  include Lumina::HasLumina
  include Lumina::HasValidation
  include Lumina::HidableColumns

  belongs_to :organization, optional: true
  has_many :posts

  lumina_search :title
end

class Comment < ActiveRecord::Base
  belongs_to :post
  belongs_to :user, optional: true
end

# --------------------------------------------------------------------------
# Test Policies
# --------------------------------------------------------------------------

class PostPolicy < Lumina::ResourcePolicy
  self.resource_slug = "posts"
end

class BlogPolicy < Lumina::ResourcePolicy
  self.resource_slug = "blogs"
end

# --------------------------------------------------------------------------
# RSpec Config
# --------------------------------------------------------------------------

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random

  # Reset Lumina configuration between tests
  config.before(:each) do
    Lumina.reset_configuration!
    Lumina.configure do |c|
      c.model :posts, "Post"
      c.model :blogs, "Blog"
    end
  end

  # Clean up database between tests
  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
