# frozen_string_literal: true

module MysqlGenius
  module Core
    module Ai
      # Snippets injected into AI system prompts so the model generates SQL in
      # the right dialect. Without these, prompts hardcode "MySQL" and tell
      # the model to use backticks — which produces broken SQL on PostgreSQL
      # (PG uses double quotes for identifiers and has no backtick syntax).
      module DialectHints
        extend self

        # Display name suitable for "You are a SQL assistant for a #{name_for}
        # database." prompts.
        def name_for(connection)
          case connection.server_version.dialect
          when :postgresql then "PostgreSQL"
          else "MySQL/MariaDB"
          end
        end

        # Identifier-quoting rule string for inclusion in a numbered Rules
        # list in a prompt. PG uses double quotes; MySQL/MariaDB uses
        # backticks.
        def identifier_quoting_rule(connection)
          if connection.server_version.postgresql?
            %(Use double quotes ("col_name") for case-sensitive identifiers; otherwise leave them bare.)
          else
            "Use backticks (`col_name`) for table and column names."
          end
        end
      end
    end
  end
end
