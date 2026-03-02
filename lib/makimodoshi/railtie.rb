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
        Makimodoshi.logger.warn(
          "[makimodoshi] makimodoshi is intended for development environment only. " \
          "It is currently loaded in '#{Rails.env}' environment. " \
          "No DB operations will be performed."
        )
      end
    end

    initializer "makimodoshi.exclude_from_schema_dump" do
      ActiveSupport.on_load(:active_record) do
        ActiveRecord::SchemaDumper.ignore_tables << Makimodoshi::HIDDEN_TABLE_NAME
      end
    end

    config.after_initialize do
      if Makimodoshi.development? && Makimodoshi::Railtie.server_process?
        Makimodoshi::Railtie.auto_rollback!
      end
    end

    class << self
      def server_process?
        # Rails::Server は rails s 経由で定義される
        # 各 Web サーバの定数も確認し、Puma 以外でも動作するようにする
        defined?(Rails::Server) ||
          (defined?(Puma) && Puma.respond_to?(:cli_config)) ||
          defined?(::Unicorn::HttpServer) ||
          defined?(::Falcon::Server)
      end

      def auto_rollback!
        orphans = SchemaChecker.should_auto_rollback?

        unless orphans
          found = SchemaChecker.orphan_versions
          unless found.empty?
            Makimodoshi.logger.info(
              "[makimodoshi] Orphan migrations found (#{found.join(", ")}), " \
              "but schema.rb has no git diff. Skipping rollback."
            )
          end
          return
        end

        Makimodoshi.logger.info(
          "[makimodoshi] schema.rb has git diff and #{orphans.size} orphan migration(s) " \
          "without files: #{orphans.join(", ")}"
        )
        Makimodoshi.logger.info("[makimodoshi] Auto-rolling back to align with git schema...")

        success = Rollbacker.rollback_versions(orphans)

        if success
          Makimodoshi.logger.info("[makimodoshi] Auto-rollback complete.")
        else
          Makimodoshi.logger.warn(
            "[makimodoshi] Auto-rollback completed with errors. " \
            "Your database may be in an inconsistent state. " \
            "Run 'rails makimodoshi:status' to check."
          )
        end
      end
    end
  end
end
