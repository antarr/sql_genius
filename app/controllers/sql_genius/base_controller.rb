# frozen_string_literal: true

module SqlGenius
  class BaseController < SqlGenius.configuration.base_controller.constantize
    layout "sql_genius/application"
    before_action :authenticate_sql_genius!

    private

    def authenticate_sql_genius!
      unless SqlGenius.configuration.authenticate.call(self)
        render(plain: "Not authorized", status: :unauthorized)
      end
    end

    def sql_genius_config
      SqlGenius.configuration
    end

    # Wraps ActiveRecord::Base.connection in a Core::Connection::ActiveRecordAdapter.
    # Every controller action that delegates to a Core::* service calls this
    # instead of instantiating the adapter inline. Shared across all concerns
    # (QueryExecution, DatabaseAnalysis, AiFeatures) via BaseController's
    # private method lookup.
    def rails_connection
      SqlGenius::Core::Connection::ActiveRecordAdapter.new(ActiveRecord::Base.connection)
    end
  end
end
