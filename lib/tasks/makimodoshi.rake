# frozen_string_literal: true

namespace :makimodoshi do
  desc "Show stored migrations available for rollback"
  task status: :environment do
    require "makimodoshi/migration_store"

    stored = Makimodoshi::MigrationStore.all_stored

    if stored.empty?
      $stdout.puts "[makimodoshi] No stored migrations."
    else
      $stdout.puts "[makimodoshi] Stored migrations:"
      $stdout.puts "  #{"Version".ljust(16)} #{"Filename".ljust(50)} Migrated At"
      $stdout.puts "  #{"-" * 16} #{"-" * 50} #{"-" * 20}"
      stored.each do |row|
        $stdout.puts "  #{row["version"].ljust(16)} #{row["filename"].ljust(50)} #{row["migrated_at"]}"
      end
    end
  end

  desc "Rollback the most recent excess migration"
  task rollback: :environment do
    require "makimodoshi/schema_checker"
    require "makimodoshi/migration_store"
    require "makimodoshi/rollbacker"

    unless Makimodoshi.development?
      $stderr.puts "[makimodoshi] This command is only available in development environment."
      exit 1
    end

    version = ENV["VERSION"]
    if version
      # VERSION 指定時は明示的にそのバージョンをロールバック
      Makimodoshi::Rollbacker.rollback_one(version)
    else
      excess = Makimodoshi::SchemaChecker.excess_versions
      if excess.empty?
        $stdout.puts "[makimodoshi] No excess migrations to rollback."
      else
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
      $stderr.puts "[makimodoshi] This command is only available in development environment."
      exit 1
    end

    excess = Makimodoshi::SchemaChecker.excess_versions

    if excess.empty?
      $stdout.puts "[makimodoshi] No excess migrations to rollback."
    else
      $stdout.puts "[makimodoshi] Found #{excess.size} excess migration(s). Rolling back..."
      success = Makimodoshi::Rollbacker.rollback_versions(excess)
      if success
        $stdout.puts "[makimodoshi] All excess migrations rolled back."
      else
        $stderr.puts "[makimodoshi] Some migrations failed to rollback. Check logs for details."
        exit 1
      end
    end
  end
end

# Hook into migration tasks to store migration info
%w[db:migrate db:migrate:up].each do |task_name|
  next unless Rake::Task.task_defined?(task_name)

  Rake::Task[task_name].enhance do
    if defined?(Makimodoshi) && Makimodoshi.development?
      require "makimodoshi/migration_store"
      require "makimodoshi/schema_checker"
      require "makimodoshi/migration_interceptor"

      Makimodoshi::MigrationInterceptor.store_all_pending
    end
  end
end
