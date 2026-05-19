# frozen_string_literal: true

module MysqlGenius
  module Core
    module SqlValidator
      FORBIDDEN_KEYWORDS = ["INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "CREATE", "TRUNCATE", "GRANT", "REVOKE"].freeze

      extend self

      def validate(sql, blocked_tables:, connection:)
        return "Please enter a query." if sql.nil? || sql.strip.empty?

        normalized = sql.gsub(/--.*$/, "").gsub(%r{/\*.*?\*/}m, "").strip

        unless normalized.match?(/\ASELECT\b/i) || normalized.match?(/\AWITH\b/i)
          return "Only SELECT queries are allowed."
        end

        return "Access to system schemas is not allowed." if normalized.match?(/\b(information_schema|mysql|performance_schema|sys)\b/i)

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
        identifier = /(?:`([^`]+)`|"((?:""|[^"])+)"|(\w+))/
        sql.scan(/\bFROM\s+((?:#{identifier.source}(?:\s*,\s*#{identifier.source})*)+)/i) do |match|
          match[0].scan(identifier) { |parts| tables << unquote_identifier(parts) }
        end
        sql.scan(/\bJOIN\s+#{identifier.source}/i) { |parts| tables << unquote_identifier(parts) }
        sql.scan(/\b(?:INTO|UPDATE)\s+#{identifier.source}/i) { |parts| tables << unquote_identifier(parts) }
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

      def unquote_identifier(parts)
        (parts.find { |part| part && !part.empty? } || "").gsub('""', '"')
      end
    end
  end
end
