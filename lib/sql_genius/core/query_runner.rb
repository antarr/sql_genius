# frozen_string_literal: true

require "set"

module SqlGenius
  module Core
    # Runs SELECT queries against a Core::Connection with SQL validation,
    # row-limit application, dialect-appropriate timeout hints, and column
    # masking. Returns a Core::ExecutionResult on success or raises a
    # specific error class on failure.
    #
    # Timeout strategy by vendor:
    #   MySQL      — wraps SELECT with /*+ MAX_EXECUTION_TIME(ms) */ hint
    #   MariaDB    — prefixes SQL with SET STATEMENT max_statement_time=s FOR
    #   PostgreSQL — issues SET statement_timeout = ms before the query and
    #                resets it to 0 in an ensure block (the server enforces
    #                the cancel-on-timeout behaviour)
    #
    # Does NOT handle audit logging — the caller is responsible for
    # recording successful queries and errors using whatever logger it owns.
    class QueryRunner
      class Rejected < Core::Error; end
      class Timeout < Core::Error; end

      TIMEOUT_PATTERNS = [
        "max_statement_time",
        "max_execution_time",
        "Query execution was interrupted",
        "canceling statement due to statement timeout",
      ].freeze

      def initialize(connection, config)
        @connection = connection
        @config = config
      end

      def run(sql, row_limit:)
        validation_error = SqlValidator.validate(
          sql,
          blocked_tables: @config.blocked_tables,
          connection: @connection,
        )
        raise Rejected, validation_error if validation_error

        normalized = SqlValidator.normalize_identifier_quotes(sql, @connection)
        limited = SqlValidator.apply_row_limit(normalized, row_limit)

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = with_timeout do
          @connection.exec_query(apply_timeout_hint(limited))
        end
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)

        masked_rows = mask_rows(result)

        ExecutionResult.new(
          columns: result.columns,
          rows: masked_rows,
          execution_time_ms: duration_ms,
          truncated: masked_rows.length >= row_limit,
        )
      end

      private

      def apply_timeout_hint(sql)
        case vendor
        when :mariadb
          timeout_seconds = @config.query_timeout_ms / 1000
          "SET STATEMENT max_statement_time=#{timeout_seconds} FOR #{sql}"
        when :postgresql
          # PostgreSQL timeout is set out-of-band in with_timeout; the
          # query itself is sent unchanged.
          sql
        else
          sql.sub(/\bSELECT\b/i, "SELECT /*+ MAX_EXECUTION_TIME(#{@config.query_timeout_ms}) */")
        end
      end

      def with_timeout
        if vendor == :postgresql
          @connection.exec_query("SET statement_timeout = #{@config.query_timeout_ms}")
          begin
            yield
          ensure
            begin
              @connection.exec_query("SET statement_timeout = 0")
            rescue StandardError
              # If the session is already torn down we can't restore — that's fine.
            end
          end
        else
          yield
        end
      rescue StandardError => e
        raise Timeout, e.message if timeout_error?(e)

        raise
      end

      def vendor
        @connection.server_version.vendor
      end

      def mask_rows(result)
        mask_indices = result.columns.each_with_index.select do |name, _i|
          SqlValidator.masked_column?(name, @config.masked_column_patterns)
        end.map { |(_name, i)| i }.to_set

        return result.rows if mask_indices.empty?

        result.rows.map do |row|
          row.each_with_index.map { |value, i| mask_indices.include?(i) ? "[REDACTED]" : value }
        end
      end

      def timeout_error?(exception)
        msg = exception.message
        TIMEOUT_PATTERNS.any? { |pattern| msg.include?(pattern) }
      end
    end
  end
end
