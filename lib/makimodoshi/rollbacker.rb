# frozen_string_literal: true

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

        # Note: If remove_schema_migration or MigrationStore.remove fails after
        # migrate(:down) succeeds, the DB schema will be rolled back but the
        # tracking records will remain. This is a known limitation; manual cleanup
        # of schema_migrations and _makimodoshi_migrations may be needed in that case.
        remove_schema_migration(version)
        MigrationStore.remove(version)

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

        # Define the class at top-level scope
        # Source is from our own hidden table, not user input
        Object.class_eval(source) unless Object.const_defined?(class_name, false) # rubocop:disable Security/Eval

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

        # Reject dangerous top-level method calls inside class body that execute at load time.
        # This is defense-in-depth; the source comes from our own hidden table, not user input.
        dangerous_pattern = /^\s*(?:system|exec|`|%x|IO\.popen|Kernel\.|Open3\.|eval|instance_eval|class_eval|module_eval|send|public_send|__send__)\b/
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
