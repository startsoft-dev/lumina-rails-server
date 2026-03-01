# frozen_string_literal: true

require "spec_helper"

# --------------------------------------------------------------------------
# Test Models
# --------------------------------------------------------------------------

class RoleTestPost < ActiveRecord::Base
  include Lumina::HasValidation
  include Lumina::HidableColumns

  self.table_name = "posts"

  lumina_validation_rules(
    blog_id: "integer",
    title: "string|max:255",
    content: "string",
    is_published: "boolean"
  )

  lumina_store_rules(
    "admin" => { "blog_id" => "required", "title" => "required", "content" => "required", "is_published" => "nullable" },
    "assistant" => { "title" => "required", "content" => "required" },
    "*" => { "title" => "required", "content" => "required" }
  )

  lumina_update_rules(
    "admin" => { "title" => "sometimes", "content" => "sometimes", "is_published" => "nullable" },
    "assistant" => { "title" => "sometimes", "content" => "sometimes" },
    "*" => { "title" => "sometimes", "content" => "sometimes" }
  )
end

class RoleTestPostWithOverride < ActiveRecord::Base
  include Lumina::HasValidation
  include Lumina::HidableColumns

  self.table_name = "posts"

  lumina_validation_rules(
    title: "string|max:255"
  )

  lumina_store_rules(
    "admin" => { "title" => "required|string|max:500" }
  )
end

class RoleTestNoWildcard < ActiveRecord::Base
  include Lumina::HasValidation
  include Lumina::HidableColumns

  self.table_name = "posts"

  lumina_validation_rules(
    title: "string|max:255"
  )

  lumina_store_rules(
    "admin" => { "title" => "required" }
  )
end

