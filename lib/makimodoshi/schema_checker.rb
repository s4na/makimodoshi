# frozen_string_literal: true

require "open3"

module Makimodoshi
  class SchemaChecker
    class << self
      def excess_versions
        schema_version = read_schema_version
        return [] unless schema_version

        db_versions = read_db_versions
        db_versions.select { |v| v > schema_version }.sort.reverse
      end

      # excess_versions のうち、マイグレーションファイルが存在しないものだけを返す。
      # ファイルが存在する = 通常の db:migrate 実行直後なのでロールバック不要。
      def orphan_versions
        excess_versions.reject { |v| migration_file_exists?(v) }
      end

      # 指定バージョンのマイグレーションファイルが db/migrate/ に存在するか
      def migration_file_exists?(version)
        Dir.glob(Rails.root.join("db", "migrate", "#{version}_*.rb")).any?
      end

      # schema.rb が git の HEAD と比較して変更されているか。
      # git管理外のプロジェクトでは false を返す（安全側に倒す）。
      def schema_file_changed_from_git?
        schema_file = Rails.root.join("db", "schema.rb")
        return false unless File.exist?(schema_file)

        diff = git_diff_schema
        !diff.nil? && !diff.strip.empty?
      end

      # git diff の実行を分離（テスト時にスタブしやすくする）
      def git_diff_schema
        output, status = Open3.capture2(
          "git", "-C", Rails.root.to_s, "diff", "HEAD", "--", "db/schema.rb",
          err: File::NULL
        )
        status.success? ? output : nil
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
