# frozen_string_literal: true

module MysqlGenius
  module Core
    module QueryBuilders
      # MySQL / MariaDB query builder. Contains all SQL previously embedded
      # in the Analysis classes prior to PostgreSQL support being added.
      module Mysql
        QUERY_STATS_NOISE_FILTERS = <<~SQL
          DIGEST_TEXT NOT LIKE 'EXPLAIN%'
          AND DIGEST_TEXT NOT LIKE '%`information_schema`%'
          AND DIGEST_TEXT NOT LIKE '%`performance_schema`%'
          AND DIGEST_TEXT NOT LIKE '%information_schema.%'
          AND DIGEST_TEXT NOT LIKE '%performance_schema.%'
          AND DIGEST_TEXT NOT LIKE 'SHOW %'
          AND DIGEST_TEXT NOT LIKE 'SET STATEMENT %'
          AND DIGEST_TEXT NOT LIKE 'SELECT VERSION ( )%'
          AND DIGEST_TEXT NOT LIKE 'SELECT @@%'
        SQL

        extend self

        def table_sizes(connection)
          <<~SQL
            SELECT
              table_name,
              engine,
              table_collation,
              auto_increment,
              update_time,
              ROUND(data_length / 1024 / 1024, 2) AS data_mb,
              ROUND(index_length / 1024 / 1024, 2) AS index_mb,
              ROUND((data_length + index_length) / 1024 / 1024, 2) AS total_mb,
              ROUND(data_free / 1024 / 1024, 2) AS fragmented_mb
            FROM information_schema.tables
            WHERE table_schema = #{connection.quote(connection.current_database)}
              AND table_type = 'BASE TABLE'
            ORDER BY (data_length + index_length) DESC
          SQL
        end

        def query_stats(connection, order_clause:, limit:, include_digest:)
          digest_col = include_digest ? "DIGEST," : ""
          <<~SQL
            SELECT
              #{digest_col}
              DIGEST_TEXT,
              COUNT_STAR AS calls,
              ROUND(SUM_TIMER_WAIT / 1000000000, 1) AS total_time_ms,
              ROUND(AVG_TIMER_WAIT / 1000000000, 1) AS avg_time_ms,
              ROUND(MAX_TIMER_WAIT / 1000000000, 1) AS max_time_ms,
              SUM_ROWS_EXAMINED AS rows_examined,
              SUM_ROWS_SENT AS rows_sent,
              SUM_CREATED_TMP_DISK_TABLES AS tmp_disk_tables,
              SUM_SORT_ROWS AS sort_rows,
              FIRST_SEEN,
              LAST_SEEN
            FROM performance_schema.events_statements_summary_by_digest
            WHERE SCHEMA_NAME = #{connection.quote(connection.current_database)}
              AND DIGEST_TEXT IS NOT NULL
              AND #{QUERY_STATS_NOISE_FILTERS.strip}
            ORDER BY #{order_clause}
            LIMIT #{limit}
          SQL
        end

        def query_stats_order_clause(sort)
          case sort
          when "total_time"    then "SUM_TIMER_WAIT DESC"
          when "avg_time"      then "AVG_TIMER_WAIT DESC"
          when "calls"         then "COUNT_STAR DESC"
          when "rows_examined" then "SUM_ROWS_EXAMINED DESC"
          else "SUM_TIMER_WAIT DESC"
          end
        end

        def stats_snapshot(connection, limit:)
          <<~SQL
            SELECT
              DIGEST_TEXT,
              COUNT_STAR,
              ROUND(SUM_TIMER_WAIT / 1000000000, 1) AS total_time_ms
            FROM performance_schema.events_statements_summary_by_digest
            WHERE SCHEMA_NAME = #{connection.quote(connection.current_database)}
              AND DIGEST_TEXT IS NOT NULL
              AND #{QUERY_STATS_NOISE_FILTERS.strip}
            ORDER BY SUM_TIMER_WAIT DESC
            LIMIT #{limit}
          SQL
        end

        def unused_indexes(connection, min_scans: 0)
          threshold = [min_scans.to_i, 0].max
          <<~SQL
            SELECT
              s.OBJECT_SCHEMA AS table_schema,
              s.OBJECT_NAME AS table_name,
              s.INDEX_NAME AS index_name,
              s.COUNT_READ AS `reads`,
              s.COUNT_WRITE AS `writes`,
              t.TABLE_ROWS AS table_rows,
              NULL AS size_bytes
            FROM performance_schema.table_io_waits_summary_by_index_usage s
            JOIN information_schema.tables t
              ON t.TABLE_SCHEMA = s.OBJECT_SCHEMA AND t.TABLE_NAME = s.OBJECT_NAME
            WHERE s.OBJECT_SCHEMA = #{connection.quote(connection.current_database)}
              AND s.INDEX_NAME IS NOT NULL
              AND s.INDEX_NAME != 'PRIMARY'
              AND s.COUNT_READ <= #{threshold}
            ORDER BY s.COUNT_WRITE DESC
          SQL
        end

        # MySQL's table_io_waits counters track since server start with no
        # cheap way to surface that timestamp at query time, so we return nil
        # and let the dashboard fall back to "since server restart" wording.
        def stats_reset_at(_connection)
          nil
        end

        def drop_index_sql(table:, index_name:)
          "ALTER TABLE `#{table}` DROP INDEX `#{index_name}`;"
        end

        def query_history(connection, digest:)
          quoted_digest = connection.quote(digest)
          quoted_db = connection.quote(connection.current_database)
          <<~SQL
            SELECT DIGEST_TEXT,
                   COUNT_STAR AS calls,
                   ROUND(SUM_TIMER_WAIT / 1000000000.0, 2) AS total_time_ms,
                   ROUND(AVG_TIMER_WAIT / 1000000000.0, 2) AS avg_time_ms,
                   ROUND(MAX_TIMER_WAIT / 1000000000.0, 2) AS max_time_ms,
                   SUM_ROWS_EXAMINED AS rows_examined,
                   SUM_ROWS_SENT AS rows_sent,
                   FIRST_SEEN,
                   LAST_SEEN
            FROM performance_schema.events_statements_summary_by_digest
            WHERE DIGEST = #{quoted_digest}
              AND SCHEMA_NAME = #{quoted_db}
            LIMIT 1
          SQL
        end

        def digest_text_lookup(connection, digest:)
          quoted_digest = connection.quote(digest)
          <<~SQL
            SELECT DIGEST_TEXT
            FROM performance_schema.events_statements_summary_by_digest
            WHERE DIGEST = #{quoted_digest}
            LIMIT 1
          SQL
        end

        def digest_column_available?(connection)
          result = connection.exec_query(
            "SELECT COLUMN_NAME FROM information_schema.COLUMNS " \
              "WHERE TABLE_SCHEMA = 'performance_schema' " \
              "AND TABLE_NAME = 'events_statements_summary_by_digest' " \
              "AND COLUMN_NAME = 'DIGEST'",
          )
          !result.rows.empty?
        rescue StandardError
          false
        end
      end
    end
  end
end
