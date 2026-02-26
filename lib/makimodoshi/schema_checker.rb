# frozen_string_literal: true

module Makimodoshi
  class SchemaChecker
    class << self
      def excess_versions
        schema_version = read_schema_version
        return [] unless schema_version

        db_versions = read_db_versions
        db_versions.select { |v| v > schema_version }.sort.reverse
      end

      def read_schema_version
        schema_file = Rails.root.join("db", "schema.rb")
        return nil unless File.exist?(schema_file)

        content = File.read(schema_file)
        match = content.match(/define\(version:\s*(\d+)(?:_\d+)*\s*\)/)
        match ||= content.match(/define\(version:\s*(\d[\d_]*\d)\s*\)/)

        return nil unless match

        match[1].delete("_")
      end

      def read_db_versions
        return [] unless ActiveRecord::Base.connection.table_exists?("schema_migrations")

        ActiveRecord::Base.connection
          .select_values("SELECT version FROM schema_migrations")
          .map(&:to_s)
      end
    end
  end
end
