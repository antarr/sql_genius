# frozen_string_literal: true

require "sql_genius/version"
require "sql_genius/core"
require "sql_genius/core/connection/active_record_adapter"
require "sql_genius/configuration"

module SqlGenius
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    attr_accessor :stats_history
    attr_accessor :stats_collector
  end
end

require "sql_genius/engine" if defined?(Rails)
