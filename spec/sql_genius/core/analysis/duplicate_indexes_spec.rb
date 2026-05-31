# frozen_string_literal: true

RSpec.describe(SqlGenius::Core::Analysis::DuplicateIndexes) do
  subject(:analysis) { described_class.new(connection, blocked_tables: blocked_tables) }

  let(:connection) { SqlGenius::Core::Connection::FakeAdapter.new }
  let(:blocked_tables) { ["sessions"] }

  def idx(name, columns, unique: false)
    SqlGenius::Core::IndexDefinition.new(name: name, columns: columns, unique: unique)
  end

  describe "#call" do
    it "returns an empty array when there are no queryable tables" do
      connection.stub_tables([])

      expect(analysis.call).to(eq([]))
    end

    it "returns an empty array when tables have fewer than 2 indexes" do
      connection.stub_tables(["users"])
      connection.stub_indexes_for("users", [idx("index_users_on_email", ["email"], unique: true)])

      expect(analysis.call).to(eq([]))
    end

    it "detects a left-prefix duplicate" do
      connection.stub_tables(["users"])
      connection.stub_indexes_for("users", [
        idx("index_users_on_email", ["email"]),
        idx("index_users_on_email_and_name", ["email", "name"]),
      ])

      result = analysis.call

      expect(result.length).to(eq(1))
      expect(result.first).to(include(
        table: "users",
        duplicate_index: "index_users_on_email",
        duplicate_columns: ["email"],
        covered_by_index: "index_users_on_email_and_name",
        covered_by_columns: ["email", "name"],
        unique: false,
      ))
    end

    it "does not flag two indexes on different columns" do
      connection.stub_tables(["users"])
      connection.stub_indexes_for("users", [
        idx("index_users_on_email", ["email"]),
        idx("index_users_on_name", ["name"]),
      ])

      expect(analysis.call).to(eq([]))
    end

    it "does not drop a unique index covered only by a non-unique one" do
      connection.stub_tables(["users"])
      connection.stub_indexes_for("users", [
        idx("index_users_on_email_unique", ["email"], unique: true),
        idx("index_users_on_email_and_name", ["email", "name"], unique: false),
      ])

      expect(analysis.call).to(eq([]))
    end

    it "skips blocked tables" do
      connection.stub_tables(["users", "sessions"])
      connection.stub_indexes_for("sessions", [
        idx("index_sessions_on_token", ["token"]),
        idx("index_sessions_on_token_and_user_id", ["token", "user_id"]),
      ])
      connection.stub_indexes_for("users", [idx("index_users_on_email", ["email"])])

      expect(analysis.call).to(eq([]))
    end

    it "deduplicates when two indexes cover each other with identical columns" do
      connection.stub_tables(["users"])
      connection.stub_indexes_for("users", [
        idx("idx_a", ["email"]),
        idx("idx_b", ["email"]),
      ])

      result = analysis.call

      expect(result.length).to(eq(1))
    end

    it "includes a MySQL ALTER TABLE drop_sql by default" do
      connection.stub_tables(["users"])
      connection.stub_indexes_for("users", [
        idx("index_users_on_email", ["email"]),
        idx("index_users_on_email_and_name", ["email", "name"]),
      ])

      result = analysis.call
      expect(result.first[:drop_sql]).to(eq("ALTER TABLE `users` DROP INDEX `index_users_on_email`;"))
    end

    context "with a PostgreSQL connection" do
      before { connection.stub_server_version("PostgreSQL 16.1") }

      it "includes a PostgreSQL DROP INDEX drop_sql with double-quoted identifier" do
        connection.stub_tables(["users"])
        connection.stub_indexes_for("users", [
          idx("index_users_on_email", ["email"]),
          idx("index_users_on_email_and_name", ["email", "name"]),
        ])

        result = analysis.call
        expect(result.first[:drop_sql]).to(eq(%(DROP INDEX IF EXISTS "index_users_on_email";)))
      end
    end
  end
end
