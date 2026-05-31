# frozen_string_literal: true

module SqlGenius
  module Core
    # Connection abstraction. This module is a namespace for concrete
    # adapters plus documentation of the contract every adapter must
    # satisfy. It is NOT meant to be included as a mixin; Ruby has no
    # interface enforcement. Tests exercise the contract via duck-typing
    # against the real adapters and the FakeAdapter test helper.
    #
    # Implementing adapters:
    #   SqlGenius::Core::Connection::FakeAdapter         — used by tests
    #   SqlGenius::Core::Connection::ActiveRecordAdapter — wraps ActiveRecord::Base.connection
    #
    # Contract (every adapter must implement):
    #
    #   #exec_query(sql)                -> Core::Result
    #   #select_value(sql)              -> Object (first column of first row, or nil)
    #   #server_version                 -> Core::ServerInfo
    #   #current_database               -> String
    #   #quote(value)                   -> String (SQL-escaped value)
    #   #quote_table_name(name)         -> String (dialect-quoted identifier:
    #                                       backticks for MySQL/MariaDB,
    #                                       double-quotes for PostgreSQL)
    #   #tables                         -> Array<String>
    #   #columns_for(table)             -> Array<Core::ColumnDefinition>
    #   #indexes_for(table)             -> Array<Core::IndexDefinition>
    #   #primary_key(table)             -> String or nil
    #   #close                          -> nil
    #
    # Adapters may implement additional methods for efficiency, but any
    # core code that depends on the connection must only call methods
    # defined in this contract.
    module Connection
    end
  end
end
