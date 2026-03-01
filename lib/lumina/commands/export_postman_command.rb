# frozen_string_literal: true

require "rails/command"
require "json"

module Lumina
  module Commands
    # Generate a Postman Collection v2.1 for all registered models.
    # Mirrors Laravel `php artisan lumina:export-postman` exactly.
    #
    # Usage: rails lumina:export_postman [--output=postman_collection.json] [--base-url=http://localhost:3000/api]
    class ExportPostmanCommand < Rails::Command::Base
      namespace "lumina:export_postman"

      class_option :output, type: :string, default: "postman_collection.json", desc: "Output file path"
      class_option :base_url, type: :string, default: "http://localhost:3000/api", desc: "Base URL for requests"
      class_option :project_name, type: :string, default: nil, desc: "Collection name"

      desc "export_postman", "Generate a Postman Collection v2.1 for all registered models"
      def perform
        output_path = options[:output]
        base_url = options[:base_url].chomp("/")
        project_name = options[:project_name] || Rails.application.class.module_parent_name rescue "API"

        config = Lumina.config
        models = config.models
        is_multi_tenant = config.multi_tenant_enabled?
        use_subdomain = config.use_subdomain?
        needs_org_prefix = is_multi_tenant && !use_subdomain

        variables = build_collection_variables(base_url, needs_org_prefix)
        items = []

        items << build_auth_folder
        items << build_invitation_folder(needs_org_prefix) if is_multi_tenant

        models.each do |slug, model_class_name|
          model_class = begin
            model_class_name.constantize
          rescue NameError
            say "Model class does not exist: #{model_class_name}", :red
            next
          end

          model_meta = introspect_model(model_class, slug)
          items << {
            name: slug.to_s,
            item: build_action_folders(slug, model_meta, needs_org_prefix)
          }
        end

        collection = {
          info: {
            name: project_name,
            schema: "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
          },
          variable: variables,
          item: items
        }

        json = JSON.pretty_generate(collection)
        File.write(output_path, json)

        say "Postman collection written to #{output_path}", :green
      end

      private

      def build_collection_variables(base_url, needs_org_prefix)
        vars = [
          { key: "baseUrl", value: base_url },
          { key: "modelId", value: "1" },
          { key: "token", value: "" }
        ]
        vars << { key: "organization", value: "organization-1" } if needs_org_prefix
        vars
      end

      def build_auth_folder
        headers = default_headers
        json_headers = headers + [{ key: "Content-Type", value: "application/json" }]

        login_test = <<~JS
          const json = pm.response.json();
          if (json.token) {
              pm.collectionVariables.set("token", json.token);
          }
          if (json.organization_slug) {
              pm.collectionVariables.set("organization", json.organization_slug);
          }
        JS

        {
          name: "Authentication",
          item: [
            request_item("Login", "POST", "{{baseUrl}}/auth/login", {}, json_headers,
                          { email: "user@example.com", password: "password" }, login_test.strip),
            request_item("Logout", "POST", "{{baseUrl}}/auth/logout", {}, headers),
            request_item("Password recover", "POST", "{{baseUrl}}/auth/password/recover", {}, json_headers,
                          { email: "user@example.com" }),
            request_item("Password reset", "POST", "{{baseUrl}}/auth/password/reset", {}, json_headers,
                          { token: "{{token}}", email: "user@example.com", password: "new-password", password_confirmation: "new-password" }),
            request_item("Register (with invitation)", "POST", "{{baseUrl}}/auth/register", {}, json_headers,
                          { invitation_token: "{{token}}", name: "New User", password: "password", password_confirmation: "password" }),
            request_item("Accept invitation", "POST", "{{baseUrl}}/invitations/accept", {}, json_headers,
                          { token: "invitation-token" })
          ]
        }
      end

      def build_invitation_folder(needs_org_prefix)
        base = needs_org_prefix ? "{{baseUrl}}/{{organization}}/invitations" : "{{baseUrl}}/invitations"
        headers = default_headers
        json_headers = headers + [{ key: "Content-Type", value: "application/json" }]

        {
          name: "Invitations",
          item: [
            request_item("List invitations", "GET", base, {}, headers),
            request_item("List pending", "GET", base, { status: "pending" }, headers),
            request_item("Create invitation", "POST", base, {}, json_headers,
                          { email: "user@example.com", role_id: 1 }),
            request_item("Resend invitation", "POST", "#{base}/{{modelId}}/resend", {}, headers),
            request_item("Cancel invitation", "DELETE", "#{base}/{{modelId}}", {}, headers)
          ]
        }
      end

      def introspect_model(model_class, slug)
        {
          slug: slug,
          except_actions: model_class.try(:lumina_except_actions_list) || [],
          uses_soft_deletes: model_class.try(:uses_soft_deletes?) || false,
          allowed_filters: model_class.try(:allowed_filters) || [],
          allowed_sorts: model_class.try(:allowed_sorts) || [],
          allowed_fields: model_class.try(:allowed_fields) || [],
          allowed_includes: model_class.try(:allowed_includes) || [],
          allowed_search: model_class.try(:allowed_search) || [],
          default_sort: model_class.try(:default_sort_field)
        }
      end

      def build_action_folders(slug, meta, needs_org_prefix)
        folders = []
        base = needs_org_prefix ? "{{baseUrl}}/{{organization}}/#{slug}" : "{{baseUrl}}/#{slug}"
        except = meta[:except_actions]

        folders << { name: "Index", item: build_index_requests(base, slug, meta) } unless except.include?("index")
        folders << { name: "Show", item: build_show_requests(base, slug, meta) } unless except.include?("show")
        folders << { name: "Store", item: build_store_requests(base) } unless except.include?("store")
        folders << { name: "Update", item: build_update_requests(base) } unless except.include?("update")
        folders << { name: "Destroy", item: build_destroy_requests(base) } unless except.include?("destroy")

        if meta[:uses_soft_deletes]
          folders << { name: "Trashed", item: build_trashed_requests(base) } unless except.include?("trashed")
          folders << { name: "Restore", item: build_restore_requests(base) } unless except.include?("restore")
          folders << { name: "Force Delete", item: build_force_delete_requests(base) } unless except.include?("forceDelete")
        end

        folders
      end

      def build_index_requests(base, slug, meta)
        headers = default_headers
        requests = [request_item("List all", "GET", base, {}, headers)]

        meta[:allowed_filters].each do |filter|
          requests << request_item("Filter by #{filter}", "GET", base, { "filter[#{filter}]" => "example" }, headers)
        end

        meta[:allowed_sorts].each do |sort|
          requests << request_item("Sort by #{sort} (asc)", "GET", base, { sort: sort.to_s }, headers)
          requests << request_item("Sort by #{sort} (desc)", "GET", base, { sort: "-#{sort}" }, headers)
        end

        meta[:allowed_includes].each do |inc|
          requests << request_item("Include #{inc}", "GET", base, { include: inc.to_s }, headers)
        end

        unless meta[:allowed_fields].empty?
          requests << request_item("Select fields", "GET", base,
                                   { "fields[#{slug}]" => meta[:allowed_fields].first(5).join(",") }, headers)
        end

        unless meta[:allowed_search].empty?
          requests << request_item("Search", "GET", base, { search: "example" }, headers)
        end

        requests << request_item("Paginate", "GET", base, { per_page: "5", page: "1" }, headers)

        requests
      end

      def build_show_requests(base, slug, meta)
        path = "#{base}/{{modelId}}"
        headers = default_headers
        requests = [request_item("Show by ID", "GET", path, {}, headers)]

        unless meta[:allowed_includes].empty?
          requests << request_item("Show with include", "GET", path, { include: meta[:allowed_includes].first.to_s }, headers)
        end

        requests
      end

      def build_store_requests(base)
        headers = default_headers + [{ key: "Content-Type", value: "application/json" }]
        [request_item("Create", "POST", base, {}, headers, { title: "Example" })]
      end

      def build_update_requests(base)
        path = "#{base}/{{modelId}}"
        headers = default_headers + [{ key: "Content-Type", value: "application/json" }]
        [request_item("Update", "PUT", path, {}, headers, { title: "Updated" })]
      end

      def build_destroy_requests(base)
        path = "#{base}/{{modelId}}"
        [request_item("Delete by ID", "DELETE", path, {}, default_headers)]
      end

      def build_trashed_requests(base)
        [request_item("List trashed", "GET", "#{base}/trashed", {}, default_headers)]
      end

      def build_restore_requests(base)
        [request_item("Restore by ID", "POST", "#{base}/{{modelId}}/restore", {}, default_headers)]
      end

      def build_force_delete_requests(base)
        [request_item("Force delete by ID", "DELETE", "#{base}/{{modelId}}/force-delete", {}, default_headers)]
      end

      def default_headers
        [
          { key: "Accept", value: "application/json" },
          { key: "Authorization", value: "Bearer {{token}}" }
        ]
      end

      def request_item(name, method, path, query_params, headers, body = nil, test_script = nil)
        query = query_params.map { |k, v| { key: k.to_s, value: v.to_s } }

        raw = path
        unless query.empty?
          raw += "?" + query.map { |q| "#{q[:key]}=#{q[:value]}" }.join("&")
        end

        parts = path.split("/").reject(&:empty?)
        url = {
          raw: raw,
          host: [parts.shift || "{{baseUrl}}"],
          path: parts
        }
        url[:query] = query unless query.empty?

        req = { method: method, header: headers, url: url }

        if body && %w[POST PUT PATCH].include?(method)
          req[:body] = {
            mode: "raw",
            raw: JSON.pretty_generate(body),
            options: { raw: { language: "json" } }
          }
        end

        item = { name: name }
        if test_script
          item[:event] = [{
            listen: "test",
            script: { exec: test_script.split("\n"), type: "text/javascript" }
          }]
        end
        item[:request] = req
        item
      end
    end
  end
end
