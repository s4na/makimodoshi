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

        # define(version: ...) は通常ファイル先頭数行にあるため、
        # 大規模 schema.rb でもファイル全体を読み込まない
        File.foreach(schema_file) do |line|
          match = line.match(/define\(version:\s*([\d_]+)\s*\)/)
          return match[1].delete("_") if match
        end

        nil
      end

      def read_db_versions
        return [] unless Makimodoshi.connection.table_exists?("schema_migrations")

        Makimodoshi.connection
          .select_values("SELECT version FROM schema_migrations")
          .map(&:to_s)
      end
    end
  end
end
