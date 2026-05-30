# frozen_string_literal: true

module MysqlGenius
  module Core
    module Analysis
      # Indexes whose scan count is at or below `min_scans` (default 0 — never
      # scanned since the underlying stats source was last reset). On MySQL this
      # reads performance_schema.table_io_waits_summary_by_index_usage; on
      # PostgreSQL it reads pg_stat_user_indexes plus pg_relation_size for the
      # index byte size.
      #
      # Returns a Result with:
      #   indexes        — Array of per-index hashes (sorted by size DESC on PG,
      #                    by write count DESC on MySQL); each carries a dialect-
      #                    appropriate `drop_sql` and a `size_bytes` value (nil
      #                    on MySQL where individual index sizes aren't cheap).
      #   stats_reset_at — Time the underlying stats source was last reset
      #                    (PG only — pg_stat_database.stats_reset; nil on MySQL).
      #   min_scans      — The scan threshold used for this call, echoed back so
      #                    callers can display "indexes with ≤ N scans".
      #
      # Skips primary key indexes on both dialects, plus unique indexes (which
      # are usually backing a constraint the application depends on). Raises if
      # the underlying stats source is unavailable.
      class UnusedIndexes
        Result = Struct.new(:indexes, :stats_reset_at, :min_scans, keyword_init: true)

        def initialize(connection, min_scans: 0)
          @connection = connection
          @builder = QueryBuilders.for(connection)
          @min_scans = [min_scans.to_i, 0].max
        end

        def call
          rows = @connection.exec_query(@builder.unused_indexes(@connection, min_scans: @min_scans)).to_hashes
          Result.new(
            indexes: rows.map { |row| transform(row) },
            stats_reset_at: @builder.stats_reset_at(@connection),
            min_scans: @min_scans,
          )
        end

        private

        def transform(row)
          table = row["table_name"] || row["TABLE_NAME"]
          index_name = row["index_name"] || row["INDEX_NAME"]
          size_bytes = row["size_bytes"] || row["SIZE_BYTES"]
          {
            table: table,
            index_name: index_name,
            reads: (row["reads"] || row["READS"] || 0).to_i,
            writes: (row["writes"] || row["WRITES"] || 0).to_i,
            table_rows: (row["table_rows"] || row["TABLE_ROWS"] || 0).to_i,
            size_bytes: size_bytes&.to_i,
            drop_sql: @builder.drop_index_sql(table: table, index_name: index_name),
          }
        end
      end
    end
  end
end
