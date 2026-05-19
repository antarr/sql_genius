# frozen_string_literal: true

module MysqlGenius
  class QueriesController < BaseController
    include QueryExecution
    include DatabaseAnalysis
    include AiFeatures
    include SharedViewHelpers

    def index
      @featured_tables = if mysql_genius_config.featured_tables.any?
        mysql_genius_config.featured_tables.sort
      else
        queryable_tables.sort
      end
      @all_tables = queryable_tables.sort
      @ai_enabled = mysql_genius_config.ai_enabled?
      @framework_version_major = Rails::VERSION::MAJOR
      @framework_version_minor = Rails::VERSION::MINOR
      @identifier_quote_char = identifier_quote_char
      render("mysql_genius/queries/dashboard")
    end

    def columns
      result = MysqlGenius::Core::Analysis::Columns.new(
        rails_connection,
        blocked_tables: mysql_genius_config.blocked_tables,
        masked_column_patterns: mysql_genius_config.masked_column_patterns,
        default_columns: mysql_genius_config.default_columns,
      ).call(table: params[:table])

      case result.status
      when :ok        then render(json: result.columns)
      when :blocked   then render(json: { error: result.error_message }, status: :forbidden)
      when :not_found then render(json: { error: result.error_message }, status: :not_found)
      end
    end

    def query_detail
      @digest = params[:digest].to_s
      render("mysql_genius/queries/query_detail")
    end

    def query_history
      digest = params[:digest].to_s

      query_history_service = MysqlGenius::Core::Analysis::QueryHistory.new(rails_connection)
      current_query = query_history_service.call(digest)
      history = fetch_query_history_series(digest, query_history_service)

      render(json: { query: current_query, history: history })
    rescue StandardError => e
      render(json: { error: e.message }, status: :unprocessable_entity)
    end

    def slow_queries
      unless mysql_genius_config.redis_url.present?
        return render(json: [], status: :ok)
      end

      require "redis"
      redis = Redis.new(url: mysql_genius_config.redis_url)
      key = SlowQueryMonitor.redis_key
      raw = redis.lrange(key, 0, 199)
      queries = raw.map do |entry|
        JSON.parse(entry)
      rescue JSON::ParserError
        nil
      end.compact
      render(json: queries)
    rescue StandardError => e
      render(json: { error: "Slow query error: #{e.message}" }, status: :unprocessable_entity)
    end

    private

    def identifier_quote_char
      ActiveRecord::Base.connection.quote_table_name("mysql_genius_identifier_probe")[0]
    end

    def queryable_tables
      ActiveRecord::Base.connection.tables - mysql_genius_config.blocked_tables
    end

    def fetch_query_history_series(digest, query_history_service)
      return [] unless MysqlGenius.stats_history

      digest_text = query_history_service.digest_text_for(digest)
      return [] unless digest_text

      MysqlGenius.stats_history.series_for(digest_text)
    end
  end
end
