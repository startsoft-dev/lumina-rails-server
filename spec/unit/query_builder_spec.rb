# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lumina::QueryBuilder do
  before do
    Post.delete_all
  end

  def create_posts(count)
    count.times { |i| Post.create!(title: "Post #{i + 1}", content: "Content #{i + 1}") }
  end

  # ------------------------------------------------------------------
  # Filtering: ?filter[status]=published
  # ------------------------------------------------------------------

  describe "filtering" do
    before do
      Post.create!(title: "Active Post", status: "published")
      Post.create!(title: "Draft Post", status: "draft")
      Post.create!(title: "Another Active", status: "published")
    end

    it "filters by a single value" do
      builder = described_class.new(Post, params: { filter: { "status" => "published" } })
      builder.build
      expect(builder.to_scope.count).to eq(2)
    end

    it "filters with comma-separated OR values" do
      builder = described_class.new(Post, params: { filter: { "status" => "published,draft" } })
      builder.build
      expect(builder.to_scope.count).to eq(3)
    end

    it "ignores filters not in allowed_filters" do
      builder = described_class.new(Post, params: { filter: { "content" => "Content" } })
      builder.build
      # content is not in allowed_filters, so all records returned
      expect(builder.to_scope.count).to eq(3)
    end

    it "returns all when no filter params" do
      builder = described_class.new(Post, params: {})
      builder.build
      expect(builder.to_scope.count).to eq(3)
    end
  end

  # ------------------------------------------------------------------
  # Sorting: ?sort=-created_at,title
  # ------------------------------------------------------------------

  describe "sorting" do
    before do
      Post.create!(title: "Banana")
      Post.create!(title: "Apple")
      Post.create!(title: "Cherry")
    end

    it "sorts ascending by default" do
      builder = described_class.new(Post, params: { sort: "title" })
      builder.build
      titles = builder.to_scope.pluck(:title)
      expect(titles).to eq(%w[Apple Banana Cherry])
    end

    it "sorts descending with - prefix" do
      builder = described_class.new(Post, params: { sort: "-title" })
      builder.build
      titles = builder.to_scope.pluck(:title)
      expect(titles).to eq(%w[Cherry Banana Apple])
    end

    it "supports multiple sort fields" do
      Post.create!(title: "Apple", status: "z")
      builder = described_class.new(Post, params: { sort: "title,-created_at" })
      builder.build
      results = builder.to_scope.to_a
      expect(results.first.title).to eq("Apple")
    end

    it "applies default sort when no sort param" do
      builder = described_class.new(Post, params: {})
      builder.build
      # Post has lumina_default_sort "-created_at"
      results = builder.to_scope.to_a
      expect(results.first.title).to eq("Cherry") # last created
    end
  end

  # ------------------------------------------------------------------
  # Search: ?search=term
  # ------------------------------------------------------------------

  describe "search" do
    before do
      Post.create!(title: "Needle in title", content: "Some content")
      Post.create!(title: "Other", content: "Needle in content")
      Post.create!(title: "No match", content: "Nothing")
    end

    it "returns matching rows across allowed search columns" do
      builder = described_class.new(Post, params: { search: "needle" })
      builder.build
      expect(builder.to_scope.count).to eq(2)
    end

    it "is case-insensitive" do
      builder = described_class.new(Post, params: { search: "NEEDLE" })
      builder.build
      expect(builder.to_scope.count).to eq(2)
    end

    it "excludes non-matching rows" do
      builder = described_class.new(Post, params: { search: "nonexistent" })
      builder.build
      expect(builder.to_scope.count).to eq(0)
    end

    it "returns all when search is empty" do
      builder = described_class.new(Post, params: { search: "" })
      builder.build
      expect(builder.to_scope.count).to eq(3)
    end

    it "returns all when search is nil" do
      builder = described_class.new(Post, params: {})
      builder.build
      expect(builder.to_scope.count).to eq(3)
    end

    it "composes with filters" do
      Post.create!(title: "Needle", status: "published")
      builder = described_class.new(Post, params: {
        search: "needle",
        filter: { "status" => "published" }
      })
      builder.build
      results = builder.to_scope.to_a
      expect(results.length).to eq(1)
      expect(results.first.status).to eq("published")
    end

    it "searches through relationship dot notation" do
      blog = Blog.create!(title: "BlogWithNeedle")
      Post.delete_all
      Post.create!(title: "Post A", content: "Content")

      # Blog.title search uses blog.title in allowed_search
      builder = described_class.new(Blog, params: { search: "blogwithneedle" })
      builder.build
      expect(builder.to_scope.count).to eq(1)
    end
  end

  # ------------------------------------------------------------------
  # Pagination
  # ------------------------------------------------------------------

  describe "pagination" do
    before { create_posts(15) }

    it "returns items and pagination metadata" do
      builder = described_class.new(Post, params: {})
      builder.build
      result = builder.paginate(per_page: 5, page: 1)

      expect(result[:items].length).to eq(5)
      expect(result[:pagination][:current_page]).to eq(1)
      expect(result[:pagination][:last_page]).to eq(3)
      expect(result[:pagination][:per_page]).to eq(5)
      expect(result[:pagination][:total]).to eq(15)
    end

    it "navigates to second page" do
      builder = described_class.new(Post, params: {})
      builder.build
      result = builder.paginate(per_page: 5, page: 2)

      expect(result[:items].length).to eq(5)
      expect(result[:pagination][:current_page]).to eq(2)
    end

    it "returns remaining items on last page" do
      builder = described_class.new(Post, params: { sort: "title" })
      builder.build
      result = builder.paginate(per_page: 4, page: 4)

      expect(result[:items].length).to eq(3) # 15 total, 4 per page, page 4 = 3 items
      expect(result[:pagination][:current_page]).to eq(4)
      expect(result[:pagination][:last_page]).to eq(4)
    end

    it "clamps per_page to minimum of 1" do
      builder = described_class.new(Post, params: {})
      builder.build
      result = builder.paginate(per_page: 0)

      expect(result[:pagination][:per_page]).to eq(1)
      expect(result[:items].length).to eq(1)
    end

    it "clamps per_page to maximum of 100" do
      builder = described_class.new(Post, params: {})
      builder.build
      result = builder.paginate(per_page: 500)

      expect(result[:pagination][:per_page]).to eq(100)
    end

    it "clamps negative per_page to 1" do
      builder = described_class.new(Post, params: {})
      builder.build
      result = builder.paginate(per_page: -10)

      expect(result[:pagination][:per_page]).to eq(1)
    end

    it "clamps negative page to 1" do
      builder = described_class.new(Post, params: {})
      builder.build
      result = builder.paginate(per_page: 5, page: -1)

      expect(result[:pagination][:current_page]).to eq(1)
    end

    it "returns empty items with no records" do
      Post.delete_all
      builder = described_class.new(Post, params: {})
      builder.build
      result = builder.paginate(per_page: 5)

      expect(result[:items].length).to eq(0)
      expect(result[:pagination][:total]).to eq(0)
      expect(result[:pagination][:last_page]).to eq(1)
    end

    it "reads per_page from params" do
      builder = described_class.new(Post, params: { per_page: "3" })
      builder.build
      result = builder.paginate

      expect(result[:pagination][:per_page]).to eq(3)
      expect(result[:items].length).to eq(3)
    end
  end

  # ------------------------------------------------------------------
  # Sparse Fieldsets: ?fields[posts]=id,title
  # ------------------------------------------------------------------

  describe "sparse fieldsets" do
    before do
      Post.create!(title: "Test", content: "Full content", status: "published")
    end

    it "selects only requested fields" do
      builder = described_class.new(Post, params: { fields: { "posts" => "id,title" } })
      builder.build
      result = builder.to_scope.first

      expect(result.attributes.keys).to include("id", "title")
      # content is not selected, so it should not be in the loaded attributes
      expect(result.has_attribute?(:content)).to be false
    end

    it "always includes primary key" do
      builder = described_class.new(Post, params: { fields: { "posts" => "title" } })
      builder.build
      result = builder.to_scope.first

      expect(result.attributes.keys).to include("id")
    end

    it "ignores fields not in allowed_fields" do
      builder = described_class.new(Post, params: { fields: { "posts" => "id,title,secret_field" } })
      builder.build
      result = builder.to_scope.first

      expect(result.attributes.keys).to include("id", "title")
    end
  end

  # ------------------------------------------------------------------
  # Eager Loading: ?include=user,comments
  # ------------------------------------------------------------------

  describe "includes" do
    before do
      user = User.create!(name: "Test User", email: "test@example.com")
      post = Post.create!(title: "Test", user: user)
      Comment.create!(post: post, body: "Great post!")
    end

    it "eager loads allowed includes" do
      builder = described_class.new(Post, params: { include: "user,comments" })
      builder.build

      result = builder.to_scope.first
      expect(result.association(:user).loaded?).to be true
      expect(result.association(:comments).loaded?).to be true
    end

    it "ignores includes not in allowed_includes" do
      builder = described_class.new(Post, params: { include: "organization" })
      builder.build

      result = builder.to_scope.first
      expect(result.association(:organization).loaded?).to be false
    end

    it "handles Count suffix" do
      builder = described_class.new(Post, params: { include: "commentsCount" })
      builder.build
      # Count suffix is handled in serialization, not eager loading
      expect(builder.to_scope.count).to eq(1)
    end
  end
end
