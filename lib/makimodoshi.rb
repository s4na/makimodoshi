# frozen_string_literal: true

require "logger"
require_relative "makimodoshi/version"
require_relative "makimodoshi/railtie" if defined?(Rails::Railtie)

module Makimodoshi
  HIDDEN_TABLE_NAME = "_makimodoshi_migrations"

  class InvalidMigrationSourceError < StandardError; end

  LOGGER_MUTEX = Mutex.new

  class << self
    def connection
      if ActiveRecord::Base.respond_to?(:lease_connection)
        ActiveRecord::Base.lease_connection
      else
        ActiveRecord::Base.connection
      end
    end

    def development?
      Rails.env.development?
    end

    def logger
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger
      else
        LOGGER_MUTEX.synchronize do
          @fallback_logger ||= Logger.new($stdout)
        end
      end
    end
  end
end
