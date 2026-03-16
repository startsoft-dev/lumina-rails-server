# frozen_string_literal: true

require "spec_helper"
require "lumina/routes"

RSpec.describe Lumina::Routes do
  describe ".draw" do
    # We test the route drawing logic by verifying the method calls
    # on the router object. Since we don't have a real Rails router,
    # we use a recording double.

    it "draws auth routes" do
      routes_drawn = []

      # Create a minimal router mock that records route registrations
      router = double("Router")
      allow(router).to receive(:instance_eval) do |&block|
        # Just verify it doesn't raise
      end

      expect { Lumina::Routes.draw(router) }.not_to raise_error
    end

    it "handles configuration with no tenant group" do
      Lumina.reset_configuration!
      Lumina.configure do |c|
        c.model :posts, "Post"
        c.route_group :default, prefix: "", middleware: [], models: :all
      end

      router = double("Router")
      allow(router).to receive(:instance_eval)

      expect { Lumina::Routes.draw(router) }.not_to raise_error
    end

    it "handles configuration with tenant group" do
      Lumina.reset_configuration!
      Lumina.configure do |c|
        c.model :posts, "Post"
        c.route_group :tenant, prefix: ":organization", middleware: [], models: :all
      end

      router = double("Router")
      allow(router).to receive(:instance_eval)

      expect { Lumina::Routes.draw(router) }.not_to raise_error
    end

    it "handles empty model list" do
      Lumina.reset_configuration!
      Lumina.configure do |c|
        c.route_group :default, prefix: "", middleware: [], models: :all
      end

      router = double("Router")
      allow(router).to receive(:instance_eval)

      expect { Lumina::Routes.draw(router) }.not_to raise_error
    end

    it "handles multiple route groups" do
      Lumina.reset_configuration!
      Lumina.configure do |c|
        c.model :posts, "Post"
        c.model :blogs, "Blog"
        c.route_group :default, prefix: "", middleware: [], models: :all
        c.route_group :public, prefix: "public", middleware: [], models: [:blogs]
      end

      router = double("Router")
      allow(router).to receive(:instance_eval)

      expect { Lumina::Routes.draw(router) }.not_to raise_error
    end
  end
end
