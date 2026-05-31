# frozen_string_literal: true

require "rails_helper"

RSpec.describe("AI feature routes", type: :request) do
  let(:ai_client) { instance_double(SqlGenius::Core::Ai::Client) }

  before do
    stub_connection(tables: ["users"])
    empty_result = fake_result
    # root_cause action iterates exec_query results with .each — stub it here
    # since fake_result doesn't include .each by default.
    allow(empty_result).to(receive(:each).and_yield({}))
    allow(ActiveRecord::Base.connection).to(receive_messages(exec_query: empty_result, select_value: "8.0.35"))
    allow(ActiveRecord::Base.connection).to(receive(:columns).with(anything).and_return([]))
    allow(ActiveRecord::Base.connection).to(receive(:indexes).with(anything).and_return([]))
    allow(ActiveRecord::Base.connection).to(receive(:primary_key).with(anything).and_return("id"))

    SqlGenius.configure do |c|
      c.ai_endpoint = "http://localhost/ai"
      c.ai_api_key = "test-key"
      c.ai_model = "test-model"
    end

    allow(SqlGenius::Core::Ai::Client).to(receive(:new).and_return(ai_client))
    allow(ai_client).to(receive(:chat).and_return({ "explanation" => "canned response" }))
  end

  describe "POST /sql_genius/suggest" do
    it "returns 200 when AI is configured" do
      allow(ai_client).to(receive(:chat).and_return({ "sql" => "SELECT 1", "explanation" => "ok" }))
      post "/sql_genius/suggest", prompt: "all users"
      expect(last_response).to(be_ok)
    end

    it "returns 404 when AI is not configured" do
      SqlGenius.configure { |c| c.ai_endpoint = nil }
      post "/sql_genius/suggest", prompt: "all users"
      expect(last_response.status).to(eq(404))
    end
  end

  describe "POST /sql_genius/optimize" do
    it "returns 200 with SQL + explain rows" do
      post "/sql_genius/optimize", sql: "SELECT 1", explain_rows: [[{ "id" => 1 }]]
      expect(last_response).to(be_ok)
    end
  end

  describe "POST /sql_genius/describe_query" do
    it "returns 200 for a non-blank SQL" do
      post "/sql_genius/describe_query", sql: "SELECT 1"
      expect(last_response).to(be_ok)
    end

    it "returns 422 for blank SQL" do
      post "/sql_genius/describe_query", sql: ""
      expect(last_response.status).to(eq(422))
    end
  end

  describe "POST /sql_genius/schema_review" do
    it "returns 200 with or without a table param" do
      post "/sql_genius/schema_review"
      expect(last_response).to(be_ok)
    end
  end

  describe "POST /sql_genius/rewrite_query" do
    it "returns 200 for a valid SQL" do
      post "/sql_genius/rewrite_query", sql: "SELECT 1"
      expect(last_response).to(be_ok)
    end
  end

  describe "POST /sql_genius/index_advisor" do
    it "returns 200 with SQL + explain rows" do
      post "/sql_genius/index_advisor", sql: "SELECT 1 FROM users", explain_rows: [[{ "id" => 1 }]]
      expect(last_response).to(be_ok)
    end

    it "returns 422 when explain_rows are missing" do
      post "/sql_genius/index_advisor", sql: "SELECT 1"
      expect(last_response.status).to(eq(422))
    end
  end

  describe "POST /sql_genius/anomaly_detection" do
    it "returns 200 (stays Rails-side in Phase 2a)" do
      post "/sql_genius/anomaly_detection"
      expect(last_response).to(be_ok)
    end
  end

  describe "POST /sql_genius/root_cause" do
    it "returns 200 (stays Rails-side in Phase 2a)" do
      post "/sql_genius/root_cause"
      expect(last_response).to(be_ok)
    end
  end

  describe "POST /sql_genius/migration_risk" do
    it "returns 200 with a migration body" do
      post "/sql_genius/migration_risk", migration: "ALTER TABLE users ADD INDEX"
      expect(last_response).to(be_ok)
    end

    it "returns 422 when migration body is blank" do
      post "/sql_genius/migration_risk", migration: ""
      expect(last_response.status).to(eq(422))
    end
  end

  describe "POST /sql_genius/variable_review" do
    it "returns 200 when AI is configured" do
      post "/sql_genius/variable_review"
      expect(last_response).to(be_ok)
    end

    it "returns 404 when AI is not configured" do
      SqlGenius.configure { |c| c.ai_endpoint = nil }
      post "/sql_genius/variable_review"
      expect(last_response.status).to(eq(404))
    end
  end

  describe "POST /sql_genius/connection_advisor" do
    it "returns 200 when AI is configured" do
      post "/sql_genius/connection_advisor"
      expect(last_response).to(be_ok)
    end

    it "returns 404 when AI is not configured" do
      SqlGenius.configure { |c| c.ai_endpoint = nil }
      post "/sql_genius/connection_advisor"
      expect(last_response.status).to(eq(404))
    end
  end

  describe "POST /sql_genius/workload_digest" do
    it "returns 200 when AI is configured" do
      post "/sql_genius/workload_digest"
      expect(last_response).to(be_ok)
    end

    it "returns 404 when AI is not configured" do
      SqlGenius.configure { |c| c.ai_endpoint = nil }
      post "/sql_genius/workload_digest"
      expect(last_response.status).to(eq(404))
    end
  end

  describe "POST /sql_genius/innodb_health" do
    it "returns 200 when AI is configured" do
      post "/sql_genius/innodb_health"
      expect(last_response).to(be_ok)
    end

    it "returns 404 when AI is not configured" do
      SqlGenius.configure { |c| c.ai_endpoint = nil }
      post "/sql_genius/innodb_health"
      expect(last_response.status).to(eq(404))
    end
  end

  describe "POST /sql_genius/index_planner" do
    it "returns 200 when AI is configured" do
      post "/sql_genius/index_planner"
      expect(last_response).to(be_ok)
    end

    it "returns 404 when AI is not configured" do
      SqlGenius.configure { |c| c.ai_endpoint = nil }
      post "/sql_genius/index_planner"
      expect(last_response.status).to(eq(404))
    end
  end

  describe "POST /sql_genius/pattern_grouper" do
    it "returns 200 when AI is configured" do
      post "/sql_genius/pattern_grouper"
      expect(last_response).to(be_ok)
    end

    it "returns 404 when AI is not configured" do
      SqlGenius.configure { |c| c.ai_endpoint = nil }
      post "/sql_genius/pattern_grouper"
      expect(last_response.status).to(eq(404))
    end
  end
end
