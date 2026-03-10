# frozen_string_literal: true

require "spec_helper"
require "rails/command"
require "lumina/commands/install_command"

RSpec.describe Lumina::Commands::InstallCommand do
  let(:tmp_dir) { Dir.mktmpdir("lumina_install_test") }
  let(:tmp_root) { Pathname.new(tmp_dir) }
  let(:command) { described_class.new }

  before do
    Rails.define_singleton_method(:root) { tmp_root } unless Rails.respond_to?(:root)
    allow(Rails).to receive(:root).and_return(tmp_root)
    allow(command).to receive(:say)
  end

  after do
    FileUtils.remove_entry(tmp_dir)
  end

  # ------------------------------------------------------------------
  # publish_config
  # ------------------------------------------------------------------

  describe "#publish_config" do
    it "creates config/initializers/lumina.rb" do
      command.send(:publish_config, "rspec")

      path = File.join(tmp_dir, "config/initializers/lumina.rb")
      expect(File.exist?(path)).to be true

      content = File.read(path)
      expect(content).to include("Lumina.configure")
      expect(content).to include("Models")
      expect(content).to include("Multi-tenant")
    end

    it "creates parent directories if they don't exist" do
      command.send(:publish_config, "rspec")

      expect(Dir.exist?(File.join(tmp_dir, "config/initializers"))).to be true
    end
  end

  # ------------------------------------------------------------------
  # publish_routes
  # ------------------------------------------------------------------

  describe "#publish_routes" do
    it "copies routes template to config/routes/lumina.rb" do
      command.send(:publish_routes)

      path = File.join(tmp_dir, "config/routes/lumina.rb")
      expect(File.exist?(path)).to be true

      content = File.read(path)
      expect(content).to include("Lumina routes")
    end
  end

  # ------------------------------------------------------------------
  # create_multi_tenant_migrations
  # ------------------------------------------------------------------

  describe "#create_multi_tenant_migrations" do
    it "creates 3 migration files" do
      command.send(:create_multi_tenant_migrations)

      org_files = Dir.glob(File.join(tmp_dir, "db/migrate/*_create_organizations.rb"))
      role_files = Dir.glob(File.join(tmp_dir, "db/migrate/*_create_roles.rb"))
      user_role_files = Dir.glob(File.join(tmp_dir, "db/migrate/*_create_user_roles.rb"))

      expect(org_files.length).to eq(1)
      expect(role_files.length).to eq(1)
      expect(user_role_files.length).to eq(1)
    end

    it "generates non-empty migration content" do
      command.send(:create_multi_tenant_migrations)

      Dir.glob(File.join(tmp_dir, "db/migrate/*.rb")).each do |f|
        content = File.read(f)
        expect(content).not_to be_empty
        expect(content).to include("create_table")
      end
    end

    it "generates timestamped filenames" do
      command.send(:create_multi_tenant_migrations)

      Dir.glob(File.join(tmp_dir, "db/migrate/*.rb")).each do |f|
        basename = File.basename(f)
        expect(basename).to match(/\A\d{16}_/)
      end
    end
  end

  # ------------------------------------------------------------------
  # create_multi_tenant_models
  # ------------------------------------------------------------------

  describe "#create_multi_tenant_models" do
    it "creates Organization, Role, and UserRole models" do
      command.send(:create_multi_tenant_models, %w[admin editor viewer])

      %w[organization role user_role].each do |model|
        path = File.join(tmp_dir, "app/models/#{model}.rb")
        expect(File.exist?(path)).to be true
        expect(File.read(path)).not_to be_empty
      end
    end

    it "passes roles to the Role model template" do
      command.send(:create_multi_tenant_models, %w[admin editor])

      role_content = File.read(File.join(tmp_dir, "app/models/role.rb"))
      expect(role_content).not_to be_empty
    end
  end

  # ------------------------------------------------------------------
  # create_factories
  # ------------------------------------------------------------------

  describe "#create_factories" do
    it "creates 3 factory files in spec/factories" do
      command.send(:create_factories)

      %w[organizations roles user_roles].each do |factory|
        path = File.join(tmp_dir, "spec/factories/#{factory}.rb")
        expect(File.exist?(path)).to be true
        expect(File.read(path)).not_to be_empty
      end
    end
  end

  # ------------------------------------------------------------------
  # create_policies
  # ------------------------------------------------------------------

  describe "#create_policies" do
    it "creates OrganizationPolicy and RolePolicy" do
      command.send(:create_policies)

      %w[organization_policy role_policy].each do |policy|
        path = File.join(tmp_dir, "app/policies/#{policy}.rb")
        expect(File.exist?(path)).to be true
        expect(File.read(path)).not_to be_empty
      end
    end
  end

  # ------------------------------------------------------------------
  # create_seeders
  # ------------------------------------------------------------------

  describe "#create_seeders" do
    it "creates role seeder with correct content" do
      roles = %w[admin editor viewer]
      command.send(:create_seeders, roles)

      seeder_path = File.join(tmp_dir, "db/seeds/role_seeder.rb")
      expect(File.exist?(seeder_path)).to be true

      content = File.read(seeder_path)
      roles.each do |role|
        expect(content).to include(role)
      end
      expect(content).to include("find_or_create_by!")
    end

    it "creates organization seeder" do
      command.send(:create_seeders, %w[admin])

      seeder_path = File.join(tmp_dir, "db/seeds/organization_seeder.rb")
      expect(File.exist?(seeder_path)).to be true
      expect(File.read(seeder_path)).not_to be_empty
    end

    it "includes descriptions for standard roles" do
      command.send(:create_seeders, %w[admin editor viewer])

      content = File.read(File.join(tmp_dir, "db/seeds/role_seeder.rb"))
      expect(content).to include("Administrator role with full access")
      expect(content).to include("Editor role with create, read, and update access")
      expect(content).to include("Viewer role with read-only access")
    end
  end

  # ------------------------------------------------------------------
  # create_audit_trail_migration
  # ------------------------------------------------------------------

  describe "#create_audit_trail_migration" do
    it "creates an audit_logs migration" do
      command.send(:create_audit_trail_migration)

      files = Dir.glob(File.join(tmp_dir, "db/migrate/*_create_audit_logs.rb"))
      expect(files.length).to eq(1)

      content = File.read(files.first)
      expect(content).to include("create_table")
      expect(content).to include("audit_logs")
    end

    it "skips if audit_logs migration already exists" do
      # Create an existing migration
      migrate_dir = File.join(tmp_dir, "db/migrate")
      FileUtils.mkdir_p(migrate_dir)
      File.write(File.join(migrate_dir, "20240101000000_create_audit_logs.rb"), "existing")

      command.send(:create_audit_trail_migration)

      files = Dir.glob(File.join(tmp_dir, "db/migrate/*_create_audit_logs.rb"))
      expect(files.length).to eq(1)
      expect(File.read(files.first)).to eq("existing")
    end
  end

  # ------------------------------------------------------------------
  # update_config
  # ------------------------------------------------------------------

  describe "#update_config" do
    before do
      command.send(:publish_config, "rspec")
    end

    it "updates organization_identifier_column in config" do
      config_path = File.join(tmp_dir, "config/initializers/lumina.rb")
      content = File.read(config_path)
      content += "\n  c.multi_tenant = {\n    organization_identifier_column: \"id\"\n  }\n"
      File.write(config_path, content)

      command.send(:update_config, "slug")

      updated = File.read(config_path)
      expect(updated).to include('organization_identifier_column: "slug"')
    end

    it "does nothing if config file does not exist" do
      FileUtils.rm_f(File.join(tmp_dir, "config/initializers/lumina.rb"))
      expect { command.send(:update_config, "id") }.not_to raise_error
    end
  end
end
