# frozen_string_literal: true

module MysqlGenius
  module Core
    module Analysis
      # Dashboard snapshot of server state. Dispatches to a dialect-specific
      # implementation that produces a uniform nested hash with four
      # top-level sections: server, connections, innodb, queries.
      #
      # On PostgreSQL the `innodb` section is populated with the closest
      # equivalents (shared_buffers as buffer pool size, blks_hit/blks_read
      # ratio as buffer pool hit rate). Lock-related fields fall back to 0
      # since there is no direct equivalent of InnoDB row lock waits.
      class ServerOverview
        def initialize(connection)
          @connection = connection
        end

        def call
          impl_for(@connection).call
        end

        private

        def impl_for(connection)
          if connection.server_version.postgresql?
            Postgresql.new(connection)
          else
            Mysql.new(connection)
          end
        end

        # MySQL / MariaDB implementation. Combines SHOW GLOBAL STATUS, SHOW
        # GLOBAL VARIABLES, and SELECT VERSION() into the dashboard hash.
        class Mysql
          def initialize(connection)
            @connection = connection
          end

          def call
            status = load_status
            vars = load_variables
            version = @connection.select_value("SELECT VERSION()")

            uptime_seconds = status["Uptime"].to_i
            {
              server: server_block(version, uptime_seconds),
              connections: connections_block(status, vars),
              innodb: innodb_block(status, vars),
              queries: queries_block(status, uptime_seconds),
            }
          end

          private

          def load_status
            result = @connection.exec_query("SHOW GLOBAL STATUS")
            result.to_hashes.each_with_object({}) do |row, acc|
              name = (row["Variable_name"] || row["variable_name"]).to_s
              value = (row["Value"] || row["value"]).to_s
              acc[name] = value
            end
          end

          def load_variables
            result = @connection.exec_query("SHOW GLOBAL VARIABLES")
            result.to_hashes.each_with_object({}) do |row, acc|
              name = (row["Variable_name"] || row["variable_name"]).to_s
              value = (row["Value"] || row["value"]).to_s
              acc[name] = value
            end
          end

          def server_block(version, uptime_seconds)
            days = uptime_seconds / 86_400
            hours = (uptime_seconds % 86_400) / 3600
            minutes = (uptime_seconds % 3600) / 60

            {
              version: version,
              uptime: "#{days}d #{hours}h #{minutes}m",
              uptime_seconds: uptime_seconds,
            }
          end

          def connections_block(status, vars)
            max_conn = vars["max_connections"].to_i
            current_conn = status["Threads_connected"].to_i
            usage_pct = max_conn.positive? ? ((current_conn.to_f / max_conn) * 100).round(1) : 0

            {
              max: max_conn,
              current: current_conn,
              usage_pct: usage_pct,
              threads_running: status["Threads_running"].to_i,
              threads_cached: status["Threads_cached"].to_i,
              threads_created: status["Threads_created"].to_i,
              aborted_connects: status["Aborted_connects"].to_i,
              aborted_clients: status["Aborted_clients"].to_i,
              max_used: status["Max_used_connections"].to_i,
            }
          end

          def innodb_block(status, vars)
            buffer_pool_bytes = vars["innodb_buffer_pool_size"].to_i
            buffer_pool_mb = (buffer_pool_bytes / 1024.0 / 1024.0).round(1)

            reads = status["Innodb_buffer_pool_read_requests"].to_f
            disk_reads = status["Innodb_buffer_pool_reads"].to_f
            hit_rate = reads.positive? ? (((reads - disk_reads) / reads) * 100).round(2) : 0

            {
              buffer_pool_mb: buffer_pool_mb,
              buffer_pool_hit_rate: hit_rate,
              buffer_pool_pages_dirty: status["Innodb_buffer_pool_pages_dirty"].to_i,
              buffer_pool_pages_free: status["Innodb_buffer_pool_pages_free"].to_i,
              buffer_pool_pages_total: status["Innodb_buffer_pool_pages_total"].to_i,
              row_lock_waits: status["Innodb_row_lock_waits"].to_i,
              row_lock_time_ms: status["Innodb_row_lock_time"].to_f.round(0),
            }
          end

          def queries_block(status, uptime_seconds)
            tmp_tables = status["Created_tmp_tables"].to_i
            tmp_disk_tables = status["Created_tmp_disk_tables"].to_i
            tmp_disk_pct = tmp_tables.positive? ? ((tmp_disk_tables.to_f / tmp_tables) * 100).round(1) : 0

            questions = status["Questions"].to_i
            qps = uptime_seconds.positive? ? (questions.to_f / uptime_seconds).round(1) : 0

            {
              questions: questions,
              qps: qps,
              slow_queries: status["Slow_queries"].to_i,
              tmp_tables: tmp_tables,
              tmp_disk_tables: tmp_disk_tables,
              tmp_disk_pct: tmp_disk_pct,
              select_full_join: status["Select_full_join"].to_i,
              sort_merge_passes: status["Sort_merge_passes"].to_i,
            }
          end
        end

        # PostgreSQL implementation. Reads connection/database stats from
        # pg_stat_activity and pg_stat_database; reads tunable settings via
        # pg_settings; populates the `innodb` block with shared_buffers and
        # the buffer cache hit rate so the existing UI continues to render.
        class Postgresql
          def initialize(connection)
            @connection = connection
          end

          def call
            version = @connection.select_value("SELECT version()").to_s
            uptime_seconds = @connection.select_value(
              "SELECT EXTRACT(EPOCH FROM (now() - pg_postmaster_start_time()))::bigint",
            ).to_i

            {
              server: server_block(version, uptime_seconds),
              connections: connections_block,
              innodb: innodb_block,
              queries: queries_block(uptime_seconds),
            }
          end

          private

          def server_block(version, uptime_seconds)
            days = uptime_seconds / 86_400
            hours = (uptime_seconds % 86_400) / 3600
            minutes = (uptime_seconds % 3600) / 60

            {
              version: version,
              uptime: "#{days}d #{hours}h #{minutes}m",
              uptime_seconds: uptime_seconds,
            }
          end

          def connections_block
            max_conn = setting_int("max_connections")
            current_conn = @connection.select_value("SELECT count(*) FROM pg_stat_activity").to_i
            running = @connection.select_value(
              "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'",
            ).to_i
            usage_pct = max_conn.positive? ? ((current_conn.to_f / max_conn) * 100).round(1) : 0

            db_stats = current_db_stats
            {
              max: max_conn,
              current: current_conn,
              usage_pct: usage_pct,
              threads_running: running,
              threads_cached: 0,
              threads_created: 0,
              aborted_connects: 0,
              aborted_clients: db_stats[:xact_rollback],
              max_used: 0,
            }
          end

          def innodb_block
            buffer_pool_bytes = setting_bytes("shared_buffers")
            buffer_pool_mb = (buffer_pool_bytes / 1024.0 / 1024.0).round(1)

            db_stats = current_db_stats
            reads = db_stats[:blks_hit].to_f + db_stats[:blks_read].to_f
            hit_rate = reads.positive? ? ((db_stats[:blks_hit].to_f / reads) * 100).round(2) : 0

            {
              buffer_pool_mb: buffer_pool_mb,
              buffer_pool_hit_rate: hit_rate,
              buffer_pool_pages_dirty: 0,
              buffer_pool_pages_free: 0,
              buffer_pool_pages_total: 0,
              row_lock_waits: db_stats[:deadlocks],
              row_lock_time_ms: 0,
            }
          end

          def queries_block(uptime_seconds)
            db_stats = current_db_stats
            questions = db_stats[:xact_commit].to_i + db_stats[:xact_rollback].to_i
            qps = uptime_seconds.positive? ? (questions.to_f / uptime_seconds).round(1) : 0
            tmp_tables = db_stats[:temp_files]
            tmp_disk_pct = tmp_tables.positive? ? 100.0 : 0

            {
              questions: questions,
              qps: qps,
              slow_queries: 0,
              tmp_tables: tmp_tables,
              tmp_disk_tables: tmp_tables,
              tmp_disk_pct: tmp_disk_pct,
              select_full_join: 0,
              sort_merge_passes: 0,
            }
          end

          def current_db_stats
            @current_db_stats ||= begin
              result = @connection.exec_query(<<~SQL)
                SELECT
                  COALESCE(xact_commit, 0) AS xact_commit,
                  COALESCE(xact_rollback, 0) AS xact_rollback,
                  COALESCE(blks_read, 0) AS blks_read,
                  COALESCE(blks_hit, 0) AS blks_hit,
                  COALESCE(temp_files, 0) AS temp_files,
                  COALESCE(deadlocks, 0) AS deadlocks
                FROM pg_stat_database
                WHERE datname = #{@connection.quote(@connection.current_database)}
              SQL
              row = result.to_hashes.first || {}
              {
                xact_commit: row["xact_commit"].to_i,
                xact_rollback: row["xact_rollback"].to_i,
                blks_read: row["blks_read"].to_i,
                blks_hit: row["blks_hit"].to_i,
                temp_files: row["temp_files"].to_i,
                deadlocks: row["deadlocks"].to_i,
              }
            end
          end

          def setting_int(name)
            @connection.select_value(
              "SELECT setting FROM pg_settings WHERE name = #{@connection.quote(name)}",
            ).to_i
          end

          # shared_buffers / work_mem etc. report via current_setting() with
          # their configured unit suffix (e.g. "128MB"). pg_size_bytes()
          # resolves that to a raw byte count. Available since PG 9.6.
          def setting_bytes(name)
            @connection.select_value(
              "SELECT pg_size_bytes(current_setting(#{@connection.quote(name)}))",
            ).to_i
          rescue StandardError
            0
          end
        end
      end
    end
  end
end
