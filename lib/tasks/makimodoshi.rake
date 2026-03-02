# frozen_string_literal: true

desc "Rollback orphan migrations (no migration file) to align DB schema with git"
task makimodoshi: :environment do
  require "makimodoshi/schema_checker"
  require "makimodoshi/schema_diff_detector"
  require "makimodoshi/migration_store"
  require "makimodoshi/rollbacker"

  unless Makimodoshi.development?
    $stderr.puts "[makimodoshi] This command is only available in development environment."
    exit 1
  end

  initial_orphans = Makimodoshi::SchemaChecker.orphan_versions
  if initial_orphans.empty?
    $stdout.puts "[makimodoshi] No orphan migrations (all excess migrations have files). Nothing to do."
    next
  end

  unless Makimodoshi::SchemaChecker.schema_file_changed_from_git?
    $stdout.puts "[makimodoshi] Orphan migrations found but schema.rb has no git diff. Nothing to do."
    next
  end

  $stdout.puts "[makimodoshi] schema.rb has git diff and #{initial_orphans.size} orphan migration(s) without files."
  $stdout.puts "[makimodoshi] Rolling back to align with git schema..."

  previous_orphan_first = nil

  loop do
    orphans = Makimodoshi::SchemaChecker.orphan_versions
    if orphans.empty?
      if Makimodoshi::SchemaDiffDetector.schema_matches?
        $stdout.puts "[makimodoshi] Schema now matches. Rollback complete."
      else
        $stderr.puts "[makimodoshi] No more orphan migrations but schema still differs from schema.rb."
        $stderr.puts "[makimodoshi] You may need to run 'rails db:migrate' to apply pending migrations."
        exit 1
      end
      break
    end

    if orphans.first == previous_orphan_first
      $stderr.puts "[makimodoshi] Rollback did not reduce orphan migrations. Aborting to prevent infinite loop."
      exit 1
    end
    previous_orphan_first = orphans.first

    success = Makimodoshi::Rollbacker.rollback_one(orphans.first)
    unless success
      $stderr.puts "[makimodoshi] Failed to rollback migration #{orphans.first}. Check logs for details."
      exit 1
    end

    if Makimodoshi::SchemaDiffDetector.schema_matches?
      $stdout.puts "[makimodoshi] Schema now matches. Rollback complete."
      break
    end
  end
end

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

  desc "Rollback the most recent orphan migration (no migration file)"
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
      # 単体ロールバックは手動操作（ユーザーが意図的に実行）のため、
      # schema_file_changed_from_git? チェックは省略する。
      # 自動ロールバック（auto_rollback!、makimodoshi タスク、rollback_all）では
      # git diff チェックを行い、意図しないロールバックを防止している。
      orphans = Makimodoshi::SchemaChecker.orphan_versions
      if orphans.empty?
        $stdout.puts "[makimodoshi] No orphan migrations to rollback."
      else
        Makimodoshi::Rollbacker.rollback_one(orphans.first)
      end
    end
  end

  desc "Rollback all orphan migrations (no migration file, DB ahead of schema.rb)"
  task rollback_all: :environment do
    require "makimodoshi/schema_checker"
    require "makimodoshi/migration_store"
    require "makimodoshi/rollbacker"

    unless Makimodoshi.development?
      $stderr.puts "[makimodoshi] This command is only available in development environment."
      exit 1
    end

    orphans = Makimodoshi::SchemaChecker.orphan_versions

    if orphans.empty?
      $stdout.puts "[makimodoshi] No orphan migrations to rollback."
      next
    end

    unless Makimodoshi::SchemaChecker.schema_file_changed_from_git?
      $stdout.puts "[makimodoshi] Orphan migrations found but schema.rb has no git diff. Nothing to do."
      next
    end

    $stdout.puts "[makimodoshi] Found #{orphans.size} orphan migration(s). Rolling back..."
    success = Makimodoshi::Rollbacker.rollback_versions(orphans)
    if success
      $stdout.puts "[makimodoshi] All orphan migrations rolled back."
    else
      $stderr.puts "[makimodoshi] Some migrations failed to rollback. Check logs for details."
      exit 1
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
