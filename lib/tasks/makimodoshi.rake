# frozen_string_literal: true

namespace :makimodoshi do
  desc "Show stored migrations available for rollback"
  task status: :environment do
    require "makimodoshi/migration_store"

    stored = Makimodoshi::MigrationStore.all_stored

    if stored.empty?
      Makimodoshi.logger.info("[makimodoshi] No stored migrations.")
    else
      Makimodoshi.logger.info("[makimodoshi] Stored migrations:")
      Makimodoshi.logger.info("  #{"Version".ljust(16)} #{"Filename".ljust(50)} Migrated At")
      Makimodoshi.logger.info("  #{"-" * 16} #{"-" * 50} #{"-" * 20}")
      stored.each do |row|
        Makimodoshi.logger.info("  #{row["version"].ljust(16)} #{row["filename"].ljust(50)} #{row["migrated_at"]}")
      end
    end
  end

  desc "Rollback the most recent excess migration"
  task rollback: :environment do
    require "makimodoshi/schema_checker"
    require "makimodoshi/migration_store"
    require "makimodoshi/rollbacker"

    unless Makimodoshi.development?
      Makimodoshi.logger.error("[makimodoshi] ERROR: This command is only available in development environment.")
      exit 1
    end

    excess = Makimodoshi::SchemaChecker.excess_versions

    if excess.empty?
      version = ENV["VERSION"]
      if version
        Makimodoshi::Rollbacker.rollback_one(version)
      else
        Makimodoshi.logger.info("[makimodoshi] No excess migrations to rollback.")
      end
    else
      version = ENV["VERSION"]
      if version
        unless excess.include?(version)
          Makimodoshi.logger.warn("[makimodoshi] WARNING: Version #{version} is not in excess migrations list.")
        end
        Makimodoshi::Rollbacker.rollback_one(version)
      else
        # Rollback one (the most recent excess)
        Makimodoshi::Rollbacker.rollback_one(excess.first)
      end
    end
  end

  desc "Rollback all excess migrations (DB ahead of schema.rb)"
  task rollback_all: :environment do
    require "makimodoshi/schema_checker"
    require "makimodoshi/migration_store"
    require "makimodoshi/rollbacker"

    unless Makimodoshi.development?
      Makimodoshi.logger.error("[makimodoshi] ERROR: This command is only available in development environment.")
      exit 1
    end

    excess = Makimodoshi::SchemaChecker.excess_versions

    if excess.empty?
      Makimodoshi.logger.info("[makimodoshi] No excess migrations to rollback.")
    else
      Makimodoshi.logger.info("[makimodoshi] Found #{excess.size} excess migration(s). Rolling back...")
      Makimodoshi::Rollbacker.rollback_versions(excess)
      Makimodoshi.logger.info("[makimodoshi] All excess migrations rolled back.")
    end
  end
end

# Hook into db:migrate to store migration info
Rake::Task["db:migrate"].enhance do
  if defined?(Makimodoshi) && Makimodoshi.development?
    require "makimodoshi/migration_store"
    require "makimodoshi/schema_checker"
    require "makimodoshi/migration_interceptor"

    Makimodoshi::MigrationInterceptor.store_all_pending
  end
end
