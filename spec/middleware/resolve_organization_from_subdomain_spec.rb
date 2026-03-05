# frozen_string_literal: true

require "spec_helper"
require "lumina/middleware/resolve_organization_from_subdomain"

RSpec.describe Lumina::Middleware::ResolveOrganizationFromSubdomain do
  let(:app) { ->(env) { [200, { "Content-Type" => "application/json" }, ['{"success":true}']] } }
  let(:middleware) { described_class.new(app) }

  before do
    Lumina.configure do |c|
      c.multi_tenant = { organization_identifier_column: "slug" }
    end
  end

  # ------------------------------------------------------------------
  # Pass-through for main domain / reserved subdomains
  # ------------------------------------------------------------------

  describe "pass-through" do
    it "passes through for localhost" do
      env = Rack::MockRequest.env_for("http://localhost/api/users", method: "GET")

      status, _headers, _body = middleware.call(env)

      expect(status).to eq(200)
      expect(env["lumina.organization"]).to be_nil
    end

    it "passes through for www subdomain" do
      env = Rack::MockRequest.env_for("http://www.example.com/api/users", method: "GET")

      status, _headers, _body = middleware.call(env)

      expect(status).to eq(200)
      expect(env["lumina.organization"]).to be_nil
    end

    it "passes through for app subdomain" do
      env = Rack::MockRequest.env_for("http://app.example.com/api/users", method: "GET")

      status, _headers, _body = middleware.call(env)

      expect(status).to eq(200)
      expect(env["lumina.organization"]).to be_nil
    end

    it "passes through for api subdomain" do
      env = Rack::MockRequest.env_for("http://api.example.com/api/users", method: "GET")

      status, _headers, _body = middleware.call(env)

      expect(status).to eq(200)
      expect(env["lumina.organization"]).to be_nil
    end

    it "passes through for IP addresses" do
      env = Rack::MockRequest.env_for("http://127.0.0.1/api/users", method: "GET")

      status, _headers, _body = middleware.call(env)

      expect(status).to eq(200)
      expect(env["lumina.organization"]).to be_nil
    end

    it "passes through for two-part domains" do
      env = Rack::MockRequest.env_for("http://example.com/api/users", method: "GET")

      status, _headers, _body = middleware.call(env)

      expect(status).to eq(200)
      expect(env["lumina.organization"]).to be_nil
    end
  end

  # ------------------------------------------------------------------
  # Organization resolution
  # ------------------------------------------------------------------

  describe "organization resolution by subdomain" do
    it "resolves organization by subdomain" do
      org = Organization.create!(name: "Test Organization", slug: "test-org-sub")

      env = Rack::MockRequest.env_for("http://test-org-sub.example.com/api/users", method: "GET")

      status, _headers, _body = middleware.call(env)

      expect(status).to eq(200)
      expect(env["lumina.organization"]).to be_present
      expect(env["lumina.organization"].id).to eq(org.id)
      expect(env["lumina.organization"].slug).to eq("test-org-sub")
    end

    it "returns 404 when organization not found by subdomain" do
      env = Rack::MockRequest.env_for("http://nonexistent.example.com/api/users", method: "GET")

      status, _headers, body = middleware.call(env)

      expect(status).to eq(404)
      response = JSON.parse(body.first)
      expect(response["message"]).to eq("Organization not found")
    end
  end

  # ------------------------------------------------------------------
  # User membership check
  # ------------------------------------------------------------------

  describe "user membership check" do
    it "allows authenticated user who belongs to organization" do
      org = Organization.create!(name: "Member Org Sub", slug: "member-org-sub")
      user = User.create!(name: "Member Sub", email: "member-sub@test.com", api_token: "valid-token-sub")
      role = Role.create!(name: "Member Role Sub", slug: "member-role-sub", permissions: ["*"])
      UserRole.create!(user: user, organization: org, role: role)

      env = Rack::MockRequest.env_for("http://member-org-sub.example.com/api/users", method: "GET")
      env["HTTP_AUTHORIZATION"] = "Bearer valid-token-sub"

      status, _headers, _body = middleware.call(env)

      expect(status).to eq(200)
      expect(env["lumina.organization"].id).to eq(org.id)
    end

    it "returns 404 for authenticated user who does not belong to organization" do
      org = Organization.create!(name: "Other Org Sub", slug: "other-org-sub")
      user = User.create!(name: "Non-member Sub", email: "nonmember-sub@test.com", api_token: "nonmember-token-sub")

      env = Rack::MockRequest.env_for("http://other-org-sub.example.com/api/users", method: "GET")
      env["HTTP_AUTHORIZATION"] = "Bearer nonmember-token-sub"

      status, _headers, _body = middleware.call(env)

      expect(status).to eq(404)
    end
  end

  # ------------------------------------------------------------------
  # Reserved subdomains
  # ------------------------------------------------------------------

  describe "reserved subdomains constant" do
    it "defines reserved subdomains" do
      expect(described_class::RESERVED_SUBDOMAINS).to include("www", "app", "api", "localhost")
    end
  end

  # ------------------------------------------------------------------
  # Subdomain extraction
  # ------------------------------------------------------------------

  describe "subdomain extraction" do
    it "extracts subdomain from three-part host" do
      middleware_instance = described_class.new(app)
      subdomain = middleware_instance.send(:extract_subdomain, "acme.example.com")
      expect(subdomain).to eq("acme")
    end

    it "returns nil for two-part host" do
      middleware_instance = described_class.new(app)
      subdomain = middleware_instance.send(:extract_subdomain, "example.com")
      expect(subdomain).to be_nil
    end

    it "returns nil for single-part host" do
      middleware_instance = described_class.new(app)
      subdomain = middleware_instance.send(:extract_subdomain, "localhost")
      expect(subdomain).to be_nil
    end
  end

  # ------------------------------------------------------------------
  # IP address detection
  # ------------------------------------------------------------------

  describe "IP address detection" do
    it "detects IPv4 addresses" do
      middleware_instance = described_class.new(app)
      expect(middleware_instance.send(:ip_address?, "192.168.1.1")).to be true
    end

    it "detects localhost IP" do
      middleware_instance = described_class.new(app)
      expect(middleware_instance.send(:ip_address?, "127.0.0.1")).to be true
    end

    it "detects localhost string" do
      middleware_instance = described_class.new(app)
      expect(middleware_instance.send(:ip_address?, "localhost")).to be true
    end

    it "does not detect domain as IP" do
      middleware_instance = described_class.new(app)
      expect(middleware_instance.send(:ip_address?, "example.com")).to be false
    end
  end
end
