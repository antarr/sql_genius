# frozen_string_literal: true

module MysqlGenius
  module Core
    module Analysis
      # Finds indexes with zero reads but a non-zero parent table row count.
      # On MySQL this reads performance_schema.table_io_waits_summary_by_index_usage;
      # on PostgreSQL it reads pg_stat_user_indexes. Returns hashes with a
      # ready-to-run DROP INDEX statement appropriate for the dialect.
      #
      # Skips primary key indexes on both dialects. Raises if the underlying
      # stats source is unavailable.
      class UnusedIndexes
        def initialize(connection)
          @connection = connection
          @builder = QueryBuilders.for(connection)
        end

        def call
          result = @connection.exec_query(@builder.unused_indexes(@connection))

          result.to_hashes.map do |row|
            table = row["table_name"] || row["TABLE_NAME"]
            index_name = row["index_name"] || row["INDEX_NAME"]
            {
              table: table,
              index_name: index_name,
              reads: (row["reads"] || row["READS"] || 0).to_i,
              writes: (row["writes"] || row["WRITES"] || 0).to_i,
              table_rows: (row["table_rows"] || row["TABLE_ROWS"] || 0).to_i,
              drop_sql: @builder.drop_index_sql(table: table, index_name: index_name),
            }
          end
        end
      end
    end
  end
end
