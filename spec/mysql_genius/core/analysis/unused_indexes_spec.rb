# frozen_string_literal: true

RSpec.describe(MysqlGenius::Core::Analysis::UnusedIndexes) do
  subject(:analysis) { described_class.new(connection) }

  let(:connection) { MysqlGenius::Core::Connection::FakeAdapter.new }

  before do
    connection.stub_current_database("app_test")
  end

  describe "#call" do
    let(:columns) { ["table_schema", "table_name", "index_name", "reads", "writes", "table_rows", "size_bytes"] }

    it "returns an empty indexes list when performance_schema has no unused-index rows" do
      connection.stub_query(/performance_schema\.table_io_waits_summary_by_index_usage/, columns: columns, rows: [])

      result = analysis.call
      expect(result).to(be_a(described_class::Result))
      expect(result.indexes).to(eq([]))
      expect(result.stats_reset_at).to(be_nil)
      expect(result.min_scans).to(eq(0))
    end

    it "returns hashes with drop_sql and size_bytes for each unused index" do
      connection.stub_query(
        /performance_schema\.table_io_waits_summary_by_index_usage/,
        columns: columns,
        rows: [
          ["app_test", "users", "index_users_on_legacy_field", 0, 500, 10_000, nil],
          ["app_test", "posts", "idx_abandoned", 0, 120, 2_500, nil],
        ],
      )

      result = analysis.call.indexes

      expect(result.length).to(eq(2))
      expect(result[0]).to(include(
        table: "users",
        index_name: "index_users_on_legacy_field",
        reads: 0,
        writes: 500,
        table_rows: 10_000,
        size_bytes: nil,
        drop_sql: "ALTER TABLE `users` DROP INDEX `index_users_on_legacy_field`;",
      ))
      expect(result[1][:table]).to(eq("posts"))
      expect(result[1][:drop_sql]).to(eq("ALTER TABLE `posts` DROP INDEX `idx_abandoned`;"))
    end

    it "handles uppercase column names" do
      connection.stub_query(
        /performance_schema/,
        columns: ["TABLE_SCHEMA", "TABLE_NAME", "INDEX_NAME", "READS", "WRITES", "TABLE_ROWS", "SIZE_BYTES"],
        rows: [["app_test", "users", "index_users_on_email", 0, 100, 1000, nil]],
      )

      result = analysis.call.indexes
      expect(result.first[:table]).to(eq("users"))
      expect(result.first[:index_name]).to(eq("index_users_on_email"))
    end

    it "zero-fills missing numeric columns and leaves size_bytes nil when absent" do
      connection.stub_query(
        /performance_schema/,
        columns: columns,
        rows: [["app_test", "users", "index_users_on_email", nil, nil, nil, nil]],
      )

      first = analysis.call.indexes.first
      expect(first[:reads]).to(eq(0))
      expect(first[:writes]).to(eq(0))
      expect(first[:table_rows]).to(eq(0))
      expect(first[:size_bytes]).to(be_nil)
    end

    it "passes min_scans through to the builder's threshold (COUNT_READ <= N on MySQL)" do
      captured_sql = nil
      connection.stub_query(/performance_schema/, columns: columns, rows: [])
      allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
        captured_sql = sql
        original.call(sql, **kwargs)
      end)

      described_class.new(connection, min_scans: 25).call
      expect(captured_sql).to(match(/COUNT_READ <= 25/))
    end

    it "exposes the min_scans threshold on the Result for callers to echo back" do
      connection.stub_query(/performance_schema/, columns: columns, rows: [])

      result = described_class.new(connection, min_scans: 50).call
      expect(result.min_scans).to(eq(50))
    end

    context "with a PostgreSQL connection" do
      before { connection.stub_server_version("PostgreSQL 16.1") }

      it "queries pg_stat_user_indexes, surfaces size_bytes, and double-quotes the DROP statement" do
        connection.stub_query(
          /pg_stat_user_indexes/,
          columns: columns,
          rows: [["public", "users", "idx_users_on_legacy", 0, 500, 10_000, 8_192_000]],
        )
        connection.stub_query(/FROM pg_stat_database/, columns: ["stats_reset"], rows: [["2026-05-18T10:00:00Z"]])

        result = analysis.call
        expect(result.indexes.length).to(eq(1))
        expect(result.indexes.first).to(include(
          table: "users",
          index_name: "idx_users_on_legacy",
          reads: 0,
          writes: 500,
          table_rows: 10_000,
          size_bytes: 8_192_000,
          drop_sql: %(DROP INDEX IF EXISTS "idx_users_on_legacy";),
        ))
        expect(result.stats_reset_at.to_s).to(include("2026-05-18"))
      end

      it "passes min_scans through as idx_scan <= N" do
        captured_sql = nil
        connection.stub_query(/pg_stat_user_indexes/, columns: columns, rows: [])
        connection.stub_query(/FROM pg_stat_database/, columns: ["stats_reset"], rows: [[nil]])
        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql if sql.include?("pg_stat_user_indexes")
          original.call(sql, **kwargs)
        end)

        described_class.new(connection, min_scans: 10).call
        expect(captured_sql).to(match(/idx_scan <= 10/))
      end

      it "orders by index size descending (matches PgHero)" do
        captured_sql = nil
        connection.stub_query(/pg_stat_user_indexes/, columns: columns, rows: [])
        connection.stub_query(/FROM pg_stat_database/, columns: ["stats_reset"], rows: [[nil]])
        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql if sql.include?("pg_stat_user_indexes")
          original.call(sql, **kwargs)
        end)

        analysis.call
        expect(captured_sql).to(match(/ORDER BY pg_relation_size\(s\.indexrelid\) DESC/))
      end

      it "clamps a negative min_scans up to 0 (defensive against bad config)" do
        captured_sql = nil
        connection.stub_query(/pg_stat_user_indexes/, columns: columns, rows: [])
        connection.stub_query(/FROM pg_stat_database/, columns: ["stats_reset"], rows: [[nil]])
        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql if sql.include?("pg_stat_user_indexes")
          original.call(sql, **kwargs)
        end)

        described_class.new(connection, min_scans: -5).call
        expect(captured_sql).to(match(/idx_scan <= 0/))
      end
    end
  end
end
