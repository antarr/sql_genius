# frozen_string_literal: true

RSpec.describe(SqlGenius::Core::Analysis::QueryStats) do
  subject(:analysis) { described_class.new(connection) }

  let(:connection) { SqlGenius::Core::Connection::FakeAdapter.new }

  before do
    connection.stub_current_database("app_test")
  end

  describe "#call" do
    let(:columns) do
      [
        "DIGEST",
        "DIGEST_TEXT",
        "calls",
        "total_time_ms",
        "avg_time_ms",
        "max_time_ms",
        "rows_examined",
        "rows_sent",
        "tmp_disk_tables",
        "sort_rows",
        "FIRST_SEEN",
        "LAST_SEEN",
      ]
    end

    it "returns an empty array when performance_schema has no digest rows" do
      connection.stub_query(/performance_schema\.events_statements_summary_by_digest/, columns: columns, rows: [])

      expect(analysis.call).to(eq([]))
    end

    it "transforms digest rows into hashes keyed by symbol" do
      connection.stub_query(
        /performance_schema\.events_statements_summary_by_digest/,
        columns: columns,
        rows: [
          ["abc123def456", "SELECT * FROM users WHERE id = ?", 100, 500.5, 5.005, 42.1, 1000, 100, 0, 0, "2026-04-01T00:00:00Z", "2026-04-10T00:00:00Z"],
        ],
      )

      result = analysis.call

      expect(result.length).to(eq(1))
      expect(result.first).to(include(
        digest: "abc123def456",
        sql: "SELECT * FROM users WHERE id = ?",
        calls: 100,
        total_time_ms: 500.5,
        avg_time_ms: 5.005,
        max_time_ms: 42.1,
        rows_examined: 1000,
        rows_sent: 100,
        rows_ratio: 10.0,
      ))
    end

    it "computes rows_ratio as 0 when rows_sent is 0" do
      connection.stub_query(
        /performance_schema\.events_statements_summary_by_digest/,
        columns: columns,
        rows: [["deadbeef", "SET NAMES ?", 50, 10.0, 0.2, 1.0, 0, 0, 0, 0, nil, nil]],
      )

      expect(analysis.call.first[:rows_ratio]).to(eq(0))
    end

    it "defaults to sorting by SUM_TIMER_WAIT DESC (sort=total_time)" do
      captured_sql = nil
      connection.stub_query(/performance_schema\.events_statements_summary_by_digest/, columns: columns, rows: [])
      allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
        captured_sql = sql
        original.call(sql, **kwargs)
      end)

      analysis.call(sort: "total_time")
      expect(captured_sql).to(match(/ORDER BY SUM_TIMER_WAIT DESC/))
    end

    it "supports sort=avg_time" do
      captured_sql = nil
      connection.stub_query(/performance_schema/, columns: columns, rows: [])
      allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
        captured_sql = sql
        original.call(sql, **kwargs)
      end)

      analysis.call(sort: "avg_time")
      expect(captured_sql).to(match(/ORDER BY AVG_TIMER_WAIT DESC/))
    end

    it "supports sort=calls" do
      captured_sql = nil
      connection.stub_query(/performance_schema/, columns: columns, rows: [])
      allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
        captured_sql = sql
        original.call(sql, **kwargs)
      end)

      analysis.call(sort: "calls")
      expect(captured_sql).to(match(/ORDER BY COUNT_STAR DESC/))
    end

    it "supports sort=rows_examined" do
      captured_sql = nil
      connection.stub_query(/performance_schema/, columns: columns, rows: [])
      allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
        captured_sql = sql
        original.call(sql, **kwargs)
      end)

      analysis.call(sort: "rows_examined")
      expect(captured_sql).to(match(/ORDER BY SUM_ROWS_EXAMINED DESC/))
    end

    it "rejects invalid sort values and falls back to total_time" do
      captured_sql = nil
      connection.stub_query(/performance_schema/, columns: columns, rows: [])
      allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
        captured_sql = sql
        original.call(sql, **kwargs)
      end)

      analysis.call(sort: "' OR 1=1 --")
      expect(captured_sql).to(match(/ORDER BY SUM_TIMER_WAIT DESC/))
    end

    it "clamps limit to a max of 50" do
      captured_sql = nil
      connection.stub_query(/performance_schema/, columns: columns, rows: [])
      allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
        captured_sql = sql
        original.call(sql, **kwargs)
      end)

      analysis.call(limit: 99)
      expect(captured_sql).to(match(/LIMIT 50/))
    end

    it "accepts a limit smaller than the max" do
      captured_sql = nil
      connection.stub_query(/performance_schema/, columns: columns, rows: [])
      allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
        captured_sql = sql
        original.call(sql, **kwargs)
      end)

      analysis.call(limit: 5)
      expect(captured_sql).to(match(/LIMIT 5/))
    end

    it "truncates long digest text to 500 characters" do
      long_digest = "SELECT * FROM users WHERE " + ("foo = 1 AND " * 100)
      connection.stub_query(
        /performance_schema/,
        columns: columns,
        rows: [["abc999", long_digest, 1, 1.0, 1.0, 1.0, 1, 1, 0, 0, nil, nil]],
      )

      result = analysis.call
      expect(result.first[:sql].length).to(be <= 500)
    end

    context "with a PostgreSQL connection" do
      before { connection.stub_server_version("PostgreSQL 16.1 on x86_64-pc-linux-gnu") }

      let(:pg_columns) do
        [
          "DIGEST",
          "DIGEST_TEXT",
          "calls",
          "total_time_ms",
          "avg_time_ms",
          "max_time_ms",
          "rows_examined",
          "rows_sent",
          "tmp_disk_tables",
          "sort_rows",
          "FIRST_SEEN",
          "LAST_SEEN",
        ]
      end

      it "queries pg_stat_statements" do
        captured_sql = nil
        connection.stub_query(/pg_stat_statements/, columns: pg_columns, rows: [])

        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql
          original.call(sql, **kwargs)
        end)

        analysis.call
        expect(captured_sql).to(include("pg_stat_statements"))
        expect(captured_sql).not_to(include("performance_schema"))
      end

      it "transforms pg_stat_statements rows into the same output schema as MySQL" do
        connection.stub_query(
          /pg_stat_statements/,
          columns: pg_columns,
          rows: [["9876543210", "SELECT * FROM users WHERE id = $1", 42, 100.5, 2.4, 10.1, 200, 42, 0, 0, nil, nil]],
        )

        result = analysis.call

        expect(result.length).to(eq(1))
        expect(result.first).to(include(
          digest: "9876543210",
          sql: "SELECT * FROM users WHERE id = $1",
          calls: 42,
          total_time_ms: 100.5,
          avg_time_ms: 2.4,
          max_time_ms: 10.1,
          rows_examined: 200,
          rows_sent: 42,
        ))
      end

      it "maps sort=total_time to total_exec_time DESC" do
        captured_sql = nil
        connection.stub_query(/pg_stat_statements/, columns: pg_columns, rows: [])

        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql
          original.call(sql, **kwargs)
        end)

        analysis.call(sort: "total_time")
        expect(captured_sql).to(match(/ORDER BY total_exec_time DESC/))
      end

      it "maps sort=avg_time to mean_exec_time DESC" do
        captured_sql = nil
        connection.stub_query(/pg_stat_statements/, columns: pg_columns, rows: [])

        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql
          original.call(sql, **kwargs)
        end)

        analysis.call(sort: "avg_time")
        expect(captured_sql).to(match(/ORDER BY mean_exec_time DESC/))
      end
    end
  end
end
