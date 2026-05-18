# frozen_string_literal: true

module MysqlGenius
  module Core
    # Factory for dialect-specific SQL query builders used by the analysis
    # classes. Each builder is a stateless module exposing class methods
    # that return raw SQL strings; the analysis class is responsible for
    # executing them and mapping result rows into output hashes.
    #
    # Builders intentionally output a stable column-name contract so that
    # downstream transformation logic doesn't need to know which dialect
    # produced the rows. See QueryBuilders::Mysql and ::Postgresql.
    module QueryBuilders
      extend self

      def for(connection)
        case connection.server_version.dialect
        when :postgresql then Postgresql
        else Mysql
        end
      end
    end
  end
end

require "mysql_genius/core/query_builders/mysql"
require "mysql_genius/core/query_builders/postgresql"
