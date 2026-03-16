# frozen_string_literal: true

namespace :lumina do
  desc "Install and configure Lumina for your Rails application"
  task install: :environment do
    require "lumina/commands/install_command"
    Lumina::Commands::InstallCommand.new.perform
  end

  desc "Generate Lumina resources (Model, Policy, Scope)"
  task generate: :environment do
    require "lumina/commands/generate_command"
    Lumina::Commands::GenerateCommand.new.perform
  end

  desc "Generate code from YAML blueprint files"
  task blueprint: :environment do
    require "lumina/commands/blueprint_command"
    Lumina::Commands::BlueprintCommand.new.perform
  end

  desc "Export Postman collection for all registered models"
  task export_postman: :environment do
    require "lumina/commands/export_postman_command"
    cmd = Lumina::Commands::ExportPostmanCommand.new
    cmd.perform
  end
end

namespace :invitation do
  desc "Generate an invitation link for testing"
  task :link, [:email, :organization] => :environment do |_t, args|
    require "lumina/commands/invitation_link_command"
    cmd = Lumina::Commands::InvitationLinkCommand.new
    cmd.email = args[:email]
    cmd.organization_identifier = args[:organization]
    cmd.perform
  end
end
