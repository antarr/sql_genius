# frozen_string_literal: true

module SqlGenius
  module Core
    module Analysis
      # Top statements by a given sort dimension, sourced from MySQL's
      # performance_schema.events_statements_summary_by_digest or PostgreSQL's
      # pg_stat_statements (whichever the connected server provides). Returns
      # an array of per-digest hashes with call counts, timing percentiles,
      # row examine/sent ratios, and temp-table metadata.
      #
      # If the underlying stats source is not enabled, the SQL exec will
      # raise — the caller decides how to render that.
      class QueryStats
        VALID_SORTS = ["total_time", "avg_time", "calls", "rows_examined"].freeze
        MAX_LIMIT = 50

        def initialize(connection)
          @connection = connection
          @builder = QueryBuilders.for(connection)
        end

        def call(sort: "total_time", limit: MAX_LIMIT)
          order_clause = @builder.query_stats_order_clause(sort)
          effective_limit = limit.to_i.clamp(1, MAX_LIMIT)

          sql = @builder.query_stats(
            @connection,
            order_clause: order_clause,
            limit: effective_limit,
            include_digest: digest_column_available?,
          )
          result = @connection.exec_query(sql)
          result.to_hashes.map { |row| transform(row) }
        end

        private

        def transform(row)
          digest = (row["DIGEST_TEXT"] || row["digest_text"] || "").to_s
          calls = (row["calls"] || row["CALLS"] || 0).to_i
          rows_examined = (row["rows_examined"] || row["ROWS_EXAMINED"] || 0).to_i
          rows_sent = (row["rows_sent"] || row["ROWS_SENT"] || 0).to_i

          {
            digest: (row["DIGEST"] || row["digest"] || "").to_s,
            sql: truncate(digest, 500),
            calls: calls,
            total_time_ms: (row["total_time_ms"] || 0).to_f,
            avg_time_ms: (row["avg_time_ms"] || 0).to_f,
            max_time_ms: (row["max_time_ms"] || 0).to_f,
            rows_examined: rows_examined,
            rows_sent: rows_sent,
            rows_ratio: rows_sent.positive? ? (rows_examined.to_f / rows_sent).round(1) : 0,
            tmp_disk_tables: (row["tmp_disk_tables"] || row["TMP_DISK_TABLES"] || 0).to_i,
            sort_rows: (row["sort_rows"] || row["SORT_ROWS"] || 0).to_i,
            first_seen: row["FIRST_SEEN"] || row["first_seen"],
            last_seen: row["LAST_SEEN"] || row["last_seen"],
          }
        end

        def truncate(string, max)
          return string if string.length <= max

          "#{string[0, max - 3]}..."
        end

        def digest_column_available?
          return @digest_available if defined?(@digest_available)

          @digest_available = @builder.digest_column_available?(@connection)
        end
      end
    end
  end
end
