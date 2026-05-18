# frozen_string_literal: true

RSpec.describe(MysqlGenius::Core::Analysis::QueryHistory) do
  subject(:analysis) { described_class.new(connection) }

  let(:connection) { MysqlGenius::Core::Connection::FakeAdapter.new }

  before do
    connection.stub_current_database("app_test")
  end

  describe "#call" do
    it "returns nil when the digest is empty" do
      expect(analysis.call("")).to(be_nil)
      expect(analysis.call(nil)).to(be_nil)
    end

    it "returns nil when no row matches the digest" do
      connection.stub_query(
        /events_statements_summary_by_digest/,
        columns: [
          "DIGEST_TEXT",
          "calls",
          "total_time_ms",
          "avg_time_ms",
          "max_time_ms",
          "rows_examined",
          "rows_sent",
          "FIRST_SEEN",
          "LAST_SEEN",
        ],
        rows: [],
      )

      expect(analysis.call("abc123")).to(be_nil)
    end

    it "returns a digest hash for a MySQL row" do
      connection.stub_query(
        /events_statements_summary_by_digest/,
        columns: [
          "DIGEST_TEXT",
          "calls",
          "total_time_ms",
          "avg_time_ms",
          "max_time_ms",
          "rows_examined",
          "rows_sent",
          "FIRST_SEEN",
          "LAST_SEEN",
        ],
        rows: [["SELECT * FROM users WHERE id = ?", 42, 100.5, 2.4, 10.1, 200, 42, "2026-01-01", "2026-04-10"]],
      )

      result = analysis.call("abc123")
      expect(result).to(include(
        sql: "SELECT * FROM users WHERE id = ?",
        calls: 42,
        total_time_ms: 100.5,
        avg_time_ms: 2.4,
        max_time_ms: 10.1,
      ))
    end

    context "with a PostgreSQL connection" do
      before { connection.stub_server_version("PostgreSQL 16.1") }

      it "queries pg_stat_statements" do
        captured_sql = nil
        connection.stub_query(
          /pg_stat_statements/,
          columns: [
            "DIGEST_TEXT",
            "calls",
            "total_time_ms",
            "avg_time_ms",
            "max_time_ms",
            "rows_examined",
            "rows_sent",
            "FIRST_SEEN",
            "LAST_SEEN",
          ],
          rows: [["SELECT * FROM users WHERE id = $1", 7, 50.0, 7.1, 12.0, 7, 7, nil, nil]],
        )
        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql
          original.call(sql, **kwargs)
        end)

        result = analysis.call("9876543210")
        expect(captured_sql).to(include("pg_stat_statements"))
        expect(captured_sql).not_to(include("performance_schema"))
        expect(result[:sql]).to(eq("SELECT * FROM users WHERE id = $1"))
      end
    end
  end

  describe "#digest_text_for" do
    it "returns the DIGEST_TEXT for a matching row" do
      connection.stub_query(
        /events_statements_summary_by_digest/,
        columns: ["DIGEST_TEXT"],
        rows: [["SELECT * FROM users"]],
      )

      expect(analysis.digest_text_for("abc")).to(eq("SELECT * FROM users"))
    end

    context "with a PostgreSQL connection" do
      before { connection.stub_server_version("PostgreSQL 16.1") }

      it "queries pg_stat_statements with queryid" do
        captured_sql = nil
        connection.stub_query(
          /pg_stat_statements/,
          columns: ["query"],
          rows: [["SELECT 1"]],
        )
        allow(connection).to(receive(:select_value).and_wrap_original do |original, sql|
          captured_sql = sql
          original.call(sql)
        end)

        analysis.digest_text_for("123")
        expect(captured_sql).to(include("queryid::text"))
        expect(captured_sql).to(include("pg_stat_statements"))
      end
    end
  end
end
