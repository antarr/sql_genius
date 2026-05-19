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

      def normalize_identifier_quotes(sql, connection)
        quote = connection.quote_table_name("mysql_genius_identifier_probe")[0]
        return sql if quote == "`" || !sql.include?("`")

        rewrite_backtick_identifiers(sql, connection)
      end

      def masked_column?(column_name, patterns)
        patterns.any? { |pattern| column_name.downcase.include?(pattern) }
      end

      def unquote_identifier(parts)
        (parts.find { |part| part && !part.empty? } || "").gsub('""', '"')
      end

      def rewrite_backtick_identifiers(sql, connection)
        output = +""
        i = 0

        while i < sql.length
          char = sql[i]

          if char == "'"
            literal, i = read_single_quoted_literal(sql, i)
            output << literal
          elsif char == "`"
            identifier, i = read_backtick_identifier(sql, i)
            output << connection.quote_table_name(identifier)
          else
            output << char
            i += 1
          end
        end

        output
      end

      def read_single_quoted_literal(sql, index)
        output = +"'"
        i = index + 1

        while i < sql.length
          output << sql[i]
          if sql[i] == "'"
            if sql[i + 1] == "'"
              output << sql[i + 1]
              i += 2
              next
            end

            i += 1
            break
          end
          i += 1
        end

        [output, i]
      end

      def read_backtick_identifier(sql, index)
        output = +""
        i = index + 1

        while i < sql.length
          if sql[i] == "`"
            if sql[i + 1] == "`"
              output << "`"
              i += 2
              next
            end

            i += 1
            break
          end

          output << sql[i]
          i += 1
        end

        [output, i]
      end
    end
  end
end
