# frozen_string_literal: true

module MysqlGenius
  module Core
    module SqlValidator
      FORBIDDEN_KEYWORDS = ["INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "CREATE", "TRUNCATE", "GRANT", "REVOKE"].freeze

      MYSQL_SYSTEM_SCHEMAS = ["information_schema", "mysql", "performance_schema", "sys"].freeze
      POSTGRESQL_SYSTEM_SCHEMAS = ["information_schema", "pg_catalog", "pg_toast", "pg_temp"].freeze

      extend self

      def validate(sql, blocked_tables:, connection:)
        return "Please enter a query." if sql.nil? || sql.strip.empty?

        normalized = sql.gsub(/--.*$/, "").gsub(%r{/\*.*?\*/}m, "").strip

        unless normalized.match?(/\ASELECT\b/i) || normalized.match?(/\AWITH\b/i)
          return "Only SELECT queries are allowed."
        end

        system_schemas = system_schemas_for(connection)
        if normalized.match?(/\b(#{system_schemas.join("|")})\b/i)
          return "Access to system schemas is not allowed."
        end

        FORBIDDEN_KEYWORDS.each do |keyword|
          return "#{keyword} statements are not allowed." if normalized.match?(/\b#{keyword}\b/i)
        end

        tables_in_query = extract_table_references(normalized, connection)
        blocked = tables_in_query & blocked_tables
        if blocked.any?
          return "Access denied for table(s): #{blocked.join(", ")}."
        end

        nil
      end

      def extract_table_references(sql, connection)
        tables = []
        sql.scan(/\bFROM\s+((?:["`]?\w+["`]?(?:\s*,\s*["`]?\w+["`]?)*)+)/i) do |m|
          m[0].scan(/["`]?(\w+)["`]?/) { |t| tables << t[0] }
        end
        sql.scan(/\bJOIN\s+["`]?(\w+)["`]?/i) { |m| tables << m[0] }
        sql.scan(/\b(?:INTO|UPDATE)\s+["`]?(\w+)["`]?/i) { |m| tables << m[0] }
        tables.uniq.map(&:downcase) & connection.tables
      end

      def apply_row_limit(sql, limit)
        if sql.match?(/\bLIMIT\s+\d+\s*,\s*\d+/i)
          sql.gsub(/\bLIMIT\s+(\d+)\s*,\s*(\d+)/i) do
            "LIMIT #{::Regexp.last_match(1).to_i}, #{[::Regexp.last_match(2).to_i, limit].min}"
          end
        elsif sql.match?(/\bLIMIT\s+\d+/i)
          sql.gsub(/\bLIMIT\s+(\d+)/i) { "LIMIT #{[::Regexp.last_match(1).to_i, limit].min}" }
        else
          "#{sql.gsub(/;\s*\z/, "")} LIMIT #{limit}"
        end
      end

      def masked_column?(column_name, patterns)
        patterns.any? { |pattern| column_name.downcase.include?(pattern) }
      end

      def system_schemas_for(connection)
        return MYSQL_SYSTEM_SCHEMAS unless connection.respond_to?(:server_version)

        connection.server_version.postgresql? ? POSTGRESQL_SYSTEM_SCHEMAS : MYSQL_SYSTEM_SCHEMAS
      rescue StandardError
        MYSQL_SYSTEM_SCHEMAS
      end
    end
  end
end
