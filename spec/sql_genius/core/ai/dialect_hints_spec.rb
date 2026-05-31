# frozen_string_literal: true

RSpec.describe(SqlGenius::Core::Ai::DialectHints) do
  let(:connection) { SqlGenius::Core::Connection::FakeAdapter.new }

  describe ".name_for" do
    it "returns 'MySQL/MariaDB' for MySQL" do
      connection.stub_server_version("8.0.35")
      expect(described_class.name_for(connection)).to(eq("MySQL/MariaDB"))
    end

    it "returns 'MySQL/MariaDB' for MariaDB (same prompt family)" do
      connection.stub_server_version("10.11.5-MariaDB")
      expect(described_class.name_for(connection)).to(eq("MySQL/MariaDB"))
    end

    it "returns 'PostgreSQL' for PostgreSQL" do
      connection.stub_server_version("PostgreSQL 16.1")
      expect(described_class.name_for(connection)).to(eq("PostgreSQL"))
    end
  end

  describe ".identifier_quoting_rule" do
    it "tells the model to use backticks on MySQL" do
      connection.stub_server_version("8.0.35")
      expect(described_class.identifier_quoting_rule(connection)).to(include("backtick"))
    end

    it "tells the model to use double quotes on PostgreSQL" do
      connection.stub_server_version("PostgreSQL 16.1")
      expect(described_class.identifier_quoting_rule(connection)).to(include('double quotes ("col_name")'))
    end
  end
end
