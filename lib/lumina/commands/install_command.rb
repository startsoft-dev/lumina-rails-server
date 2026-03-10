# frozen_string_literal: true

require "rails/command"
require "thor"

module Lumina
  module Commands
    # Interactive setup wizard — mirrors Laravel `php artisan lumina:install` exactly.
    #
    # Usage: rails lumina:install
    class InstallCommand < Rails::Command::Base
      namespace "lumina:install"

      desc "install", "Install and configure Lumina for your Rails application"
      def perform
        print_banner

        say ""
        say "+ Lumina :: Install :: Let's build something great +", :cyan
        say ""

        features = prompt_multiselect(
          "Which features would you like to configure?",
          {
            "publish" => "Publish config & routes",
            "multi_tenant" => "Multi-tenant support (Organizations, Roles)",
            "audit_trail" => "Audit trail (change logging)"
          },
          default: ["publish"]
        )

        test_framework = prompt_select(
          "Which test framework do you use?",
          { "rspec" => "RSpec", "minitest" => "Minitest" },
          default: "rspec"
        )

        identifier_column = "id"
        roles = ["admin"]

        if features.include?("multi_tenant")
          identifier_column = ask("What column should be used to identify organizations? [id]:")
          identifier_column = "id" if identifier_column.blank?

          roles_input = ask("What roles should your app have? [admin, editor, viewer]:")
          roles_input = "admin, editor, viewer" if roles_input.blank?
          roles = (["admin"] + roles_input.split(",").map(&:strip)).uniq
        end

        say ""

        if features.include?("publish")
          task("Publishing config") { publish_config(test_framework) }
          task("Publishing routes") { publish_routes }
        end

        if features.include?("multi_tenant")
          task("Creating migrations") { create_multi_tenant_migrations }
          task("Creating models") { create_multi_tenant_models(roles) }
          task("Creating factories") { create_factories }
          task("Creating policies") { create_policies }
          task("Updating config") { update_config(identifier_column) }
          task("Creating seeders") { create_seeders(roles) }
        end

        if features.include?("audit_trail")
          task("Creating audit trail migration") { create_audit_trail_migration }
        end

        say ""
        run_post_install_steps(features)

        say ""
        say "Lumina installed successfully!", :green
        say ""

        print_next_steps(features)
      end

      private

      # ----------------------------------------------------------------
      # Banner
      # ----------------------------------------------------------------

      def print_banner
        say ""

        lines = [
          "  ██╗     ██╗   ██╗███╗   ███╗██╗███╗   ██╗ █████╗ ",
          "  ██║     ██║   ██║████╗ ████║██║████╗  ██║██╔══██╗",
          "  ██║     ██║   ██║██╔████╔██║██║██╔██╗ ██║███████║",
          "  ██║     ██║   ██║██║╚██╔╝██║██║██║╚██╗██║██╔══██║",
          "  ███████╗╚██████╔╝██║ ╚═╝ ██║██║██║ ╚████║██║  ██║",
          "  ╚══════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝"
        ]

        gradient = [
          [0, 255, 255],
          [0, 230, 200],
          [100, 220, 100],
          [255, 220, 50],
          [255, 170, 30],
          [255, 120, 0]
        ]

        lines.each_with_index do |text, i|
          r, g, b = gradient[i]
          $stdout.puts "\033[38;2;#{r};#{g};#{b}m#{text}\033[0m"
        end
      end

      # ----------------------------------------------------------------
      # Publish
      # ----------------------------------------------------------------

      def publish_config(test_framework)
        template_path = File.expand_path("../../templates/lumina.rb", __FILE__)
        dest_path = Rails.root.join("config/initializers/lumina.rb")

        FileUtils.mkdir_p(File.dirname(dest_path))

        content = File.read(template_path)
        content = content.gsub('test_framework: "rspec"', "test_framework: \"#{test_framework}\"")
        File.write(dest_path, content)
      end

      def publish_routes
        template_path = File.expand_path("../../templates/routes.rb", __FILE__)
        dest_path = Rails.root.join("config/routes/lumina.rb")

        FileUtils.mkdir_p(File.dirname(dest_path))
        FileUtils.cp(template_path, dest_path)
      end

      # ----------------------------------------------------------------
      # Multi-tenant
      # ----------------------------------------------------------------

      def create_multi_tenant_migrations
        timestamp = Time.current.strftime("%Y%m%d%H%M%S")
        migrations_path = Rails.root.join("db/migrate")
        FileUtils.mkdir_p(migrations_path)

        templates_dir = File.expand_path("../../templates/multi_tenant/migrations", __FILE__)

        {
          "create_organizations" => "#{timestamp}00",
          "create_roles" => "#{timestamp}01",
          "create_user_roles" => "#{timestamp}02"
        }.each do |name, ts|
          template = File.join(templates_dir, "#{name}.rb.erb")
          next unless File.exist?(template)

          content = ERB.new(File.read(template), trim_mode: "-").result(binding)
          File.write(migrations_path.join("#{ts}_#{name}.rb"), content)
        end
      end

      def create_multi_tenant_models(roles)
        models_path = Rails.root.join("app/models")
        FileUtils.mkdir_p(models_path)

        templates_dir = File.expand_path("../../templates/multi_tenant/models", __FILE__)

        %w[organization role user_role].each do |model|
          template = File.join(templates_dir, "#{model}.rb.erb")
          next unless File.exist?(template)

          dest_name = model.camelize
          content = ERB.new(File.read(template), trim_mode: "-").result_with_hash(roles: roles)
          File.write(models_path.join("#{model}.rb"), content)
        end
      end

      def create_factories
        factories_path = Rails.root.join("spec/factories")
        FileUtils.mkdir_p(factories_path)

        templates_dir = File.expand_path("../../templates/multi_tenant/factories", __FILE__)

        %w[organizations roles user_roles].each do |factory|
          template = File.join(templates_dir, "#{factory}.rb.erb")
          next unless File.exist?(template)

          content = ERB.new(File.read(template), trim_mode: "-").result(binding)
          File.write(factories_path.join("#{factory}.rb"), content)
        end
      end

      def create_policies
        policies_path = Rails.root.join("app/policies")
        FileUtils.mkdir_p(policies_path)

        templates_dir = File.expand_path("../../templates/multi_tenant/policies", __FILE__)

        %w[organization_policy role_policy].each do |policy|
          template = File.join(templates_dir, "#{policy}.rb.erb")
          next unless File.exist?(template)

          content = ERB.new(File.read(template), trim_mode: "-").result(binding)
          File.write(policies_path.join("#{policy}.rb"), content)
        end
      end

      def update_config(identifier_column)
        config_path = Rails.root.join("config/initializers/lumina.rb")
        return unless File.exist?(config_path)

        content = File.read(config_path)

        # Update organization_identifier_column
        content = content.gsub(
          'organization_identifier_column: "id"',
          "organization_identifier_column: \"#{identifier_column}\""
        )

        # Add organization and role models
        unless content.include?("c.model :organizations")
          content = content.gsub(
            "# c.model :posts, 'Post'",
            "c.model :organizations, 'Organization'\n  c.model :roles, 'Role'\n  # c.model :posts, 'Post'"
          )
        end

        # Add tenant route group
        unless content.include?("c.route_group :tenant")
          content = content.gsub(
            "# c.route_group :default",
            "c.route_group :tenant, prefix: \":organization\", middleware: [ResolveOrganizationFromRoute], models: :all\n  # c.route_group :default"
          )
        end

        File.write(config_path, content)
      end

      def create_seeders(roles)
        seeders_path = Rails.root.join("db/seeds")
        FileUtils.mkdir_p(seeders_path)

        templates_dir = File.expand_path("../../templates/multi_tenant/seeders", __FILE__)

        template = File.join(templates_dir, "role_seeder.rb.erb")
        if File.exist?(template)
          content = ERB.new(File.read(template), trim_mode: "-").result_with_hash(roles: roles)
          File.write(seeders_path.join("role_seeder.rb"), content)
        end

        template = File.join(templates_dir, "organization_seeder.rb.erb")
        if File.exist?(template)
          content = ERB.new(File.read(template), trim_mode: "-").result(binding)
          File.write(seeders_path.join("organization_seeder.rb"), content)
        end
      end

      # ----------------------------------------------------------------
      # Audit trail
      # ----------------------------------------------------------------

      def create_audit_trail_migration
        timestamp = Time.current.strftime("%Y%m%d%H%M%S")
        migrations_path = Rails.root.join("db/migrate")
        FileUtils.mkdir_p(migrations_path)

        # Check for existing
        existing = Dir.glob(migrations_path.join("*_create_audit_logs.rb"))
        return unless existing.empty?

        template = File.expand_path("../../templates/audit_trail/create_audit_logs.rb.erb", __FILE__)
        if File.exist?(template)
          content = ERB.new(File.read(template), trim_mode: "-").result(binding)
          File.write(migrations_path.join("#{timestamp}_create_audit_logs.rb"), content)
        end
      end

      # ----------------------------------------------------------------
      # Post-install
      # ----------------------------------------------------------------

      def run_post_install_steps(features)
        has_migrations = features.include?("multi_tenant") || features.include?("audit_trail")

        if has_migrations
          if yes?("Would you like to run migrations now? [y/N]")
            task("Running migrations") { system("rails db:migrate") }
          end
        end

        if features.include?("multi_tenant")
          if yes?("Would you like to seed the database? [y/N]")
            task("Seeding database") { system("rails db:seed") }
          end
        end
      end

      def print_next_steps(features)
        say "Remaining steps:", :yellow
        say ""

        step = 1

        if features.include?("audit_trail")
          say "  #{step}. Add Lumina::HasAuditTrail concern to your models:", :white
          say "     include Lumina::HasAuditTrail", :light_black
          step += 1
        end

        if features.include?("multi_tenant")
          say "  #{step}. Add Lumina::HasPermissions concern to your User model:", :white
          say "     include Lumina::HasPermissions", :light_black
          step += 1
        end

        say ""
      end

      # ----------------------------------------------------------------
      # Prompt helpers
      # ----------------------------------------------------------------

      def prompt_select(label, options, default: nil)
        say label, :yellow
        options.each_with_index do |(key, desc), i|
          marker = key == default ? " (default)" : ""
          say "  #{i + 1}. #{desc}#{marker}"
        end

        keys = options.keys
        choice = ask("Enter number [1-#{keys.length}]:")
        idx = (choice.to_i - 1).clamp(0, keys.length - 1)
        keys[idx]
      end

      def prompt_multiselect(label, options, default: [])
        say label, :yellow
        options.each_with_index do |(key, desc), i|
          marker = default.include?(key) ? " *" : ""
          say "  #{i + 1}. #{desc}#{marker}"
        end

        say "  Enter numbers separated by commas (e.g., 1,2,3):"
        input = ask("")
        if input.blank?
          default
        else
          keys = options.keys
          input.split(",").map { |n| keys[n.to_i - 1] }.compact
        end
      end

      def task(description)
        say "  → #{description}...", :cyan
        yield
        say "    ✓ Done", :green
      end
    end
  end
end
