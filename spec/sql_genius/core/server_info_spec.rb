# frozen_string_literal: true

RSpec.describe(SqlGenius::Core::ServerInfo) do
  describe ".parse" do
    it "recognises MySQL from a version string" do
      info = described_class.parse("8.0.35")
      expect(info.vendor).to(eq(:mysql))
      expect(info.version).to(eq("8.0.35"))
    end

    it "recognises MariaDB from a version string containing 'MariaDB'" do
      info = described_class.parse("10.11.5-MariaDB-1:10.11.5+maria~ubu2204")
      expect(info.vendor).to(eq(:mariadb))
      expect(info.version).to(eq("10.11.5-MariaDB-1:10.11.5+maria~ubu2204"))
    end

    it "recognises MariaDB case-insensitively" do
      info = described_class.parse("10.4.30-mariadb-log")
      expect(info.vendor).to(eq(:mariadb))
    end

    it "recognises PostgreSQL from a version string containing 'PostgreSQL'" do
      info = described_class.parse("PostgreSQL 16.1 on x86_64-pc-linux-gnu, compiled by gcc")
      expect(info.vendor).to(eq(:postgresql))
    end

    it "recognises PostgreSQL case-insensitively" do
      info = described_class.parse("postgresql 15.4")
      expect(info.vendor).to(eq(:postgresql))
    end
  end

  describe "#mariadb?" do
    it "is true for MariaDB" do
      expect(described_class.new(vendor: :mariadb, version: "10.11").mariadb?).to(be(true))
    end

    it "is false for MySQL" do
      expect(described_class.new(vendor: :mysql, version: "8.0").mariadb?).to(be(false))
    end

    it "is false for PostgreSQL" do
      expect(described_class.new(vendor: :postgresql, version: "16").mariadb?).to(be(false))
    end
  end

  describe "#mysql?" do
    it "is true for MySQL" do
      expect(described_class.new(vendor: :mysql, version: "8.0").mysql?).to(be(true))
    end

    it "is false for MariaDB" do
      expect(described_class.new(vendor: :mariadb, version: "10.11").mysql?).to(be(false))
    end

    it "is false for PostgreSQL" do
      expect(described_class.new(vendor: :postgresql, version: "16").mysql?).to(be(false))
    end
  end

  describe "#postgresql?" do
    it "is true for PostgreSQL" do
      expect(described_class.new(vendor: :postgresql, version: "16").postgresql?).to(be(true))
    end

    it "is false for MySQL" do
      expect(described_class.new(vendor: :mysql, version: "8.0").postgresql?).to(be(false))
    end

    it "is false for MariaDB" do
      expect(described_class.new(vendor: :mariadb, version: "10.11").postgresql?).to(be(false))
    end
  end

  describe "#dialect" do
    it "is :mysql for MySQL" do
      expect(described_class.new(vendor: :mysql, version: "8.0").dialect).to(eq(:mysql))
    end

    it "is :mysql for MariaDB" do
      expect(described_class.new(vendor: :mariadb, version: "10.11").dialect).to(eq(:mysql))
    end

    it "is :postgresql for PostgreSQL" do
      expect(described_class.new(vendor: :postgresql, version: "16").dialect).to(eq(:postgresql))
    end
  end
end
