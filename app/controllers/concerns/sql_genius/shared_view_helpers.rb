# frozen_string_literal: true

module SqlGenius
  module SharedViewHelpers
    extend ActiveSupport::Concern

    included do
      helper_method :path_for, :render_partial, :capability?
    end

    # URL path helper for shared templates.
    #   path_for(:execute) # => "/sql_genius/execute"
    #
    # When @digest is set (query detail page), routes that require a digest
    # param (query_detail, query_history) are generated with it automatically.
    #
    # `:query_detail_prefix` returns the engine-mount-aware base path that
    # the dashboard JS appends a digest to (so query stat rows link to
    # /sql_genius/queries/${digest} rather than /queries/${digest}).
    #
    # Uses SqlGenius::Engine.routes.url_helpers directly rather than the
    # `sql_genius` proxy: in production with eager loading, the proxy
    # method isn't always injected onto the engine's controller in time,
    # which surfaces as `NameError: undefined local variable or method
    # 'sql_genius'` the first time a view tries to build a URL.
    def path_for(name)
      helpers = SqlGenius::Engine.routes.url_helpers
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
    #   render_partial(:tab_dashboard) # => view_context.render partial: "sql_genius/queries/tab_dashboard"
    def render_partial(name)
      view_context.render(partial: "sql_genius/queries/#{name}")
    end

    # Capability flag for shared templates. Used to hide AI feature buttons
    # whose underlying service has no equivalent on the connected dialect
    # (e.g. InnoDB Health, Variable Review, Connection Advisor, Root Cause
    # Analysis, and Anomaly Detection all read MySQL-specific server state
    # via SHOW commands / performance_schema).
    #
    # All other capabilities default to true — the Rails adapter owns every
    # route, including Redis-backed slow_queries.
    def capability?(name)
      case name
      when :mysql_only_ai
        !connected_to_postgresql?
      else
        true
      end
    end

    private

    def connected_to_postgresql?
      SqlGenius::Core::Connection::ActiveRecordAdapter
        .new(ActiveRecord::Base.connection)
        .server_version
        .postgresql?
    rescue StandardError
      false
    end
  end
end
