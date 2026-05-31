# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module SqlGenius
  module Core
    module Ai
      # HTTP client for OpenAI-compatible chat completion APIs.
      # Construct with a Core::Ai::Config; call #chat with a messages array.
      class Client
        class NotConfigured < Core::Error; end
        class ApiError < Core::Error; end
        class TooManyRedirects < Core::Error; end

        MAX_REDIRECTS = 3

        def initialize(config)
          @config = config
        end

        def chat(messages:, temperature: 0)
          if @config.client
            return @config.client.call(messages: messages, temperature: temperature)
          end

          raise NotConfigured, "AI is not configured" unless @config.enabled?

          body = if anthropic?
            build_anthropic_body(messages, temperature)
          else
            build_openai_body(messages, temperature)
          end

          response = post_with_redirects(URI(@config.endpoint), body.to_json)
          parsed = JSON.parse(response.body)

          if parsed["error"]
            raise ApiError, "AI API error: #{parsed["error"]["message"] || parsed["error"]}"
          end

          content = if anthropic?
            parsed.dig("content", 0, "text")
          else
            parsed.dig("choices", 0, "message", "content")
          end
          raise ApiError, "No content in AI response" if content.nil?

          parse_json_content(content)
        end

        private

        def anthropic?
          @config.auth_style == :x_api_key
        end

        def build_openai_body(messages, temperature)
          body = {
            messages: messages,
            response_format: { type: "json_object" },
          }
          # GPT-5 and o-series ("reasoning") models renamed max_tokens to
          # max_completion_tokens and only accept temperature=1 (the default).
          # Older chat models (gpt-4o, gpt-4, gpt-3.5) keep the original names.
          if openai_reasoning_model?
            body[:max_completion_tokens] = @config.max_tokens.to_i if @config.max_tokens
          else
            body[:max_tokens] = @config.max_tokens.to_i if @config.max_tokens
            body[:temperature] = temperature
          end
          body[:model] = @config.model if @config.model && !@config.model.empty?
          body
        end

        # Returns true when the configured model belongs to the OpenAI families
        # that reject `max_tokens` and `temperature` overrides: gpt-5*, o1*,
        # o3*, o4*. Matches the bare model name plus common deployment-name
        # prefixes (Azure deployments are user-named but typically include the
        # model identifier).
        OPENAI_REASONING_MODEL_PATTERN = /\b(gpt-5|o1|o3|o4)(-|\b)/i.freeze
        def openai_reasoning_model?
          model = @config.model.to_s
          return false if model.empty?

          model.match?(OPENAI_REASONING_MODEL_PATTERN)
        end

        def build_anthropic_body(messages, temperature)
          system_text = messages.select { |m| m[:role] == "system" }.map { |m| m[:content] }.join("\n\n")
          user_messages = messages.reject { |m| m[:role] == "system" }

          body = {
            messages: user_messages,
            max_tokens: (@config.max_tokens || 4096).to_i,
            temperature: temperature,
          }
          body[:system] = system_text unless system_text.empty?
          body[:model] = @config.model if @config.model && !@config.model.empty?
          body
        end

        def parse_json_content(content)
          JSON.parse(content)
        rescue JSON::ParserError
          stripped = content.to_s
            .gsub(/\A\s*```(?:json)?\s*/i, "")
            .gsub(/\s*```\s*\z/, "")
            .strip
          begin
            JSON.parse(stripped)
          rescue JSON::ParserError
            { "raw" => content.to_s }
          end
        end

        def post_with_redirects(uri, body, redirects = 0)
          raise TooManyRedirects, "Too many redirects" if redirects > MAX_REDIRECTS

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          if http.use_ssl?
            http.verify_mode = OpenSSL::SSL::VERIFY_PEER
            cert_file = ENV["SSL_CERT_FILE"] || OpenSSL::X509::DEFAULT_CERT_FILE
            http.ca_file = cert_file if File.exist?(cert_file)
          end
          http.open_timeout = 10
          http.read_timeout = 60

          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          case @config.auth_style
          when :bearer
            request["Authorization"] = "Bearer #{@config.api_key}"
          when :x_api_key
            request["x-api-key"] = @config.api_key
            request["anthropic-version"] = "2023-06-01"
          else
            request["api-key"] = @config.api_key
          end
          request.body = body

          response = http.request(request)

          if response.is_a?(Net::HTTPRedirection)
            post_with_redirects(URI(response["location"]), body, redirects + 1)
          else
            response
          end
        end
      end
    end
  end
end
