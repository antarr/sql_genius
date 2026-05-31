# frozen_string_literal: true

module SqlGenius
  module Core
    module Analysis
      # Returns size/fragmentation metrics for each user table in the current
      # database, plus an exact SELECT COUNT(*) for each table. Delegates SQL
      # generation to the dialect-appropriate QueryBuilder so the same class
      # works against MySQL/MariaDB (information_schema.tables) and PostgreSQL
      # (pg_class + pg_total_relation_size).
      #
      # Takes a Core::Connection. Returns an array of hashes suitable for
      # JSON rendering.
      class TableSizes
        def initialize(connection)
          @connection = connection
          @builder = QueryBuilders.for(connection)
        end

        def call
          result = @connection.exec_query(@builder.table_sizes(@connection))

          result.to_hashes.map do |row|
            table_name = row["table_name"] || row["TABLE_NAME"]
            row_count = begin
              @connection.select_value("SELECT COUNT(*) FROM #{@connection.quote_table_name(table_name)}")
            rescue StandardError
              nil
            end

            total_mb = (row["total_mb"] || 0).to_f
            fragmented_mb = (row["fragmented_mb"] || 0).to_f

            {
              table: table_name,
              rows: row_count,
              engine: row["engine"] || row["ENGINE"],
              collation: row["table_collation"] || row["TABLE_COLLATION"],
              auto_increment: row["auto_increment"] || row["AUTO_INCREMENT"],
              updated_at: row["update_time"] || row["UPDATE_TIME"],
              data_mb: (row["data_mb"] || 0).to_f,
              index_mb: (row["index_mb"] || 0).to_f,
              total_mb: total_mb,
              fragmented_mb: fragmented_mb,
              needs_optimize: total_mb.positive? && fragmented_mb > (total_mb * 0.1),
            }
          end
        end
      end
    end
  end
end
