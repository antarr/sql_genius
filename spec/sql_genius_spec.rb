# frozen_string_literal: true

RSpec.describe(SqlGenius) do
  it "has a version number" do
    expect(SqlGenius::VERSION).not_to(be_nil)
  end
end
