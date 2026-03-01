# frozen_string_literal: true

module Lumina
  module Middleware
    # Rack middleware that extracts the organization from the subdomain.
    # Mirrors the Laravel ResolveOrganizationFromSubdomain middleware.
    #
    # For subdomain multi-tenancy: https://acme-corp.yourapp.com/api/posts
    class ResolveOrganizationFromSubdomain
      RESERVED_SUBDOMAINS = %w[www app api localhost].freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        request = ActionDispatch::Request.new(env)
        host = request.host

        # Skip for reserved subdomains and IP addresses
        subdomain = extract_subdomain(host)

        if subdomain.present? && !RESERVED_SUBDOMAINS.include?(subdomain) && !ip_address?(host)
          organization = find_organization(subdomain)

          unless organization
            return [404, { "Content-Type" => "application/json" }, ['{"message":"Organization not found"}']]
          end

          # Check if authenticated user belongs to this organization
          user = resolve_user(request)
          if user && !user_belongs_to_organization?(user, organization)
            return [404, { "Content-Type" => "application/json" }, ['{"message":"Organization not found"}']]
          end

          env["lumina.organization"] = organization

          if defined?(RequestStore)
            RequestStore.store[:lumina_organization] = organization
          end
        end

        @app.call(env)
      end

      private

      def extract_subdomain(host)
        parts = host.split(".")
        return nil if parts.length <= 2
        parts.first
      end

      def ip_address?(host)
        host.match?(/\A\d+\.\d+\.\d+\.\d+\z/) || host == "127.0.0.1" || host == "localhost"
      end

      def find_organization(subdomain)
        org_class = "Organization".safe_constantize
        return nil unless org_class

        identifier_column = Lumina.config.multi_tenant[:organization_identifier_column] || "id"

        # Try domain column first, then identifier column
        if org_class.column_names.include?("domain")
          org_class.find_by(domain: subdomain)
        else
          org_class.find_by(identifier_column => subdomain)
        end
      end

      def resolve_user(request)
        token = request.headers["Authorization"]&.sub(/\ABearer /, "")
        return nil unless token

        user_class = "User".safe_constantize
        return nil unless user_class

        if user_class.column_names.include?("api_token")
          user_class.find_by(api_token: token)
        end
      end

      def user_belongs_to_organization?(user, organization)
        return true unless user.respond_to?(:user_roles)

        user.user_roles.exists?(organization_id: organization.id)
      end
    end
  end
end
