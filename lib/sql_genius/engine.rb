# frozen_string_literal: true

module SqlGenius
  class Engine < ::Rails::Engine
    isolate_namespace SqlGenius

    initializer "sql_genius.register_core_views", before: :add_view_paths do
      paths["app/views"] << SqlGenius::Core.views_path
    end

    config.after_initialize do
      if SqlGenius.configuration.redis_url.present?
        require "sql_genius/slow_query_monitor"
        SqlGenius::SlowQueryMonitor.subscribe!
      end

      if SqlGenius.configuration.stats_collection
        history = SqlGenius::Core::Analysis::StatsHistory.new
        connection_provider = -> { SqlGenius::Core::Connection::ActiveRecordAdapter.new(ActiveRecord::Base.connection) }
        collector = SqlGenius::Core::Analysis::StatsCollector.new(
          connection_provider: connection_provider,
          history: history,
        )
        SqlGenius.stats_history = history
        SqlGenius.stats_collector = collector
        collector.start
        at_exit { collector.stop }
      end
    end
  end
end
