# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lumina::HasValidation do
  describe "#validate_for_action" do
    context "with wildcard permitted fields" do
      it "validates all submitted fields" do
        instance = Post.new
        result = instance.validate_for_action(
          { "title" => "Hello", "content" => "World" },
          permitted_fields: ['*']
        )
        expect(result[:valid]).to be true
        expect(result[:validated]["title"]).to eq("Hello")
        expect(result[:validated]["content"]).to eq("World")
      end

      it "runs ActiveModel validations" do
        instance = Post.new
        result = instance.validate_for_action(
          { "title" => "A" * 256 },
          permitted_fields: ['*']
        )
        expect(result[:valid]).to be false
        expect(result[:errors]).to have_key("title")
      end
    end

    context "with specific permitted fields" do
      it "only validates permitted fields" do
        instance = Post.new
        result = instance.validate_for_action(
          { "title" => "Hello", "content" => "World", "status" => "draft" },
          permitted_fields: ['title', 'content']
        )
        expect(result[:valid]).to be true
        expect(result[:validated]).to have_key("title")
        expect(result[:validated]).to have_key("content")
        expect(result[:validated]).not_to have_key("status")
      end

      it "only returns errors for permitted fields" do
        instance = Post.new
        result = instance.validate_for_action(
          { "title" => "A" * 256, "status" => "invalid" },
          permitted_fields: ['title']
        )
        expect(result[:valid]).to be false
        expect(result[:errors]).to have_key("title")
        expect(result[:errors]).not_to have_key("status")
      end
    end

    context "with no validations" do
      it "returns valid for any data" do
        klass = Class.new(ActiveRecord::Base) do
          include Lumina::HasValidation
          self.table_name = "posts"
        end
        instance = klass.new
        result = instance.validate_for_action(
          { "title" => "Hello" },
          permitted_fields: ['*']
        )
        expect(result[:valid]).to be true
      end
    end

    context "with empty params" do
      it "returns valid with empty validated hash" do
        instance = Post.new
        result = instance.validate_for_action({}, permitted_fields: ['*'])
        expect(result[:valid]).to be true
        expect(result[:validated]).to be_empty
      end
    end
  end
end
