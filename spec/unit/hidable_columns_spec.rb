# frozen_string_literal: true

require "spec_helper"

# --------------------------------------------------------------------------
# Test Models
# --------------------------------------------------------------------------

class HidablePost < ActiveRecord::Base
  include Lumina::HidableColumns
  self.table_name = "posts"
end

class HidablePostWithAdditional < ActiveRecord::Base
  include Lumina::HidableColumns
  self.table_name = "posts"

  lumina_additional_hidden :status, :is_published
end

# --------------------------------------------------------------------------
# Test Policies
# --------------------------------------------------------------------------

class HidablePostPolicy < Lumina::ResourcePolicy
  self.resource_slug = "posts"

  def hidden_attributes_for_show(user)
    return ["status", "is_published", "content"] unless user
    return [] if user.id == 1 # admin
    ["status"] # regular user
  end
end

class HidablePostWithAdditionalPolicy < Lumina::ResourcePolicy
  self.resource_slug = "posts"

  def hidden_attributes_for_show(user)
    return ["content"] unless user
    []
  end
end

RSpec.describe Lumina::HidableColumns do
  # ------------------------------------------------------------------
  # Base hidden columns
  # ------------------------------------------------------------------

  describe "BASE_HIDDEN_COLUMNS" do
    it "includes sensitive columns" do
      expect(Lumina::HidableColumns::BASE_HIDDEN_COLUMNS).to include(
        "password", "password_digest", "remember_token",
        "created_at", "updated_at", "deleted_at", "discarded_at",
        "email_verified_at"
      )
    end
  end

  # ------------------------------------------------------------------
  # hidden_columns_for
  # ------------------------------------------------------------------

  describe "#hidden_columns_for" do
    it "returns base hidden columns for model without policy" do
      post = HidablePost.create!(title: "Test", content: "Content")
      hidden = post.hidden_columns_for(nil)
      expect(hidden).to include("password", "password_digest", "created_at", "updated_at")
    end

    it "includes additional hidden columns" do
      post = HidablePostWithAdditional.create!(title: "Test", content: "Content")
      hidden = post.hidden_columns_for(nil)
      expect(hidden).to include("status", "is_published")
    end

    it "includes policy-based hidden columns for guest" do
      # Stub Pundit to return our test policy
      allow(Pundit::PolicyFinder).to receive(:new).and_return(
        double(policy: HidablePostPolicy)
      )

      post = HidablePost.create!(title: "Test", content: "Content")
      hidden = post.hidden_columns_for(nil)
      expect(hidden).to include("status", "is_published", "content")
    end

    it "includes fewer hidden columns for admin" do
      allow(Pundit::PolicyFinder).to receive(:new).and_return(
        double(policy: HidablePostPolicy)
      )

      admin = User.create!(id: 1, name: "Admin", email: "admin-hid@test.com")
      post = HidablePost.create!(title: "Test", content: "Content")
      hidden = post.hidden_columns_for(admin)

      # Admin sees everything — policy returns []
      expect(hidden).not_to include("status", "is_published", "content")
    end

    it "deduplicates column names" do
      allow(Pundit::PolicyFinder).to receive(:new).and_return(
        double(policy: HidablePostWithAdditionalPolicy)
      )

      post = HidablePostWithAdditional.create!(title: "Test", content: "Content")
      hidden = post.hidden_columns_for(nil)
      expect(hidden).to eq(hidden.uniq)
    end
  end

  # ------------------------------------------------------------------
  # as_lumina_json
  # ------------------------------------------------------------------

  describe "#as_lumina_json" do
    it "excludes hidden columns from JSON output" do
      post = HidablePost.create!(title: "Test", content: "Visible", status: "published")
      json = post.as_lumina_json(nil)

      # Base hidden columns (created_at, updated_at, etc.) should be removed
      expect(json).not_to have_key("created_at")
      expect(json).not_to have_key("updated_at")
      expect(json).not_to have_key("discarded_at")

      # Non-hidden columns should be present
      expect(json).to have_key("id")
      expect(json).to have_key("title")
      expect(json["title"]).to eq("Test")
    end

    it "includes additional hidden columns in exclusion" do
      post = HidablePostWithAdditional.create!(title: "Test", content: "Visible", status: "published")
      json = post.as_lumina_json(nil)

      expect(json).not_to have_key("status")
      expect(json).not_to have_key("is_published")
    end
  end

  # ------------------------------------------------------------------
  # Edge cases
  # ------------------------------------------------------------------

  describe "edge cases" do
    it "handles missing policy gracefully" do
      post = HidablePost.create!(title: "Test", content: "Content")
      # With no policy found, should still return base + additional
      expect { post.hidden_columns_for(nil) }.not_to raise_error
    end

    it "handles policy without hidden_attributes_for_show method" do
      allow(Pundit::PolicyFinder).to receive(:new).and_return(
        double(policy: Class.new { def initialize(u, r); end })
      )

      post = HidablePost.create!(title: "Test", content: "Content")
      hidden = post.hidden_columns_for(nil)
      expect(hidden).to include("password") # base columns still present
    end
  end

  # ------------------------------------------------------------------
  # permitted_attributes_for_show filtering
  # ------------------------------------------------------------------

  describe "permitted_attributes_for_show filtering" do
    # Create a policy that uses permitted_attributes_for_show whitelist
    it "hides columns not in permitted list" do
      policy_class = Class.new(Lumina::ResourcePolicy) do
        self.resource_slug = "posts"

        def permitted_attributes_for_show(user)
          return ['id', 'title'] unless user
          ['*']
        end
      end

      allow(Pundit::PolicyFinder).to receive(:new).and_return(
        double(policy: policy_class)
      )

      post = HidablePost.create!(title: "Test", content: "Content", status: "draft")
      json = post.as_lumina_json(nil) # guest user

      expect(json).to have_key("id")
      expect(json).to have_key("title")
      expect(json).not_to have_key("content")
      expect(json).not_to have_key("status")
      expect(json).not_to have_key("blog_id")
    end
  end
end
