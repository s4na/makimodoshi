# frozen_string_literal: true

module Makimodoshi
  class Rollbacker
    class << self
      def rollback_versions(versions)
        versions.each do |version|
          rollback_one(version)
        end
      end

      def rollback_one(version)
        stored = MigrationStore.fetch(version)

        if stored.nil?
          puts "[makimodoshi] WARNING: No stored rollback info for migration #{version}. Skipping."
          return false
        end

        migration_class = load_migration_class(stored["migration_source"], stored["filename"], version)

        puts "[makimodoshi] Rolling back #{version} (#{stored["filename"]})..."

        migration_instance = migration_class.new
        migration_instance.migrate(:down)

        remove_schema_migration(version)
        MigrationStore.remove(version)

        puts "[makimodoshi] Rolled back #{version}."
        true
      end

      private

      def load_migration_class(source, filename, version)
        # Evaluate the migration source in a clean context
        eval(source) # rubocop:disable Security/Eval

        # Extract class name from filename (e.g., "20240201000000_create_posts.rb" -> "CreatePosts")
        class_name = filename
          .sub(/\A\d+_/, "")
          .sub(/\.rb\z/, "")
          .camelize

        class_name.constantize
      end

      def remove_schema_migration(version)
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array(
            ["DELETE FROM schema_migrations WHERE version = ?", version]
          )
        )
      end
    end
  end
end
