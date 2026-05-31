# frozen_string_literal: true

RSpec.describe(SqlGenius::Core::QueryExplainer) do
  subject(:explainer) { described_class.new(connection, config) }

  let(:connection) { SqlGenius::Core::Connection::FakeAdapter.new }
  let(:config) do
    SqlGenius::Core::QueryRunner::Config.new(
      blocked_tables: ["sessions"],
      masked_column_patterns: [],
      query_timeout_ms: 30_000,
    )
  end

  before do
    connection.stub_tables(["users", "posts", "sessions"])
  end

  describe "#explain" do
    it "returns a Core::Result for a valid SELECT" do
      connection.stub_query(
        /EXPLAIN SELECT/,
        columns: ["id", "select_type", "table", "type"],
        rows: [[1, "SIMPLE", "users", "ALL"]],
      )

      result = explainer.explain("SELECT id FROM users")

      expect(result).to(be_a(SqlGenius::Core::Result))
      expect(result.columns).to(eq(["id", "select_type", "table", "type"]))
      expect(result.rows).to(eq([[1, "SIMPLE", "users", "ALL"]]))
    end

    it "raises Rejected for a non-SELECT query" do
      expect { explainer.explain("DELETE FROM users") }
        .to(raise_error(SqlGenius::Core::QueryRunner::Rejected, /Only SELECT/))
    end

    it "raises Rejected for a blocked table" do
      expect { explainer.explain("SELECT * FROM sessions") }
        .to(raise_error(SqlGenius::Core::QueryRunner::Rejected, /sessions/))
    end

    it "skips validation when skip_validation: true" do
      connection.stub_query(/EXPLAIN SELECT/, columns: ["id"], rows: [[1]])

      expect { explainer.explain("SELECT id FROM users", skip_validation: true) }
        .not_to(raise_error)
    end

    it "raises Truncated when the SQL appears to be cut mid-statement" do
      expect { explainer.explain("SELECT id, name FROM users WHERE", skip_validation: true) }
        .to(raise_error(SqlGenius::Core::QueryExplainer::Truncated, /truncated/))
    end

    it "accepts SQL ending with a closing paren" do
      connection.stub_query(/EXPLAIN/, columns: ["id"], rows: [[1]])

      expect { explainer.explain("SELECT id FROM (SELECT id FROM users)", skip_validation: true) }
        .not_to(raise_error)
    end

    it "accepts SQL ending with a number" do
      connection.stub_query(/EXPLAIN/, columns: ["id"], rows: [[1]])

      expect { explainer.explain("SELECT id FROM users LIMIT 10", skip_validation: true) }
        .not_to(raise_error)
    end

    it "accepts SQL ending with a closing quote" do
      connection.stub_query(/EXPLAIN/, columns: ["id"], rows: [[1]])

      expect { explainer.explain("SELECT id FROM users WHERE name = 'alice'", skip_validation: true) }
        .not_to(raise_error)
    end

    it "accepts SQL ending with a Rails query-annotation comment (closed block comment)" do
      # SELECT ... /*action='table_sizes',application='WeVote',controller='queries'*/
      # ends in `*/` which would otherwise trip the trailing-operator check.
      connection.stub_query(/EXPLAIN/, columns: ["id"], rows: [[1]])

      expect do
        explainer.explain(
          %(SELECT COUNT(*) FROM users /*action='table_sizes',application='WeVote',controller='queries'*/),
          skip_validation: true,
        )
      end.not_to(raise_error)
    end

    it "strips a trailing semicolon before wrapping in EXPLAIN" do
      captured_sql = nil
      connection.stub_query(/EXPLAIN/, columns: ["id"], rows: [[1]])
      allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
        captured_sql = sql
        original.call(sql, **kwargs)
      end)

      explainer.explain("SELECT id FROM users;")
      expect(captured_sql).to(eq("EXPLAIN SELECT id FROM users"))
    end

    context "with a PostgreSQL connection" do
      before { connection.stub_server_version("PostgreSQL 16.1") }

      it "substitutes $N bind placeholders with NULL so EXPLAIN can plan a captured digest" do
        captured_sql = nil
        connection.stub_query(/EXPLAIN/, columns: ["plan"], rows: [["Seq Scan on users"]])
        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql
          original.call(sql, **kwargs)
        end)

        explainer.explain(
          %(SELECT "users".* FROM "users" WHERE "users"."slug" = $1 LIMIT $2),
          skip_validation: true,
        )
        expect(captured_sql).to(eq(%(EXPLAIN SELECT "users".* FROM "users" WHERE "users"."slug" = NULL LIMIT NULL)))
      end

      it "leaves SQL without placeholders untouched" do
        captured_sql = nil
        connection.stub_query(/EXPLAIN/, columns: ["plan"], rows: [["Seq Scan"]])
        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql
          original.call(sql, **kwargs)
        end)

        explainer.explain("SELECT id FROM users", skip_validation: true)
        expect(captured_sql).to(eq("EXPLAIN SELECT id FROM users"))
      end

      it "rewrites backtick identifiers to PostgreSQL double quotes" do
        captured_sql = nil
        connection.stub_query(/EXPLAIN/, columns: ["plan"], rows: [["Seq Scan"]])
        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql
          original.call(sql, **kwargs)
        end)

        explainer.explain("SELECT `id` FROM `users`", skip_validation: true)

        expect(captured_sql).to(eq(%(EXPLAIN SELECT "id" FROM "users")))
      end

      it "handles multi-digit placeholders ($10, $42)" do
        captured_sql = nil
        connection.stub_query(/EXPLAIN/, columns: ["plan"], rows: [["plan"]])
        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql
          original.call(sql, **kwargs)
        end)

        explainer.explain("SELECT id FROM users WHERE a = $10 AND b = $42", skip_validation: true)
        expect(captured_sql).to(include("a = NULL AND b = NULL"))
      end
    end

    context "with a MySQL connection (default FakeAdapter version)" do
      it "substitutes unquoted ? placeholders with NULL" do
        captured_sql = nil
        connection.stub_query(/EXPLAIN/, columns: ["id"], rows: [[1]])
        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql
          original.call(sql, **kwargs)
        end)

        explainer.explain("SELECT * FROM users WHERE id = ? LIMIT ?", skip_validation: true)
        expect(captured_sql).to(eq("EXPLAIN SELECT * FROM users WHERE id = NULL LIMIT NULL"))
      end

      it "does not substitute ? inside single-quoted string literals" do
        captured_sql = nil
        connection.stub_query(/EXPLAIN/, columns: ["id"], rows: [[1]])
        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql
          original.call(sql, **kwargs)
        end)

        explainer.explain("SELECT * FROM users WHERE name = '?' AND id = ?", skip_validation: true)
        expect(captured_sql).to(eq("EXPLAIN SELECT * FROM users WHERE name = '?' AND id = NULL"))
      end

      it "handles escaped single quotes ('' inside a string) without breaking placeholder detection" do
        captured_sql = nil
        connection.stub_query(/EXPLAIN/, columns: ["id"], rows: [[1]])
        allow(connection).to(receive(:exec_query).and_wrap_original do |original, sql, **kwargs|
          captured_sql = sql
          original.call(sql, **kwargs)
        end)

        # The 'O''Brien' literal contains an escaped quote; the ? after it
        # is OUTSIDE any string and should be substituted.
        explainer.explain("SELECT * FROM users WHERE name = 'O''Brien' AND id = ?", skip_validation: true)
        expect(captured_sql).to(eq("EXPLAIN SELECT * FROM users WHERE name = 'O''Brien' AND id = NULL"))
      end
    end
  end
end
