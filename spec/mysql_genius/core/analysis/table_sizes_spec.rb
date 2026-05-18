# frozen_string_literal: true

RSpec.describe(MysqlGenius::Core::Analysis::TableSizes) do
  subject(:analysis) { described_class.new(connection) }

  let(:connection) { MysqlGenius::Core::Connection::FakeAdapter.new }

  before do
    connection.stub_current_database("app_test")
  end

  describe "#call" do
    it "returns an empty array when information_schema.tables has no BASE TABLE rows" do
      connection.stub_query(
        /FROM information_schema\.tables/i,
        columns: ["table_name", "engine", "table_collation", "auto_increment", "update_time", "data_mb", "index_mb", "total_mb", "fragmented_mb"],
        rows: [],
      )

      expect(analysis.call).to(eq([]))
    end

    context "with two BASE TABLE rows" do
      let(:two_row_result) do
        connection.stub_query(
          /FROM information_schema\.tables/i,
          columns: ["table_name", "engine", "table_collation", "auto_increment", "update_time", "data_mb", "index_mb", "total_mb", "fragmented_mb"],
          rows: [
            ["users", "InnoDB", "utf8mb4_0900_ai_ci", 42, "2026-04-10 12:00:00", 1.50, 0.50, 2.00, 0.00],
            ["posts", "InnoDB", "utf8mb4_0900_ai_ci", 100, "2026-04-10 12:05:00", 5.00, 2.00, 7.00, 0.10],
          ],
        )
        connection.stub_query(/SELECT COUNT.*FROM `users`/, columns: ["COUNT(*)"], rows: [[41]])
        connection.stub_query(/SELECT COUNT.*FROM `posts`/, columns: ["COUNT(*)"], rows: [[99]])
        analysis.call
      end

      it "returns one hash per BASE TABLE row" do
        expect(two_row_result.length).to(eq(2))
        expect(two_row_result[0]).to(include(
          table: "users",
          rows: 41,
          engine: "InnoDB",
          needs_optimize: false,
        ))
        expect(two_row_result[1]).to(include(table: "posts", rows: 99, needs_optimize: false))
      end

      it "includes full size metadata for each row" do
        expect(two_row_result[0]).to(include(
          collation: "utf8mb4_0900_ai_ci",
          auto_increment: 42,
          data_mb: 1.5,
          index_mb: 0.5,
          total_mb: 2.0,
          fragmented_mb: 0.0,
        ))
        expect(two_row_result[1]).to(include(total_mb: 7.0, fragmented_mb: 0.1))
      end
    end

    it "sets needs_optimize=true when fragmented_mb exceeds 10% of total_mb" do
      connection.stub_query(
        /FROM information_schema\.tables/i,
        columns: ["table_name", "engine", "table_collation", "auto_increment", "update_time", "data_mb", "index_mb", "total_mb", "fragmented_mb"],
        rows: [["users", "InnoDB", "utf8mb4", 1, nil, 10.0, 5.0, 15.0, 2.0]],
      )
      connection.stub_query(/SELECT COUNT.*FROM `users`/, columns: ["COUNT(*)"], rows: [[100]])

      expect(analysis.call.first[:needs_optimize]).to(be(true))
    end

    it "falls back to nil row count when the COUNT(*) query raises" do
      connection.stub_query(
        /FROM information_schema\.tables/i,
        columns: ["table_name", "engine", "table_collation", "auto_increment", "update_time", "data_mb", "index_mb", "total_mb", "fragmented_mb"],
        rows: [["broken", "InnoDB", "utf8mb4", 1, nil, 1.0, 0.0, 1.0, 0.0]],
      )
      connection.stub_query(/SELECT COUNT.*FROM `broken`/, raises: StandardError.new("no such table"))

      result = analysis.call
      expect(result.first[:rows]).to(be_nil)
    end

    it "handles uppercase column names (MariaDB compatibility)" do
      connection.stub_query(
        /FROM information_schema\.tables/i,
        columns: ["TABLE_NAME", "ENGINE", "TABLE_COLLATION", "AUTO_INCREMENT", "UPDATE_TIME", "data_mb", "index_mb", "total_mb", "fragmented_mb"],
        rows: [["users", "InnoDB", "utf8mb4", 1, nil, 1.0, 0.0, 1.0, 0.0]],
      )
      connection.stub_query(/SELECT COUNT.*FROM `users`/, columns: ["COUNT(*)"], rows: [[1]])

      result = analysis.call
      expect(result.first[:table]).to(eq("users"))
      expect(result.first[:engine]).to(eq("InnoDB"))
      expect(result.first[:collation]).to(eq("utf8mb4"))
    end

    it "coerces nil size columns to 0.0 (e.g., MEMORY engine tables)" do
      connection.stub_query(
        /FROM information_schema\.tables/i,
        columns: ["table_name", "engine", "table_collation", "auto_increment", "update_time", "data_mb", "index_mb", "total_mb", "fragmented_mb"],
        rows: [["memory_tbl", "MEMORY", "utf8mb4", nil, nil, nil, nil, nil, nil]],
      )
      connection.stub_query(/SELECT COUNT.*FROM `memory_tbl`/, columns: ["COUNT(*)"], rows: [[0]])

      row = analysis.call.first

      expect(row[:data_mb]).to(eq(0.0))
      expect(row[:index_mb]).to(eq(0.0))
      expect(row[:total_mb]).to(eq(0.0))
      expect(row[:fragmented_mb]).to(eq(0.0))
      expect(row[:needs_optimize]).to(be(false))
    end

    it "does not flag needs_optimize when fragmented_mb is exactly at the 10% boundary" do
      connection.stub_query(
        /FROM information_schema\.tables/i,
        columns: ["table_name", "engine", "table_collation", "auto_increment", "update_time", "data_mb", "index_mb", "total_mb", "fragmented_mb"],
        rows: [["boundary_tbl", "InnoDB", "utf8mb4", 1, nil, 9.0, 0.0, 10.0, 1.0]],
      )
      connection.stub_query(/SELECT COUNT.*FROM `boundary_tbl`/, columns: ["COUNT(*)"], rows: [[100]])

      expect(analysis.call.first[:needs_optimize]).to(be(false))
    end

    context "with a PostgreSQL connection" do
      before { connection.stub_server_version("PostgreSQL 16.1 on x86_64-pc-linux-gnu") }

      it "queries pg_class instead of information_schema.tables" do
        captured = nil
        connection.stub_query(
          /pg_class/i,
          columns: ["table_name", "engine", "table_collation", "auto_increment", "update_time", "data_mb", "index_mb", "total_mb", "fragmented_mb"],
          rows: [["users", nil, nil, nil, nil, 1.5, 0.5, 2.0, 0.0]],
        )
        connection.stub_query(/SELECT COUNT.*FROM "users"/, columns: ["count"], rows: [[42]])

        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured = sql if sql.match?(/FROM pg_class|FROM information_schema/i)
          original.call(sql, **kwargs)
        end)

        result = analysis.call
        expect(captured).to(include("pg_class"))
        expect(captured).not_to(include("information_schema.tables"))
        expect(result.first).to(include(table: "users", rows: 42, total_mb: 2.0))
      end

      it "uses double-quoted identifiers for the COUNT(*) probe" do
        captured_count_sql = nil
        connection.stub_query(
          /pg_class/i,
          columns: ["table_name", "engine", "table_collation", "auto_increment", "update_time", "data_mb", "index_mb", "total_mb", "fragmented_mb"],
          rows: [["orders", nil, nil, nil, nil, 3.0, 1.0, 4.0, 0.0]],
        )
        connection.stub_query(/SELECT COUNT/i, columns: ["count"], rows: [[1]])

        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_count_sql = sql if sql.start_with?("SELECT COUNT")
          original.call(sql, **kwargs)
        end)
        allow(connection).to(receive(:select_value).and_wrap_original do |original, sql|
          captured_count_sql = sql if sql.start_with?("SELECT COUNT")
          original.call(sql)
        end)

        analysis.call
        expect(captured_count_sql).to(include(%("orders")))
      end
    end
  end
end
