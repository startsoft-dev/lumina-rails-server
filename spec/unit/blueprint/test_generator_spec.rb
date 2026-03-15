# frozen_string_literal: true

require "spec_helper"
require "lumina/blueprint/generators/test_generator"

RSpec.describe Lumina::Blueprint::Generators::TestGenerator do
  let(:generator) { described_class.new }

  def make_permission(overrides = {})
    {
      actions: [], show_fields: [], create_fields: [],
      update_fields: [], hidden_fields: []
    }.merge(overrides)
  end

  def make_blueprint(overrides = {})
    {
      model: "Contract", slug: "contracts", table: "contracts",
      options: { belongs_to_organization: true, soft_deletes: true, audit_trail: false,
                 owner: nil, except_actions: [], pagination: false, per_page: 25 },
      columns: [
        { name: "title", type: "string" },
        { name: "total_value", type: "decimal" }
      ],
      relationships: [],
      permissions: {
        "owner" => make_permission(
          actions: %w[index show store update destroy trashed restore forceDelete],
          show_fields: ["*"], create_fields: ["*"], update_fields: ["*"]
        ),
        "viewer" => make_permission(
          actions: %w[index show], show_fields: %w[id title],
          hidden_fields: ["total_value"]
        )
      },
      source_file: "contracts.yaml"
    }.merge(overrides)
  end

  # ──────────────────────────────────────────────
  # CRUD access tests
  # ──────────────────────────────────────────────

  describe "#build_crud_access_tests" do
    it "generates tests for allowed endpoints" do
      permissions = { "admin" => make_permission(actions: %w[index show store]) }
      result = generator.build_crud_access_tests("contracts", permissions, false, "id")

      expect(result).to include("allows admin to access allowed contracts endpoints")
      expect(result).to include("get")
      expect(result).to include("post")
      expect(result).to include(":ok")
      expect(result).to include(":created")
    end

    it "generates tests for blocked endpoints" do
      permissions = { "viewer" => make_permission(actions: %w[index show]) }
      result = generator.build_crud_access_tests("contracts", permissions, false, "id")

      expect(result).to include("blocks viewer from blocked contracts endpoints")
      expect(result).to include(":forbidden")
    end

    it "generates multi-tenant URLs with org identifier" do
      permissions = { "admin" => make_permission(actions: ["index"]) }
      result = generator.build_crud_access_tests("contracts", permissions, true, "slug")
      expect(result).to include('#{org.slug}')
    end

    it "generates non-tenant URLs without org prefix" do
      permissions = { "admin" => make_permission(actions: ["index"]) }
      result = generator.build_crud_access_tests("contracts", permissions, false, "id")
      expect(result).to include('"/api/contracts"')
      expect(result).not_to include('#{org.')
    end

    it "returns empty for no permissions" do
      result = generator.build_crud_access_tests("contracts", {}, false, "id")
      expect(result).to eq("")
    end
  end

  # ──────────────────────────────────────────────
  # Field visibility tests
  # ──────────────────────────────────────────────

  describe "#build_field_visibility_tests" do
    it "generates visibility test for restricted show_fields" do
      permissions = {
        "viewer" => make_permission(
          actions: %w[index show], show_fields: %w[id title],
          hidden_fields: ["total_value"]
        )
      }
      columns = [{ name: "title", type: "string" }, { name: "total_value", type: "decimal" }]

      result = generator.build_field_visibility_tests("contracts", permissions, columns, false, "id")

      expect(result).to include("shows only permitted fields for viewer on contracts")
      expect(result).to include("have_key('id')")
      expect(result).to include("have_key('title')")
      expect(result).to include("not_to have_key('total_value')")
    end

    it "skips visibility test for wildcard roles" do
      permissions = { "owner" => make_permission(actions: %w[index show], show_fields: ["*"]) }
      result = generator.build_field_visibility_tests("contracts", permissions, [], false, "id")
      expect(result).to eq("")
    end

    it "skips visibility test for roles without show action" do
      permissions = { "creator" => make_permission(actions: ["store"], show_fields: %w[id title]) }
      result = generator.build_field_visibility_tests("contracts", permissions, [], false, "id")
      expect(result).to eq("")
    end
  end

  # ──────────────────────────────────────────────
  # Forbidden field tests
  # ──────────────────────────────────────────────

  describe "#build_forbidden_field_tests" do
    it "generates forbidden field test for restricted create_fields" do
      permissions = { "admin" => make_permission(actions: %w[index show store], create_fields: ["title"]) }
      columns = [{ name: "title", type: "string" }, { name: "total_value", type: "decimal" }]

      result = generator.build_forbidden_field_tests("contracts", permissions, columns, false, "id")

      expect(result).to include("returns 403 when admin tries to set restricted fields")
      expect(result).to include("total_value")
      expect(result).to include(":forbidden")
    end

    it "skips for wildcard create_fields" do
      permissions = { "owner" => make_permission(actions: %w[index show store], create_fields: ["*"]) }
      columns = [{ name: "title", type: "string" }]

      result = generator.build_forbidden_field_tests("contracts", permissions, columns, false, "id")
      expect(result).to eq("")
    end

    it "skips for roles without store action" do
      permissions = { "viewer" => make_permission(actions: %w[index show], create_fields: ["title"]) }
      result = generator.build_forbidden_field_tests("contracts", permissions, [], false, "id")
      expect(result).to eq("")
    end
  end

  # ──────────────────────────────────────────────
  # Full generate — multi-tenant
  # ──────────────────────────────────────────────

  describe "#generate multi-tenant" do
    it "generates complete RSpec test file" do
      output = generator.generate(make_blueprint, true, "slug")

      expect(output).to include("require 'rails_helper'")
      expect(output).to include("Contract — CRUD & Permissions")
      expect(output).to include("organization")
    end

    it "uses create_user_with_role helper" do
      output = generator.generate(make_blueprint, true, "id")

      expect(output).to include("create_user_with_role")
      expect(output).to include("def create_user_with_role")
    end

    it "multi-tenant CRUD tests use create_user_with_role" do
      output = generator.generate(make_blueprint, true, "id")

      expect(output).to include("create_user_with_role('owner', org,")
      expect(output).to include("create_user_with_role('viewer', org,")
    end

    it "generated code is syntactically balanced" do
      output = generator.generate(make_blueprint, true, "id")

      open_do = output.scan(/\bdo\b/).length
      end_count = output.scan(/\bend\b/).length
      # do...end blocks + method defs + class should balance
      expect(end_count).to be >= open_do
    end
  end

  # ──────────────────────────────────────────────
  # Full generate — non-tenant
  # ──────────────────────────────────────────────

  describe "#generate non-tenant" do
    it "generates complete RSpec test file" do
      output = generator.generate(make_blueprint, false)

      expect(output).to include("require 'rails_helper'")
      expect(output).to include("Contract — CRUD & Permissions")
      expect(output).not_to include("Organization")
    end

    it "uses create_user_with_permissions helper" do
      output = generator.generate(make_blueprint, false)

      expect(output).to include("create_user_with_permissions")
      expect(output).to include("def create_user_with_permissions")
    end
  end

  # ──────────────────────────────────────────────
  # actions_to_permissions
  # ──────────────────────────────────────────────

  describe "#actions_to_permissions" do
    it "uses wildcard when all actions present" do
      all = %w[index show store update destroy trashed restore forceDelete]
      result = generator.actions_to_permissions(all, "contracts")
      expect(result).to eq("['contracts.*']")
    end

    it "lists individual permissions for partial actions" do
      result = generator.actions_to_permissions(%w[index show], "contracts")
      expect(result).to eq("['contracts.index', 'contracts.show']")
    end
  end
end
