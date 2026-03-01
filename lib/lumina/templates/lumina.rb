# frozen_string_literal: true

# Lumina Configuration
# This file is used to configure Lumina for your Rails application.
# See: https://github.com/startsoft/lumina-rails

Lumina.configure do |config|
  # ---------------------------------------------------------------
  # Models
  # ---------------------------------------------------------------
  # Register your models here. Each model gets automatic CRUD endpoints.
  #
  # config.model :posts, 'Post'
  # config.model :comments, 'Comment'
  # config.model :users, 'User'

  # ---------------------------------------------------------------
  # Public Models
  # ---------------------------------------------------------------
  # Models listed here do not require authentication.
  #
  # config.public_model :posts

  # ---------------------------------------------------------------
  # Multi-tenant
  # ---------------------------------------------------------------
  # config.multi_tenant = {
  #   enabled: false,
  #   use_subdomain: false,
  #   organization_identifier_column: 'id',  # Options: 'id', 'slug', or any column
  #   middleware: nil
  # }

  # ---------------------------------------------------------------
  # Invitations
  # ---------------------------------------------------------------
  # config.invitations = {
  #   expires_days: 7,
  #   allowed_roles: nil  # nil means all roles can invite
  # }

  # ---------------------------------------------------------------
  # Nested Operations
  # ---------------------------------------------------------------
  # config.nested = {
  #   path: 'nested',
  #   max_operations: 50,
  #   allowed_models: nil  # nil = all registered models
  # }

  # ---------------------------------------------------------------
  # Test Framework
  # ---------------------------------------------------------------
  # config.test_framework = 'rspec'  # Options: 'rspec', 'minitest'
end
