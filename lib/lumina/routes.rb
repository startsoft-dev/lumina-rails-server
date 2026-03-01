# frozen_string_literal: true

module Lumina
  # Dynamic route registration from Lumina configuration.
  # Mirrors the Laravel routes/api.php behavior exactly.
  module Routes
    class << self
      def draw(router)
        config = Lumina.config
        models = config.models
        multi_tenant = config.multi_tenant
        is_multi_tenant = multi_tenant[:enabled]
        use_subdomain = multi_tenant[:use_subdomain]
        multi_tenant_middleware = multi_tenant[:middleware]
        needs_org_prefix = is_multi_tenant && !use_subdomain

        router.instance_eval do
          scope path: "api", defaults: { format: :json } do
            # ---------------------------------------------------------------
            # Auth Routes
            # ---------------------------------------------------------------
            scope path: "auth" do
              post "login", to: "lumina/auth#login"
              post "password/recover", to: "lumina/auth#recover_password"
              post "password/reset", to: "lumina/auth#reset"
              post "register", to: "lumina/auth#register_with_invitation"
              post "logout", to: "lumina/auth#logout"
            end

            # ---------------------------------------------------------------
            # Invitation accept (public)
            # ---------------------------------------------------------------
            post "invitations/accept", to: "lumina/invitations#accept"

            # ---------------------------------------------------------------
            # Invitation Routes (protected)
            # ---------------------------------------------------------------
            if is_multi_tenant
              invitation_prefix = needs_org_prefix ? ":organization/invitations" : "invitations"

              scope path: invitation_prefix do
                get "/", to: "lumina/invitations#index"
                post "/", to: "lumina/invitations#create"
                post ":id/resend", to: "lumina/invitations#resend"
                delete ":id", to: "lumina/invitations#cancel"
              end
            end

            # ---------------------------------------------------------------
            # Nested operations endpoint
            # ---------------------------------------------------------------
            nested_config = config.nested
            nested_path = nested_config[:path] || "nested"
            nested_prefix = needs_org_prefix ? ":organization/#{nested_path}" : nested_path

            post nested_prefix, to: "lumina/resources#nested", as: :lumina_nested

            # ---------------------------------------------------------------
            # Per-model CRUD routes
            # ---------------------------------------------------------------
            models.each do |slug, model_class_name|
              model_class = begin
                model_class_name.constantize
              rescue NameError
                next
              end

              except_actions = model_class.try(:lumina_except_actions_list) || []

              prefix = needs_org_prefix ? ":organization/#{slug}" : slug.to_s

              scope path: prefix, defaults: { model_slug: slug.to_s } do
                unless except_actions.include?("index")
                  get "/", to: "lumina/resources#index", as: "lumina_#{slug}_index"
                end

                unless except_actions.include?("store")
                  post "/", to: "lumina/resources#store", as: "lumina_#{slug}_store"
                end

                # Soft delete routes (before :id to avoid wildcard capture)
                if model_class.try(:uses_soft_deletes?)
                  unless except_actions.include?("trashed")
                    get "trashed", to: "lumina/resources#trashed", as: "lumina_#{slug}_trashed"
                  end

                  unless except_actions.include?("restore")
                    post ":id/restore", to: "lumina/resources#restore", as: "lumina_#{slug}_restore"
                  end

                  unless except_actions.include?("forceDelete")
                    delete ":id/force-delete", to: "lumina/resources#force_delete", as: "lumina_#{slug}_force_delete"
                  end
                end

                unless except_actions.include?("show")
                  get ":id", to: "lumina/resources#show", as: "lumina_#{slug}_show"
                end

                unless except_actions.include?("update")
                  put ":id", to: "lumina/resources#update", as: "lumina_#{slug}_update"
                end

                unless except_actions.include?("destroy")
                  delete ":id", to: "lumina/resources#destroy", as: "lumina_#{slug}_destroy"
                end
              end
            end
          end
        end
      end
    end
  end
end
