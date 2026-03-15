# frozen_string_literal: true

module Lumina
  module Blueprint
    module Generators
      # Generates RSpec test files with CRUD access, field visibility, and forbidden field tests.
      # Port of lumina-adonis-server test_generator.ts.
      class TestGenerator
        ALL_ACTIONS = %w[index show store update destroy trashed restore forceDelete].freeze

        # Generate a complete RSpec test file.
        #
        # @param blueprint [Hash] ParsedBlueprint
        # @param is_multi_tenant [Boolean]
        # @param org_identifier [String] 'slug' or 'id'
        # @return [String] Ruby source code
        def generate(blueprint, is_multi_tenant, org_identifier = "slug")
          model = blueprint[:model]
          slug = blueprint[:slug]
          permissions = blueprint[:permissions]
          columns = blueprint[:columns]

          crud_tests = build_crud_access_tests(slug, permissions, is_multi_tenant, org_identifier)
          visibility_tests = build_field_visibility_tests(slug, permissions, columns, is_multi_tenant, org_identifier)
          forbidden_tests = build_forbidden_field_tests(slug, permissions, columns, is_multi_tenant, org_identifier)

          if is_multi_tenant
            wrap_multi_tenant(model, slug, crud_tests, visibility_tests, forbidden_tests, org_identifier)
          else
            wrap_non_tenant(model, slug, crud_tests, visibility_tests, forbidden_tests)
          end
        end

        # Build CRUD access tests for all roles.
        #
        # @return [String]
        def build_crud_access_tests(slug, permissions, is_multi_tenant, org_identifier)
          return "" if permissions.empty?

          all_actions = ALL_ACTIONS.dup
          lines = []

          permissions.each do |role, perm|
            allowed = perm[:actions] & all_actions
            blocked = all_actions - perm[:actions]

            if allowed.any?
              lines << "    it 'allows #{role} to access allowed #{slug} endpoints' do"
              lines << build_user_setup(role, perm[:actions], slug, is_multi_tenant, org_identifier)
              lines << build_endpoint_assertions(slug, allowed, is_multi_tenant, org_identifier, true)
              lines << "    end"
              lines << ""
            end

            if blocked.any?
              lines << "    it 'blocks #{role} from blocked #{slug} endpoints' do"
              lines << build_user_setup(role, perm[:actions], slug, is_multi_tenant, org_identifier)
              lines << build_endpoint_assertions(slug, blocked, is_multi_tenant, org_identifier, false)
              lines << "    end"
              lines << ""
            end
          end

          lines.join("\n")
        end

        # Build field visibility tests.
        #
        # @return [String]
        def build_field_visibility_tests(slug, permissions, columns, is_multi_tenant, org_identifier)
          lines = []

          permissions.each do |role, perm|
            next unless perm[:actions].include?("show")
            next if perm[:show_fields] == ["*"]
            next if perm[:show_fields].empty?

            all_fields = columns.map { |c| c[:name] }
            visible = perm[:show_fields].include?("*") ? all_fields : perm[:show_fields]
            hidden = all_fields - visible + (perm[:hidden_fields] || [])
            hidden = hidden.uniq - visible

            next if hidden.empty? && visible.empty?

            lines << "    it 'shows only permitted fields for #{role} on #{slug}' do"

            if is_multi_tenant
              lines << "      user = create_user_with_role('#{role}', org, #{actions_to_permissions(perm[:actions], slug)})"
              lines << "      record = create(:#{slug.chomp('s')}, organization: org)"
              lines << "      get \"/api/\#{org.#{org_identifier}}/#{slug}/\#{record.id}\", headers: auth_headers(user)"
            else
              lines << "      user = create_user_with_permissions(#{actions_to_permissions(perm[:actions], slug)})"
              lines << "      record = create(:#{slug.chomp('s')})"
              lines << "      get \"/api/#{slug}/\#{record.id}\", headers: auth_headers(user)"
            end

            lines << "      expect(response).to have_http_status(:ok)"
            lines << "      data = JSON.parse(response.body)['data']"

            visible.each do |field|
              lines << "      expect(data).to have_key('#{field}')"
            end

            hidden.each do |field|
              lines << "      expect(data).not_to have_key('#{field}')"
            end

            lines << "    end"
            lines << ""
          end

          lines.join("\n")
        end

        # Build forbidden field tests.
        #
        # @return [String]
        def build_forbidden_field_tests(slug, permissions, columns, is_multi_tenant, org_identifier)
          lines = []

          permissions.each do |role, perm|
            next unless perm[:actions].include?("store")
            next if perm[:create_fields] == ["*"]
            next if perm[:create_fields].empty?

            all_fields = columns.map { |c| c[:name] }
            forbidden = all_fields - perm[:create_fields]

            next if forbidden.empty?

            lines << "    it 'returns 403 when #{role} tries to set restricted fields on #{slug}' do"

            if is_multi_tenant
              lines << "      user = create_user_with_role('#{role}', org, #{actions_to_permissions(perm[:actions], slug)})"
              lines << "      post \"/api/\#{org.#{org_identifier}}/#{slug}\","
            else
              lines << "      user = create_user_with_permissions(#{actions_to_permissions(perm[:actions], slug)})"
              lines << "      post \"/api/#{slug}\","
            end

            lines << "        params: { #{forbidden.first}: 'forbidden_value' },"
            lines << "        headers: auth_headers(user)"
            lines << "      expect(response).to have_http_status(:forbidden)"
            lines << "    end"
            lines << ""
          end

          lines.join("\n")
        end

        # Convert actions to permission string for test helpers.
        #
        # @param actions [Array<String>]
        # @param slug [String]
        # @return [String]
        def actions_to_permissions(actions, slug)
          if (ALL_ACTIONS - actions).empty?
            "['#{slug}.*']"
          else
            items = actions.map { |a| "'#{slug}.#{a}'" }
            "[#{items.join(', ')}]"
          end
        end

        private

        def build_user_setup(role, actions, slug, is_multi_tenant, org_identifier)
          perms = actions_to_permissions(actions, slug)
          if is_multi_tenant
            "      user = create_user_with_role('#{role}', org, #{perms})"
          else
            "      user = create_user_with_permissions(#{perms})"
          end
        end

        def build_endpoint_assertions(slug, actions, is_multi_tenant, org_identifier, expect_success)
          lines = []

          action_map = {
            "index" => { method: "get", path: "/#{slug}" },
            "show" => { method: "get", path: "/#{slug}/1" },
            "store" => { method: "post", path: "/#{slug}" },
            "update" => { method: "put", path: "/#{slug}/1" },
            "destroy" => { method: "delete", path: "/#{slug}/1" },
            "trashed" => { method: "get", path: "/#{slug}/trashed" },
            "restore" => { method: "post", path: "/#{slug}/1/restore" },
            "forceDelete" => { method: "delete", path: "/#{slug}/1/force" }
          }

          success_codes = { "store" => ":created" }
          default_success = ":ok"

          actions.each do |action|
            mapping = action_map[action]
            next unless mapping

            if is_multi_tenant
              url = "\"/api/\#{org.#{org_identifier}}#{mapping[:path]}\""
            else
              url = "\"/api#{mapping[:path]}\""
            end

            if expect_success
              code = success_codes[action] || default_success
              lines << "      #{mapping[:method]} #{url}, headers: auth_headers(user)"
              lines << "      expect(response).to have_http_status(#{code})"
            else
              lines << "      #{mapping[:method]} #{url}, headers: auth_headers(user)"
              lines << "      expect(response).to have_http_status(:forbidden)"
            end
          end

          lines.join("\n")
        end

        def wrap_multi_tenant(model, slug, crud_tests, visibility_tests, forbidden_tests, org_identifier)
          <<~RUBY
            # frozen_string_literal: true

            # Generated by Lumina Blueprint — zero-token deterministic generation.
            # To regenerate, modify the blueprint YAML and run: rails lumina:blueprint

            require 'rails_helper'

            RSpec.describe '#{model} — CRUD & Permissions', type: :request do
              let(:org) { create(:organization) }

              def create_user_with_role(role_slug, organization, permissions)
                user = create(:user)
                role = Role.find_or_create_by!(slug: role_slug, name: role_slug.capitalize)
                UserRole.find_or_create_by!(
                  user: user,
                  organization: organization,
                  role: role
                ) do |ur|
                  ur.permissions = permissions
                end
                user
              end

              def auth_headers(user)
                { 'Authorization' => "Bearer \#{user.auth_token}" }
              end

            #{crud_tests}
            #{visibility_tests}
            #{forbidden_tests}
            end
          RUBY
        end

        def wrap_non_tenant(model, slug, crud_tests, visibility_tests, forbidden_tests)
          <<~RUBY
            # frozen_string_literal: true

            # Generated by Lumina Blueprint — zero-token deterministic generation.
            # To regenerate, modify the blueprint YAML and run: rails lumina:blueprint

            require 'rails_helper'

            RSpec.describe '#{model} — CRUD & Permissions', type: :request do
              def create_user_with_permissions(permissions)
                create(:user, permissions: permissions)
              end

              def auth_headers(user)
                { 'Authorization' => "Bearer \#{user.auth_token}" }
              end

            #{crud_tests}
            #{visibility_tests}
            #{forbidden_tests}
            end
          RUBY
        end
      end
    end
  end
end
