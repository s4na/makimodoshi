# frozen_string_literal: true

module Makimodoshi
  class MigrationInterceptor
    class << self
      def store_all_pending
        return unless Makimodoshi.development?

        migration_files = Dir[Rails.root.join("db", "migrate", "*.rb")]
        db_versions = SchemaChecker.read_db_versions

        migration_files.each do |filepath|
          filename = File.basename(filepath)
          version = filename.match(/\A(\d+)_/).to_a[1]
          next unless version
          next unless db_versions.include?(version)
          next if MigrationStore.exists?(version)

          source = File.read(filepath)
          MigrationStore.store(version: version, filename: filename, source: source)
        end
      end
    end
  end
end
