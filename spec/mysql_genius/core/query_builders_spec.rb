# frozen_string_literal: true

RSpec.describe(MysqlGenius::Core::QueryBuilders) do
  let(:connection) { MysqlGenius::Core::Connection::FakeAdapter.new }

  describe ".for" do
    it "returns the Mysql builder for a MySQL connection" do
      connection.stub_server_version("8.0.35")

      expect(described_class.for(connection)).to(be(MysqlGenius::Core::QueryBuilders::Mysql))
    end

    it "returns the Mysql builder for a MariaDB connection" do
      connection.stub_server_version("10.11.5-MariaDB")

      expect(described_class.for(connection)).to(be(MysqlGenius::Core::QueryBuilders::Mysql))
    end

    it "returns the Postgresql builder for a PostgreSQL connection" do
      connection.stub_server_version("PostgreSQL 16.1")

      expect(described_class.for(connection)).to(be(MysqlGenius::Core::QueryBuilders::Postgresql))
    end
  end

  describe MysqlGenius::Core::QueryBuilders::Postgresql do
    let(:connection) do
      conn = MysqlGenius::Core::Connection::FakeAdapter.new
      conn.stub_current_database("app_test")
      conn.stub_server_version("PostgreSQL 16.1")
      conn
    end

    describe ".table_sizes" do
      it "selects from pg_class joined with pg_namespace" do
        sql = described_class.table_sizes(connection)
        expect(sql).to(include("FROM pg_class"))
        expect(sql).to(include("pg_namespace"))
        expect(sql).to(include("pg_total_relation_size"))
      end

      it "filters out system schemas" do
        sql = described_class.table_sizes(connection)
        expect(sql).to(include("pg_catalog"))
        expect(sql).to(include("information_schema"))
        expect(sql).to(include("pg_toast"))
      end
    end

    describe ".query_stats" do
      it "selects from pg_stat_statements joined with pg_database" do
        sql = described_class.query_stats(connection, order_clause: "total_exec_time DESC", limit: 25, include_digest: true)
        expect(sql).to(include("pg_stat_statements"))
        expect(sql).to(include("pg_database"))
        expect(sql).to(include("LIMIT 25"))
      end
    end

    describe ".query_stats_order_clause" do
      it "maps each known sort to the corresponding PostgreSQL column" do
        expect(described_class.query_stats_order_clause("total_time")).to(eq("total_exec_time DESC"))
        expect(described_class.query_stats_order_clause("avg_time")).to(eq("mean_exec_time DESC"))
        expect(described_class.query_stats_order_clause("calls")).to(eq("calls DESC"))
        expect(described_class.query_stats_order_clause("rows_examined")).to(eq("rows DESC"))
      end

      it "falls back to total_exec_time for unknown sorts" do
        expect(described_class.query_stats_order_clause("nope")).to(eq("total_exec_time DESC"))
      end
    end

    describe ".unused_indexes" do
      it "selects from pg_stat_user_indexes and excludes unique/primary indexes" do
        sql = described_class.unused_indexes(connection)
        expect(sql).to(include("pg_stat_user_indexes"))
        expect(sql).to(include("indisprimary"))
        expect(sql).to(include("indisunique"))
      end
    end

    describe ".drop_index_sql" do
      it "produces a DROP INDEX IF EXISTS with a double-quoted identifier" do
        sql = described_class.drop_index_sql(table: "users", index_name: "idx_legacy")
        expect(sql).to(eq(%(DROP INDEX IF EXISTS "idx_legacy";)))
      end

      it "escapes embedded double quotes in the index name" do
        sql = described_class.drop_index_sql(table: "users", index_name: %(weird"idx))
        expect(sql).to(eq(%(DROP INDEX IF EXISTS "weird""idx";)))
      end
    end

    describe ".digest_column_available?" do
      it "is true (pg_stat_statements always exposes queryid)" do
        expect(described_class.digest_column_available?(connection)).to(be(true))
      end
    end
  end
end
