# frozen_string_literal: true

module MysqlGenius
  module SharedViewHelpers
    extend ActiveSupport::Concern

    included do
      helper_method :path_for, :render_partial, :capability?
    end

    # URL path helper for shared templates.
    #   path_for(:execute) # => "/mysql_genius/execute"
    #
    # When @digest is set (query detail page), routes that require a digest
    # param (query_detail, query_history) are generated with it automatically.
    #
    # `:query_detail_prefix` returns the engine-mount-aware base path that
    # the dashboard JS appends a digest to (so query stat rows link to
    # /mysql_genius/queries/${digest} rather than /queries/${digest}).
    #
    # Uses MysqlGenius::Engine.routes.url_helpers directly rather than the
    # `mysql_genius` proxy: in production with eager loading, the proxy
    # method isn't always injected onto the engine's controller in time,
    # which surfaces as `NameError: undefined local variable or method
    # 'mysql_genius'` the first time a view tries to build a URL.
    def path_for(name)
      helpers = MysqlGenius::Engine.routes.url_helpers
      case name
      when :query_detail_prefix
        "#{helpers.root_path}queries/"
      when :query_detail, :query_history
        if @digest
          helpers.public_send("#{name}_path", digest: @digest)
        else
          helpers.public_send("#{name}_path", digest: "")
        end
      else
        helpers.public_send("#{name}_path")
      end
    end

    # Partial renderer for shared templates.
    #   render_partial(:tab_dashboard) # => view_context.render partial: "mysql_genius/queries/tab_dashboard"
    def render_partial(name)
      view_context.render(partial: "mysql_genius/queries/#{name}")
    end

    # Capability flag for shared templates. The Rails adapter always
    # reports every capability as present because it owns all routes
    # (including the Redis-backed slow_queries / anomaly_detection /
    # root_cause features).
    def capability?(_name)
      true
    end
  end
end
