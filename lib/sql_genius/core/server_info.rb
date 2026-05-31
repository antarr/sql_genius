# frozen_string_literal: true

module SqlGenius
  module Core
    # Identifies the database vendor and version. Adapters construct one
    # from the server's VERSION() output.
    #
    # Three vendors are recognised: :mysql, :mariadb, :postgresql.
    # #dialect collapses these into the SQL family used by query builders
    # — :mysql (covering both MySQL and MariaDB) or :postgresql.
    class ServerInfo
      attr_reader :vendor, :version

      class << self
        def parse(version_string)
          str = version_string.to_s
          vendor = if str.match?(/postgresql/i)
            :postgresql
          elsif str.downcase.include?("mariadb")
            :mariadb
          else
            :mysql
          end
          new(vendor: vendor, version: str)
        end
      end

      # vendor must be :mysql, :mariadb, or :postgresql
      def initialize(vendor:, version:)
        @vendor = vendor
        @version = version
        freeze
      end

      def mariadb?
        @vendor == :mariadb
      end

      def mysql?
        @vendor == :mysql
      end

      def postgresql?
        @vendor == :postgresql
      end

      # SQL family used to pick a query builder. MySQL and MariaDB share
      # one dialect; PostgreSQL is its own.
      def dialect
        postgresql? ? :postgresql : :mysql
      end
    end
  end
end
