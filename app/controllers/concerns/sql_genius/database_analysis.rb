# frozen_string_literal: true

module SqlGenius
  module DatabaseAnalysis
    extend ActiveSupport::Concern

    def duplicate_indexes
      duplicates = SqlGenius::Core::Analysis::DuplicateIndexes
        .new(rails_connection, blocked_tables: sql_genius_config.blocked_tables)
        .call
      render(json: duplicates)
    end

    def table_sizes
      tables = SqlGenius::Core::Analysis::TableSizes.new(rails_connection).call
      render(json: tables)
    end

    def query_stats
      sort = params[:sort].to_s
      limit = params.fetch(:limit, SqlGenius::Core::Analysis::QueryStats::MAX_LIMIT).to_i
      queries = SqlGenius::Core::Analysis::QueryStats.new(rails_connection).call(sort: sort, limit: limit)
      render(json: queries)
    rescue ActiveRecord::StatementInvalid => e
      render(json: { error: "#{query_stats_source_name} #{e.message.split(":").last.strip}" }, status: :unprocessable_entity)
    end

    def unused_indexes
      result = SqlGenius::Core::Analysis::UnusedIndexes.new(
        rails_connection,
        min_scans: sql_genius_config.min_unused_index_scans,
      ).call
      render(json: {
        indexes: result.indexes,
        stats_reset_at: result.stats_reset_at,
        min_scans: result.min_scans,
      })
    rescue ActiveRecord::StatementInvalid => e
      render(json: { error: "#{unused_indexes_source_name} #{e.message.split(":").last.strip}" }, status: :unprocessable_entity)
    end

    def server_overview
      overview = SqlGenius::Core::Analysis::ServerOverview.new(rails_connection).call
      render(json: overview)
    rescue => e
      render(json: { error: "Failed to load server overview: #{e.message}" }, status: :unprocessable_entity)
    end

    private

    def query_stats_source_name
      if rails_connection.server_version.postgresql?
        "Query statistics require the pg_stat_statements extension to be installed."
      else
        "Query statistics require performance_schema to be enabled."
      end
    end

    def unused_indexes_source_name
      if rails_connection.server_version.postgresql?
        "Unused index detection requires pg_stat_user_indexes (always available on PostgreSQL — check connection)."
      else
        "Unused index detection requires performance_schema."
      end
    end
  end
end
