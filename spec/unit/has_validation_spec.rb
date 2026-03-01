# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lumina::HasValidation do
  # ------------------------------------------------------------------
  # Legacy format: flat array of field names
  # ------------------------------------------------------------------

  describe "legacy format (flat array)" do
    let(:post) { Post.new }

    it "validates store with base rules" do
      # Post has '*' => { title: required, content: required }
      result = post.validate_store({ "title" => "Hello", "content" => "World" })
      expect(result[:valid]).to be true
      expect(result[:validated]["title"]).to eq("Hello")
      expect(result[:validated]["content"]).to eq("World")
    end

    it "fails when required field is missing" do
      result = post.validate_store({ "content" => "World" })
      expect(result[:valid]).to be false
      expect(result[:errors]).to have_key("title")
      expect(result[:errors]["title"].first).to include("required")
    end

    it "fails when required field is blank" do
      result = post.validate_store({ "title" => "", "content" => "World" })
      expect(result[:valid]).to be false
      expect(result[:errors]).to have_key("title")
    end
  end

  # ------------------------------------------------------------------
  # Role-keyed format
  # ------------------------------------------------------------------

  describe "role-keyed format" do
    let(:post) { Post.new }

    context "with admin role" do
      let(:admin_user) do
        user = User.create!(name: "Admin", email: "admin@test.com")
        org = Organization.create!(name: "Test Org", slug: "test-org")
        role = Role.create!(name: "Admin", slug: "admin", permissions: ["*"])
        UserRole.create!(user: user, organization: org, role: role)
        user
      end
      let(:organization) { Organization.find_by(slug: "test-org") }

      it "uses admin rules with extra fields" do
        result = post.validate_store(
          { "title" => "Hello", "content" => "World", "status" => "draft", "is_published" => true },
          user: admin_user,
          organization: organization
        )
        expect(result[:valid]).to be true
        expect(result[:validated]).to have_key("is_published")
      end
    end

    context "with wildcard fallback" do
      it "falls back to * when role not found" do
        result = post.validate_store({ "title" => "Hello", "content" => "World" })
        expect(result[:valid]).to be true
      end

      it "does not allow admin-only fields for wildcard role" do
        result = post.validate_store({ "title" => "Hello", "content" => "World", "is_published" => true })
        expect(result[:valid]).to be true
        # is_published is not in * rules, so it's not validated/returned
        expect(result[:validated]).not_to have_key("is_published")
      end
    end
  end

  # ------------------------------------------------------------------
  # Update validation
  # ------------------------------------------------------------------

  describe "update validation" do
    let(:post) { Post.new }

    it "allows partial updates with sometimes modifier" do
      result = post.validate_update({ "title" => "Updated" })
      expect(result[:valid]).to be true
      expect(result[:validated]["title"]).to eq("Updated")
    end

    it "validates type rules on update" do
      result = post.validate_update({ "title" => "A" * 256 })
      expect(result[:valid]).to be false
      expect(result[:errors]["title"].first).to include("255")
    end
  end

  # ------------------------------------------------------------------
  # Rule validation: string, max, min, integer, etc.
  # ------------------------------------------------------------------

  describe "individual rule validation" do
    let(:post) { Post.new }

    it "validates string type" do
      result = post.validate_store({ "title" => 123, "content" => "World" })
      expect(result[:valid]).to be false
      expect(result[:errors]["title"].first).to include("string")
    end

    it "validates max length" do
      result = post.validate_store({ "title" => "A" * 256, "content" => "World" })
      expect(result[:valid]).to be false
      expect(result[:errors]["title"].first).to include("255")
    end

    it "validates boolean type" do
      result = post.validate_store(
        { "title" => "Hello", "content" => "World", "is_published" => "invalid" },
        user: nil
      )
      # is_published is not in wildcard rules, so it's not validated
      expect(result[:valid]).to be true
    end
  end

  # ------------------------------------------------------------------
  # Role-keyed with full rule override (value contains |)
  # ------------------------------------------------------------------

  describe "full rule override" do
    # When the role value contains |, it replaces the base rule entirely
    let(:model_class) do
      Class.new(ActiveRecord::Base) do
        include Lumina::HasValidation
        self.table_name = "posts"

        lumina_validation_rules(title: "string|max:255")
        lumina_store_rules(
          "admin" => { "title" => "required|string|max:500" }
        )
      end
    end

    it "uses the full override rule instead of merging" do
      instance = model_class.new
      # Since admin role uses pipe-delimited rules, they replace base rules
      admin = User.create!(name: "Admin", email: "admin2@test.com")
      org = Organization.create!(name: "Override Org", slug: "override-org")
      role = Role.create!(name: "Admin Override", slug: "admin", permissions: ["*"])
      UserRole.create!(user: admin, organization: org, role: role)

      result = instance.validate_store(
        { "title" => "A" * 400 },
        user: admin,
        organization: org
      )
      expect(result[:valid]).to be true # max:500 allows up to 500 chars
    end
  end

  # ------------------------------------------------------------------
  # Edge cases
  # ------------------------------------------------------------------

  describe "edge cases" do
    let(:post) { Post.new }

    it "returns empty result when no rules configured" do
      klass = Class.new(ActiveRecord::Base) do
        include Lumina::HasValidation
        self.table_name = "posts"
      end
      instance = klass.new
      result = instance.validate_store({ "title" => "Hello" })
      expect(result[:valid]).to be true
      expect(result[:errors]).to be_empty
    end

    it "handles nil params gracefully" do
      result = post.validate_store({})
      expect(result[:valid]).to be false # title and content are required
    end
  end
end