RSpec.describe "RoleBasedValidation" do
  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  def create_user_with_role(role_slug, permissions: ["*"])
    user = User.create!(name: "RB User", email: "rb-#{rand(10000)}@test.com")
    org = Organization.create!(name: "RB Org", slug: "rb-org-#{rand(10000)}")
    role = Role.create!(name: role_slug.capitalize, slug: role_slug, permissions: permissions)
    UserRole.create!(user: user, organization: org, role: role)
    [user, org]
  end

  # ------------------------------------------------------------------
  # Legacy format: flat array of field names
  # ------------------------------------------------------------------

  describe "legacy format" do
    it "validates store with static rules" do
      # Post has '*' => { title: required, content: required }
      post = Post.new
      result = post.validate_store({ "title" => "A title", "content" => "Some content" })
      expect(result[:valid]).to be true
      expect(result[:validated]).to have_key("title")
      expect(result[:validated]).to have_key("content")
    end

    it "fails when required field is missing" do
      post = Post.new
      result = post.validate_store({ "title" => "Only title" })
      expect(result[:valid]).to be false
      expect(result[:errors]).to have_key("content")
    end
  end

  # ------------------------------------------------------------------
  # Role-keyed format
  # ------------------------------------------------------------------

  describe "role-keyed format" do
    it "admin receives all fields in validated" do
      admin, org = create_user_with_role("admin")

      model = RoleTestPost.new
      result = model.validate_store(
        { "blog_id" => 1, "title" => "Post title", "content" => "Content", "is_published" => true },
        user: admin,
        organization: org
      )

      expect(result[:valid]).to be true
      expect(result[:validated]).to have_key("blog_id")
      expect(result[:validated]).to have_key("title")
      expect(result[:validated]).to have_key("content")
      expect(result[:validated]).to have_key("is_published")
    end

    it "assistant receives only title and content in validated" do
      assistant, org = create_user_with_role("assistant", permissions: ["posts.store"])

      model = RoleTestPost.new
      result = model.validate_store(
        { "blog_id" => 1, "title" => "Post title", "content" => "Content", "is_published" => true },
        user: assistant,
        organization: org
      )

      expect(result[:valid]).to be true
      expect(result[:validated]).not_to have_key("blog_id")
      expect(result[:validated]).not_to have_key("is_published")
      expect(result[:validated]).to have_key("title")
      expect(result[:validated]).to have_key("content")
    end

    it "wildcard fallback used when role is unknown" do
      user, org = create_user_with_role("unknown_role")

      model = RoleTestPost.new
      result = model.validate_store(
        { "title" => "Post title", "content" => "Content" },
        user: user,
        organization: org
      )

      expect(result[:valid]).to be true
      expect(result[:validated]).to have_key("title")
      expect(result[:validated]).to have_key("content")
      expect(result[:validated]).not_to have_key("blog_id")
    end

    it "no match and no wildcard returns empty validated" do
      assistant, org = create_user_with_role("assistant", permissions: ["posts.store"])

      model = RoleTestNoWildcard.new
      result = model.validate_store(
        { "title" => "Any" },
        user: assistant,
        organization: org
      )

      # No matching role rules, no wildcard → empty
      expect(result[:valid]).to be true
      expect(result[:validated]).to be_empty
    end
  end

  # ------------------------------------------------------------------
  # Presence merging
  # ------------------------------------------------------------------

  describe "presence merging" do
    it "fails when required field is blank" do
      assistant, org = create_user_with_role("assistant", permissions: ["posts.store"])

      model = RoleTestPost.new
      result = model.validate_store(
        { "title" => "", "content" => "Content" },
        user: assistant,
        organization: org
      )

      expect(result[:valid]).to be false
      expect(result[:errors]).to have_key("title")
    end
  end

  # ------------------------------------------------------------------
  # Full rule override (value contains |)
  # ------------------------------------------------------------------

  describe "full rule override" do
    it "replaces base rule when override has pipe-delimited rules" do
      admin, org = create_user_with_role("admin")

      model = RoleTestPostWithOverride.new
      result = model.validate_store(
        { "title" => "a" * 400 },
        user: admin,
        organization: org
      )

      # max:500 from override allows up to 500 chars
      expect(result[:valid]).to be true
    end

    it "enforces override constraint" do
      admin, org = create_user_with_role("admin")

      model = RoleTestPostWithOverride.new
      result = model.validate_store(
        { "title" => "a" * 501 },
        user: admin,
        organization: org
      )

      expect(result[:valid]).to be false
      expect(result[:errors]).to have_key("title")
    end
  end

  # ------------------------------------------------------------------
  # User without role falls back to wildcard
  # ------------------------------------------------------------------

  describe "user without role" do
    it "falls back to wildcard" do
      model = RoleTestPost.new
      result = model.validate_store(
        { "title" => "Post title", "content" => "Content" },
        user: nil
      )

      expect(result[:valid]).to be true
      expect(result[:validated]).to have_key("title")
      expect(result[:validated]).to have_key("content")
    end
  end

  # ------------------------------------------------------------------
  # Integration: real user + organization role resolution
  # ------------------------------------------------------------------

  describe "integration with real user and organization" do
    it "resolves role from user_roles and validates accordingly" do
      org = Organization.create!(name: "RB Int Org", slug: "rb-int-org")
      admin_role = Role.create!(name: "Admin", slug: "admin", permissions: ["*"])
      assistant_role = Role.create!(name: "Assistant", slug: "assistant", permissions: ["posts.store"])

      admin_user = User.create!(name: "Admin User", email: "admin-rb@test.com")
      assistant_user = User.create!(name: "Assistant User", email: "assistant-rb@test.com")

      UserRole.create!(user: admin_user, organization: org, role: admin_role)
      UserRole.create!(user: assistant_user, organization: org, role: assistant_role)

      model = RoleTestPost.new

      # Admin gets all fields
      admin_result = model.validate_store(
        { "blog_id" => 1, "title" => "T", "content" => "C", "is_published" => true },
        user: admin_user,
        organization: org
      )
      expect(admin_result[:valid]).to be true
      expect(admin_result[:validated]).to have_key("is_published")

      # Assistant only gets title and content
      assistant_result = model.validate_store(
        { "title" => "T", "content" => "C" },
        user: assistant_user,
        organization: org
      )
      expect(assistant_result[:valid]).to be true
      expect(assistant_result[:validated]).not_to have_key("is_published")
    end
  end

  # ------------------------------------------------------------------
  # Update validation with role
  # ------------------------------------------------------------------

  describe "update validation with role" do
    it "allows partial updates for admin" do
      admin, org = create_user_with_role("admin")

      model = RoleTestPost.new
      result = model.validate_update(
        { "title" => "Updated" },
        user: admin,
        organization: org
      )

      expect(result[:valid]).to be true
      expect(result[:validated]["title"]).to eq("Updated")
    end

    it "admin can update is_published" do
      admin, org = create_user_with_role("admin")

      model = RoleTestPost.new
      result = model.validate_update(
        { "is_published" => true },
        user: admin,
        organization: org
      )

      expect(result[:valid]).to be true
      expect(result[:validated]).to have_key("is_published")
    end

    it "assistant cannot update is_published" do
      assistant, org = create_user_with_role("assistant", permissions: ["posts.update"])

      model = RoleTestPost.new
      result = model.validate_update(
        { "is_published" => true },
        user: assistant,
        organization: org
      )

      # is_published not in assistant update rules, so not validated/returned
      expect(result[:valid]).to be true
      expect(result[:validated]).not_to have_key("is_published")
    end
  end
end
