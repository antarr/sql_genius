# frozen_string_literal: true

module SqlGenius
  module Core
    module Analysis
      # Fetches a single query's aggregated stats by its digest/queryid for the
      # query detail page. Returns nil if the digest is not found in the
      # statement-stats source for the current database.
      #
      # On MySQL/MariaDB this reads performance_schema.events_statements_summary_by_digest;
      # on PostgreSQL it reads pg_stat_statements joined with pg_database.
      class QueryHistory
        def initialize(connection)
          @connection = connection
          @builder = QueryBuilders.for(connection)
        end

        def call(digest)
          digest_str = digest.to_s
          return if digest_str.empty?

          sql = @builder.query_history(@connection, digest: digest_str)
          result = @connection.exec_query(sql)
          row = result.to_hashes.first
          return unless row

          {
            sql: row["DIGEST_TEXT"] || row["digest_text"],
            calls: (row["calls"] || row["CALLS"] || 0).to_i,
            total_time_ms: (row["total_time_ms"] || 0).to_f,
            avg_time_ms: (row["avg_time_ms"] || 0).to_f,
            max_time_ms: (row["max_time_ms"] || 0).to_f,
            rows_examined: (row["rows_examined"] || row["ROWS_EXAMINED"] || 0).to_i,
            rows_sent: (row["rows_sent"] || row["ROWS_SENT"] || 0).to_i,
            first_seen: (row["FIRST_SEEN"] || row["first_seen"]).to_s,
            last_seen: (row["LAST_SEEN"] || row["last_seen"]).to_s,
          }
        end

        def digest_text_for(digest)
          digest_str = digest.to_s
          return if digest_str.empty?

          sql = @builder.digest_text_lookup(@connection, digest: digest_str)
          @connection.select_value(sql)
        end
      end
    end
  end
end
