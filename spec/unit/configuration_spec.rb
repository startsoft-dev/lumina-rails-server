# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lumina::Configuration do
  subject(:config) { described_class.new }

  describe "#initialize" do
    it "sets default values" do
      expect(config.models).to eq({})
      expect(config.public_models).to eq([])
      expect(config.multi_tenant[:enabled]).to eq(false)
      expect(config.invitations[:expires_days]).to eq(7)
      expect(config.nested[:max_operations]).to eq(50)
      expect(config.test_framework).to eq("rspec")
    end
  end

  describe "#model" do
    it "registers a model with its slug" do
      config.model :posts, "Post"
      expect(config.models[:posts]).to eq("Post")
    end

    it "converts slug to symbol" do
      config.model "posts", "Post"
      expect(config.models[:posts]).to eq("Post")
    end
  end

  describe "#public_model" do
    it "marks a model as public" do
      config.public_model :posts
      expect(config.public_models).to include(:posts)
    end

    it "accepts multiple slugs" do
      config.public_model :posts, :comments
      expect(config.public_models).to include(:posts, :comments)
    end
  end

  describe "#public_model?" do
    it "returns true for public models" do
      config.public_model :posts
      expect(config.public_model?(:posts)).to be true
    end

    it "returns false for non-public models" do
      expect(config.public_model?(:posts)).to be false
    end

    it "converts string slugs to symbols" do
      config.public_model :posts
      expect(config.public_model?("posts")).to be true
    end
  end

  describe "#resolve_model" do
    before { config.model :posts, "Post" }

    it "resolves a model class from its slug" do
      expect(config.resolve_model(:posts)).to eq(Post)
    end

    it "raises RecordNotFound for unknown slugs" do
      expect { config.resolve_model(:unknown) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "raises RecordNotFound for invalid class names" do
      config.model :invalid, "NonExistentModel"
      expect { config.resolve_model(:invalid) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#slug_for" do
    before do
      config.model :posts, "Post"
      config.model :blogs, "Blog"
    end

    it "returns the slug for a model class" do
      expect(config.slug_for(Post)).to eq(:posts)
    end

    it "returns the slug for a model instance" do
      expect(config.slug_for(Post.new)).to eq(:posts)
    end

    it "returns nil for unregistered models" do
      expect(config.slug_for(Comment)).to be_nil
    end
  end

  describe "#multi_tenant_enabled?" do
    it "returns false by default" do
      expect(config.multi_tenant_enabled?).to be false
    end

    it "returns true when enabled" do
      config.multi_tenant[:enabled] = true
      expect(config.multi_tenant_enabled?).to be true
    end
  end

  describe "#use_subdomain?" do
    it "returns false by default" do
      expect(config.use_subdomain?).to be false
    end
  end

  describe "#needs_org_prefix?" do
    it "returns false when multi-tenant is disabled" do
      expect(config.needs_org_prefix?).to be false
    end

    it "returns true when multi-tenant is enabled without subdomain" do
      config.multi_tenant[:enabled] = true
      config.multi_tenant[:use_subdomain] = false
      expect(config.needs_org_prefix?).to be true
    end

    it "returns false when using subdomain" do
      config.multi_tenant[:enabled] = true
      config.multi_tenant[:use_subdomain] = true
      expect(config.needs_org_prefix?).to be false
    end
  end
end
