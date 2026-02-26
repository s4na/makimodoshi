# frozen_string_literal: true

require_relative "migration_store"
require_relative "schema_checker"
require_relative "rollbacker"
require_relative "migration_interceptor"

module Makimodoshi
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("../../tasks/makimodoshi.rake", __FILE__)
    end

    initializer "makimodoshi.environment_check" do
      unless Makimodoshi.development?
        puts "[makimodoshi] WARNING: makimodoshi is intended for development environment only. " \
             "It is currently loaded in '#{Rails.env}' environment. " \
             "No DB operations will be performed."
      end
    end

    initializer "makimodoshi.exclude_from_schema_dump" do
      ActiveSupport.on_load(:active_record) do
        ActiveRecord::SchemaDumper.ignore_tables << Makimodoshi::HIDDEN_TABLE_NAME
      end
    end

    config.after_initialize do
      if Makimodoshi.development? && defined?(Rails::Server)
        auto_rollback!
      end
    end

    class << self
      def auto_rollback!
        excess = SchemaChecker.excess_versions
        return if excess.empty?

        puts "[makimodoshi] DB is ahead of schema.rb by #{excess.size} migration(s): #{excess.join(", ")}"
        puts "[makimodoshi] Auto-rolling back..."

        Rollbacker.rollback_versions(excess)

        puts "[makimodoshi] Auto-rollback complete."
      end
    end
  end
end
