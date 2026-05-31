# frozen_string_literal: true

require "spec_helper"
require "sql_genius/core"
require "sql_genius/core/ai/rewrite_query"
require "sql_genius/core/connection/fake_adapter"

RSpec.describe(SqlGenius::Core::Ai::RewriteQuery) do
  subject(:builder) { described_class.new(client, config, connection) }

  let(:client) { instance_double(SqlGenius::Core::Ai::Client) }
  let(:config) do
    SqlGenius::Core::Ai::Config.new(
      client: "openai",
      endpoint: "x",
      api_key: "k",
      model: "m",
      auth_style: :bearer,
      system_context: "",
    )
  end
  let(:connection) do
    conn = SqlGenius::Core::Connection::FakeAdapter.new
    conn.stub_tables(["users"])
    conn.stub_columns_for("users", [
      SqlGenius::Core::ColumnDefinition.new(name: "id", sql_type: "bigint", type: :integer, null: false, default: nil, primary_key: true),
    ])
    conn.stub_indexes_for("users", [])
    conn.stub_primary_key("users", "id")
    conn
  end

  it "extracts tables from the SQL and includes their schema in the user message" do
    expect(client).to(receive(:chat)) do |messages:|
      expect(messages[1][:content]).to(eq("SELECT id FROM users"))
      expect(messages[0][:content]).to(include("Available schema:"))
      expect(messages[0][:content]).to(include("Table: users"))
    end.and_return({ "original" => "SELECT id FROM users", "rewritten" => "SELECT id FROM users", "changes" => "none" })
    builder.call("SELECT id FROM users")
  end
end
