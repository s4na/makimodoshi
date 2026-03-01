# frozen_string_literal: true

require "tempfile"

module Makimodoshi
  class Rollbacker
    class << self
      def rollback_versions(versions)
        results = versions.map { |version| rollback_one(version) }
        results.all?
      end

      def rollback_one(version)
        stored = MigrationStore.fetch(version)

        if stored.nil?
          logger.warn("[makimodoshi] No stored rollback info for migration #{version}. Skipping.")
          return false
        end

        migration_class = load_migration_class(stored["migration_source"], stored["filename"], version)

        logger.info("[makimodoshi] Rolling back #{version} (#{stored["filename"]})...")

        migration_instance = migration_class.new
        migration_instance.migrate(:down)

        # DDL 成功後のメタデータ削除をトランザクションでまとめ、
        # 片方だけ失敗して不整合になるリスクを下げる
        ActiveRecord::Base.transaction do
          remove_schema_migration(version)
          MigrationStore.remove(version)
        end

        logger.info("[makimodoshi] Rolled back #{version}.")
        true
      rescue InvalidMigrationSourceError
        raise
      rescue => e
        logger.error("[makimodoshi] Failed to rollback migration #{version}: #{e.message}")
        logger.error(e.backtrace.first(5).join("\n")) if e.backtrace
        false
      end

      private

      def load_migration_class(source, filename, version)
        validate_migration_source!(source, version)

        # Extract class name from source code
        class_name = source.match(/class\s+(\w+)\s*</)&.captures&.first

        raise "Could not determine migration class name from source for #{version}" unless class_name

        # 同名クラスが既に定義されている場合は削除して、
        # 正しいバージョンのソースコードからクラスを再定義する。
        # これにより、異なるバージョンで同じクラス名（例: AddColumnToUsers）を
        # 使っている場合の名前衝突を防ぐ。
        if Object.const_defined?(class_name, false)
          Object.send(:remove_const, class_name)
        end

        # Tempfile + load は class_eval より安全:
        # - ファイルパスがスタックトレースに表示される
        # - Ruby パーサを経由するため、eval 特有の攻撃ベクタを回避
        Tempfile.create(["migration_#{version}_", ".rb"]) do |f|
          f.write(source)
          f.flush
          load f.path
        end

        Object.const_get(class_name)
      end

      def validate_migration_source!(source, version)
        unless source.match?(/\A\s*class\s+\w+\s*<\s*ActiveRecord::Migration/)
          raise InvalidMigrationSourceError, "Invalid migration source for #{version}: does not look like an ActiveRecord::Migration"
        end

        # Reject code after the class definition's closing `end`
        unless source.strip.match?(/\bend\s*\z/)
          raise InvalidMigrationSourceError, "Invalid migration source for #{version}: contains code after class definition"
        end

        # Reject dangerous method calls that could execute at class load time.
        # This is defense-in-depth; the source comes from our own hidden table, not user input.
        # Note: This pattern uses ^ (line start) so it also matches calls inside method bodies
        # (e.g., `system(...)` in `def up`), which are false positives. This is intentional:
        # we prefer a strict "deny by default" stance over allowing potentially dangerous code.
        # Migrations using these methods in def bodies will need the source to be re-stored
        # without them, or the validation can be extended to be scope-aware if needed.
        dangerous_pattern = /^\s*(?:::)?(?:system|exec|`|%x|IO\.popen|Kernel\.|Open3\.|eval|instance_eval|class_eval|module_eval|send|public_send|__send__)\b/
        if source.match?(dangerous_pattern)
          raise InvalidMigrationSourceError, "Invalid migration source for #{version}: contains potentially dangerous method calls"
        end
      end

      def remove_schema_migration(version)
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array(
            ["DELETE FROM schema_migrations WHERE version = ?", version]
          )
        )
      end

      def logger
        Makimodoshi.logger
      end
    end
  end
end
