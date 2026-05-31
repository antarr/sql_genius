# frozen_string_literal: true

module SqlGenius
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates a SqlGenius initializer and mounts the engine in routes."

      def copy_initializer
        template("initializer.rb", "config/initializers/sql_genius.rb")
      end

      def mount_engine
        route('mount SqlGenius::Engine, at: "/sql_genius"')
      end
    end
  end
end
