# frozen_string_literal: true

require "spec_helper"
require "rails/command"
require "json"
require "lumina/commands/export_postman_command"

RSpec.describe Lumina::Commands::ExportPostmanCommand do
  let(:tmp_dir) { Dir.mktmpdir("lumina_postman_test") }
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
  # build_collection_variables
  # ------------------------------------------------------------------

  describe "#build_collection_variables" do
    it "returns base variables without org prefix" do
      vars = command.send(:build_collection_variables, "http://localhost:3000/api", false)

      expect(vars.length).to eq(3)
      expect(vars.map { |v| v[:key] }).to contain_exactly("baseUrl", "modelId", "token")
      expect(vars.find { |v| v[:key] == "baseUrl" }[:value]).to eq("http://localhost:3000/api")
    end

    it "includes organization variable with org prefix" do
      vars = command.send(:build_collection_variables, "http://localhost:3000/api", true)

      expect(vars.length).to eq(4)
      expect(vars.map { |v| v[:key] }).to include("organization")
    end
  end

  # ------------------------------------------------------------------
  # build_auth_folder
  # ------------------------------------------------------------------

  describe "#build_auth_folder" do
    it "returns Authentication folder with correct items" do
      folder = command.send(:build_auth_folder)

      expect(folder[:name]).to eq("Authentication")
      expect(folder[:item].length).to eq(6)

      names = folder[:item].map { |i| i[:name] }
      expect(names).to include("Login", "Logout", "Password recover",
                                "Password reset", "Register (with invitation)",
                                "Accept invitation")
    end

    it "Login request includes test script for token extraction" do
      folder = command.send(:build_auth_folder)
      login_item = folder[:item].find { |i| i[:name] == "Login" }

      expect(login_item[:event]).not_to be_nil
      script_exec = login_item[:event].first[:script][:exec]
      expect(script_exec.join("\n")).to include("pm.collectionVariables.set")
    end

    it "Login request has POST method with JSON body" do
      folder = command.send(:build_auth_folder)
      login_item = folder[:item].find { |i| i[:name] == "Login" }

      expect(login_item[:request][:method]).to eq("POST")
      expect(login_item[:request][:body]).not_to be_nil
      expect(login_item[:request][:body][:mode]).to eq("raw")
    end
  end

  # ------------------------------------------------------------------
  # build_invitation_folder
  # ------------------------------------------------------------------

  describe "#build_invitation_folder" do
    it "uses direct base URL without org prefix" do
      folder = command.send(:build_invitation_folder, false)

      expect(folder[:name]).to eq("Invitations")
      list_item = folder[:item].find { |i| i[:name] == "List invitations" }
      raw_url = list_item[:request][:url][:raw]
      expect(raw_url).to include("{{baseUrl}}/invitations")
      expect(raw_url).not_to include("{{organization}}")
    end

    it "includes organization prefix when needed" do
      folder = command.send(:build_invitation_folder, true)

      list_item = folder[:item].find { |i| i[:name] == "List invitations" }
      raw_url = list_item[:request][:url][:raw]
      expect(raw_url).to include("{{organization}}")
    end

    it "includes 5 invitation endpoints" do
      folder = command.send(:build_invitation_folder, false)
      expect(folder[:item].length).to eq(5)

      names = folder[:item].map { |i| i[:name] }
      expect(names).to include("List invitations", "List pending",
                                "Create invitation", "Resend invitation",
                                "Cancel invitation")
    end
  end

  # ------------------------------------------------------------------
  # introspect_model
  # ------------------------------------------------------------------

  describe "#introspect_model" do
    it "extracts metadata from model class" do
      meta = command.send(:introspect_model, Post, :posts)

      expect(meta[:slug]).to eq(:posts)
      expect(meta[:allowed_filters].map(&:to_s)).to include("title", "status")
      expect(meta[:allowed_sorts].map(&:to_s)).to include("title", "created_at")
      expect(meta[:allowed_fields].map(&:to_s)).to include("id", "title")
      expect(meta[:allowed_includes].map(&:to_s)).to include("user", "comments")
      expect(meta[:allowed_search].map(&:to_s)).to include("title", "content")
    end

    it "detects soft deletes" do
      meta = command.send(:introspect_model, Post, :posts)
      # Post includes Discard::Model
      expect(meta[:uses_soft_deletes]).to be true
    end
  end

  # ------------------------------------------------------------------
  # build_action_folders
  # ------------------------------------------------------------------

  describe "#build_action_folders" do
    let(:meta) do
      {
        slug: :posts,
        except_actions: [],
        uses_soft_deletes: false,
        allowed_filters: [:status],
        allowed_sorts: [:created_at],
        allowed_fields: [:id, :title],
        allowed_includes: [:user],
        allowed_search: [:title],
        default_sort: "-created_at"
      }
    end

    it "creates standard CRUD folders" do
      folders = command.send(:build_action_folders, :posts, meta, false)
      folder_names = folders.map { |f| f[:name] }

      expect(folder_names).to include("Index", "Show", "Store", "Update", "Destroy")
    end

    it "includes soft delete folders when model uses soft deletes" do
      meta_with_soft_delete = meta.merge(uses_soft_deletes: true)
      folders = command.send(:build_action_folders, :posts, meta_with_soft_delete, false)
      folder_names = folders.map { |f| f[:name] }

      expect(folder_names).to include("Trashed", "Restore", "Force Delete")
    end

    it "excludes folders listed in except_actions" do
      meta_with_except = meta.merge(except_actions: ["store", "destroy"])
      folders = command.send(:build_action_folders, :posts, meta_with_except, false)
      folder_names = folders.map { |f| f[:name] }

      expect(folder_names).not_to include("Store", "Destroy")
      expect(folder_names).to include("Index", "Show", "Update")
    end

    it "includes org prefix in URLs when needed" do
      folders = command.send(:build_action_folders, :posts, meta, true)
      index_folder = folders.find { |f| f[:name] == "Index" }
      list_item = index_folder[:item].first

      expect(list_item[:request][:url][:raw]).to include("{{organization}}")
    end
  end

  # ------------------------------------------------------------------
  # build_index_requests
  # ------------------------------------------------------------------

  describe "#build_index_requests" do
    let(:meta) do
      {
        slug: :posts,
        allowed_filters: [:status, :user_id],
        allowed_sorts: [:created_at, :title],
        allowed_fields: [:id, :title, :status],
        allowed_includes: [:user],
        allowed_search: [:title],
        default_sort: "-created_at"
      }
    end

    it "includes list, filter, sort, include, fields, search, and pagination requests" do
      requests = command.send(:build_index_requests, "{{baseUrl}}/posts", :posts, meta)

      names = requests.map { |r| r[:name] }
      expect(names).to include("List all")
      expect(names).to include("Filter by status")
      expect(names).to include("Sort by created_at (asc)")
      expect(names).to include("Sort by created_at (desc)")
      expect(names).to include("Include user")
      expect(names).to include("Select fields")
      expect(names).to include("Search")
      expect(names).to include("Paginate")
    end
  end

  # ------------------------------------------------------------------
  # request_item
  # ------------------------------------------------------------------

  describe "#request_item" do
    it "builds a GET request" do
      item = command.send(:request_item, "List all", "GET",
                          "{{baseUrl}}/posts", {}, [{ key: "Accept", value: "application/json" }])

      expect(item[:name]).to eq("List all")
      expect(item[:request][:method]).to eq("GET")
      expect(item[:request][:body]).to be_nil
    end

    it "builds a POST request with body" do
      headers = [
        { key: "Accept", value: "application/json" },
        { key: "Content-Type", value: "application/json" }
      ]
      item = command.send(:request_item, "Create", "POST",
                          "{{baseUrl}}/posts", {}, headers,
                          { title: "Example" })

      expect(item[:request][:method]).to eq("POST")
      expect(item[:request][:body]).not_to be_nil
      expect(item[:request][:body][:mode]).to eq("raw")

      body = JSON.parse(item[:request][:body][:raw])
      expect(body["title"]).to eq("Example")
    end

    it "includes query parameters in URL" do
      item = command.send(:request_item, "Filter", "GET",
                          "{{baseUrl}}/posts",
                          { "filter[status]" => "active" },
                          [{ key: "Accept", value: "application/json" }])

      expect(item[:request][:url][:raw]).to include("filter[status]=active")
      expect(item[:request][:url][:query]).not_to be_empty
    end

    it "includes test script when provided" do
      script = "pm.test('ok', function() {});"
      item = command.send(:request_item, "Test", "GET",
                          "{{baseUrl}}/posts", {},
                          [{ key: "Accept", value: "application/json" }],
                          nil, script)

      expect(item[:event]).not_to be_nil
      expect(item[:event].first[:listen]).to eq("test")
      expect(item[:event].first[:script][:exec]).to include(script)
    end
  end

  # ------------------------------------------------------------------
  # default_headers
  # ------------------------------------------------------------------

  describe "#default_headers" do
    it "includes Accept and Authorization headers" do
      headers = command.send(:default_headers)

      expect(headers.length).to eq(2)
      expect(headers.find { |h| h[:key] == "Accept" }[:value]).to eq("application/json")
      expect(headers.find { |h| h[:key] == "Authorization" }[:value]).to eq("Bearer {{token}}")
    end
  end

  # ------------------------------------------------------------------
  # Full collection generation
  # ------------------------------------------------------------------

  describe "#perform (full collection)" do
    it "generates a valid Postman collection JSON file" do
      Lumina.configure do |c|
        c.model :posts, "Post"
        c.model :blogs, "Blog"
      end

      output_path = File.join(tmp_dir, "collection.json")
      allow(command).to receive(:options).and_return({
        output: output_path,
        base_url: "http://localhost:3000/api",
        project_name: "TestAPI"
      })

      command.perform

      expect(File.exist?(output_path)).to be true

      collection = JSON.parse(File.read(output_path))
      expect(collection["info"]["name"]).to eq("TestAPI")
      expect(collection["info"]["schema"]).to include("postman.com")
      expect(collection["variable"]).to be_an(Array)
      expect(collection["item"]).to be_an(Array)

      # Should have Authentication folder + model folders
      item_names = collection["item"].map { |i| i["name"] }
      expect(item_names).to include("Authentication", "posts", "blogs")
    end
  end
end
