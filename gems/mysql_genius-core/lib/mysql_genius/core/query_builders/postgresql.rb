# frozen_string_literal: true

module MysqlGenius
  module Core
    module QueryBuilders
      # PostgreSQL query builder. Produces SQL that returns the same
      # column-name contract as the MySQL builder so the Analysis classes
      # can stay dialect-agnostic after picking a builder.
      #
      # Caveats:
      # - query_stats and stats_snapshot require the pg_stat_statements
      #   extension. If it's not installed, the query will raise; the
      #   Analysis layer surfaces that failure to the caller exactly as
      #   it does on MySQL when performance_schema is disabled.
      # - "engine" / "table_collation" / "auto_increment" / "fragmented_mb"
      #   columns are emitted as NULL or 0 — PostgreSQL has no direct
      #   equivalents. The dashboard renders these gracefully.
      # - PostgreSQL "schema" and MySQL "database" are not equivalent;
      #   table_sizes filters to the current search_path's first schema
      #   (typically "public").
      module Postgresql
        QUERY_STATS_NOISE_FILTERS = <<~SQL
          query NOT ILIKE 'EXPLAIN%'
          AND query NOT ILIKE 'SHOW %'
          AND query NOT ILIKE 'SET %'
          AND query NOT ILIKE '%pg_stat_statements%'
          AND query NOT ILIKE '%pg_catalog%'
          AND query NOT ILIKE '%information_schema%'
        SQL

        extend self

        def table_sizes(_connection)
          <<~SQL
            SELECT
              c.relname AS table_name,
              NULL AS engine,
              NULL AS table_collation,
              NULL AS auto_increment,
              s.last_autoanalyze AS update_time,
              ROUND((pg_table_size(c.oid))::numeric / 1024 / 1024, 2) AS data_mb,
              ROUND((pg_indexes_size(c.oid))::numeric / 1024 / 1024, 2) AS index_mb,
              ROUND((pg_total_relation_size(c.oid))::numeric / 1024 / 1024, 2) AS total_mb,
              0.0 AS fragmented_mb
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
            WHERE c.relkind = 'r'
              AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
              AND n.nspname NOT LIKE 'pg_temp_%'
              AND n.nspname NOT LIKE 'pg_toast_temp_%'
            ORDER BY pg_total_relation_size(c.oid) DESC
          SQL
        end

        def query_stats(connection, order_clause:, limit:, include_digest:)
          _ = include_digest
          <<~SQL
            SELECT
              queryid::text AS "DIGEST",
              query AS "DIGEST_TEXT",
              calls AS calls,
              ROUND(total_exec_time::numeric, 1) AS total_time_ms,
              ROUND(mean_exec_time::numeric, 1) AS avg_time_ms,
              ROUND(max_exec_time::numeric, 1) AS max_time_ms,
              rows AS rows_examined,
              rows AS rows_sent,
              0 AS tmp_disk_tables,
              0 AS sort_rows,
              NULL AS "FIRST_SEEN",
              NULL AS "LAST_SEEN"
            FROM pg_stat_statements s
            JOIN pg_database d ON d.oid = s.dbid
            WHERE d.datname = #{connection.quote(connection.current_database)}
              AND query IS NOT NULL
              AND #{QUERY_STATS_NOISE_FILTERS.strip}
            ORDER BY #{order_clause}
            LIMIT #{limit}
          SQL
        end

        def query_stats_order_clause(sort)
          case sort
          when "total_time"    then "total_exec_time DESC"
          when "avg_time"      then "mean_exec_time DESC"
          when "calls"         then "calls DESC"
          when "rows_examined" then "rows DESC"
          else "total_exec_time DESC"
          end
        end

        def stats_snapshot(connection, limit:)
          <<~SQL
            SELECT
              query AS "DIGEST_TEXT",
              calls AS "COUNT_STAR",
              ROUND(total_exec_time::numeric, 1) AS total_time_ms
            FROM pg_stat_statements s
            JOIN pg_database d ON d.oid = s.dbid
            WHERE d.datname = #{connection.quote(connection.current_database)}
              AND query IS NOT NULL
              AND #{QUERY_STATS_NOISE_FILTERS.strip}
            ORDER BY total_exec_time DESC
            LIMIT #{limit}
          SQL
        end

        def unused_indexes(_connection)
          <<~SQL
            SELECT
              s.schemaname AS table_schema,
              s.relname AS table_name,
              s.indexrelname AS index_name,
              s.idx_scan AS reads,
              s.idx_tup_read AS writes,
              c.reltuples::bigint AS table_rows
            FROM pg_stat_user_indexes s
            JOIN pg_index i ON i.indexrelid = s.indexrelid
            JOIN pg_class c ON c.oid = s.relid
            WHERE NOT i.indisprimary
              AND NOT i.indisunique
              AND s.idx_scan = 0
              AND c.reltuples > 0
            ORDER BY s.idx_tup_read DESC, s.indexrelname ASC
          SQL
        end

        def drop_index_sql(table:, index_name:)
          _ = table
          %(DROP INDEX IF EXISTS "#{index_name.to_s.gsub('"', '""')}";)
        end

        def digest_column_available?(_connection)
          # pg_stat_statements always exposes queryid; treat as a stable digest.
          true
        end
      end
    end
  end
end
