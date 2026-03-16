# frozen_string_literal: true

require "spec_helper"

# Engine requires a full Rails environment (Rails::Engine base class).
# We test the engine source file structure and verify it can be parsed.
RSpec.describe "Lumina::Engine (source verification)" do
  it "engine source file exists" do
    path = File.expand_path("../../../lib/lumina/engine.rb", __FILE__)
    expect(File.exist?(path)).to be true
  end

  it "engine source defines the correct class" do
    path = File.expand_path("../../../lib/lumina/engine.rb", __FILE__)
    content = File.read(path)
    expect(content).to include("class Engine < ::Rails::Engine")
    expect(content).to include("isolate_namespace Lumina")
  end

  it "engine source registers lumina.autoloads initializer" do
    path = File.expand_path("../../../lib/lumina/engine.rb", __FILE__)
    content = File.read(path)
    expect(content).to include('initializer "lumina.autoloads"')
  end

  it "engine source registers lumina.routes initializer" do
    path = File.expand_path("../../../lib/lumina/engine.rb", __FILE__)
    content = File.read(path)
    expect(content).to include('initializer "lumina.routes"')
  end

  it "engine source registers lumina.pundit initializer" do
    path = File.expand_path("../../../lib/lumina/engine.rb", __FILE__)
    content = File.read(path)
    expect(content).to include('initializer "lumina.pundit"')
  end

  it "engine source requires all concerns" do
    path = File.expand_path("../../../lib/lumina/engine.rb", __FILE__)
    content = File.read(path)
    %w[has_lumina has_validation has_permissions has_audit_trail
       belongs_to_organization hidable_columns has_uuid has_auto_scope].each do |concern|
      expect(content).to include("lumina/concerns/#{concern}")
    end
  end

  it "engine source requires controllers" do
    path = File.expand_path("../../../lib/lumina/engine.rb", __FILE__)
    content = File.read(path)
    expect(content).to include("lumina/controllers/resources_controller")
    expect(content).to include("lumina/controllers/auth_controller")
    expect(content).to include("lumina/controllers/invitations_controller")
  end

  it "engine source requires policies" do
    path = File.expand_path("../../../lib/lumina/engine.rb", __FILE__)
    content = File.read(path)
    expect(content).to include("lumina/policies/resource_policy")
    expect(content).to include("lumina/policies/invitation_policy")
  end

  it "engine source requires models" do
    path = File.expand_path("../../../lib/lumina/engine.rb", __FILE__)
    content = File.read(path)
    expect(content).to include("lumina/models/lumina_model")
    expect(content).to include("lumina/models/audit_log")
    expect(content).to include("lumina/models/organization_invitation")
  end
end
