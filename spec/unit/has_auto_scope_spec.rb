# frozen_string_literal: true

require "spec_helper"

# Define scope classes before models reference them
module ModelScopes
  class ScopedPostScope
    def self.apply(relation)
      relation.where(status: "published")
    end
  end
end

RSpec.describe Lumina::HasAutoScope do
  before(:all) do
    ActiveRecord::Schema.define do
      create_table :scoped_posts, force: true do |t|
        t.string :title
        t.string :status
        t.timestamps
      end

      create_table :unscoped_items, force: true do |t|
        t.string :name
        t.timestamps
      end
    end
  end

  let!(:scoped_post_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "scoped_posts"
      def self.name; "ScopedPost"; end

      include Lumina::HasAutoScope
    end
  end

  let!(:unscoped_item_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "unscoped_items"
      def self.name; "UnscopedItem"; end

      include Lumina::HasAutoScope
    end
  end

  describe ".lumina_auto_scope_class" do
    it "finds scope class by naming convention" do
      expect(scoped_post_class.lumina_auto_scope_class).to eq(ModelScopes::ScopedPostScope)
    end

    it "returns nil when no scope class exists" do
      expect(unscoped_item_class.lumina_auto_scope_class).to be_nil
    end
  end

  describe "default_scope" do
    it "applies scope when scope class exists" do
      scoped_post_class.create!(title: "Draft Post", status: "draft")
      scoped_post_class.create!(title: "Published Post", status: "published")

      results = scoped_post_class.all.to_a
      expect(results.size).to eq(1)
      expect(results.first.title).to eq("Published Post")
    end

    it "returns all records when no scope class exists" do
      unscoped_item_class.create!(name: "Item A")
      unscoped_item_class.create!(name: "Item B")

      results = unscoped_item_class.all.to_a
      expect(results.size).to eq(2)
    end

    it "can be bypassed with unscoped" do
      scoped_post_class.create!(title: "Draft", status: "draft")
      scoped_post_class.create!(title: "Published", status: "published")

      results = scoped_post_class.unscoped.to_a
      expect(results.size).to eq(2)
    end
  end
end
