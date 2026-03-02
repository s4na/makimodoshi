# frozen_string_literal: true

require "open3"

module Makimodoshi
  class SchemaChecker
    class << self
      # 自動ロールバックの前提条件チェック。
      # 戻り値: [orphans, reason]
      #   - 条件を満たす場合: [orphan_versions の配列, nil]
      #   - orphan なし: [[], :no_orphans]
      #   - git diff なし: [orphan_versions の配列, :no_git_diff]
      #
      # orphans は reason が :no_git_diff の場合もログ出力用に返される。
      def check_auto_rollback_preconditions
        orphans = orphan_versions
        return [orphans, :no_orphans] if orphans.empty?
        return [orphans, :no_git_diff] unless schema_file_changed_from_git?

        [orphans, nil]
      end

      # excess_versions のうち、マイグレーションファイルが存在しないものだけを返す。
      # ファイルが存在する = 通常の db:migrate 実行直後なのでロールバック不要。
      def orphan_versions
        excess_versions.reject { |v| migration_file_exists?(v) }
      end

      # 指定バージョンのマイグレーションファイルが db/migrate/ に存在するか
      def migration_file_exists?(version)
        raise ArgumentError, "version must be a numeric string" unless version.to_s.match?(/\A\d+\z/)

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
      #
      # `git diff HEAD` はワーキングツリーと HEAD の差分を比較する。
      # ブランチ切り替え直後は HEAD が切り替え先ブランチを指すため、
      # 切り替え先の schema.rb と HEAD が一致し diff が空になる場合がある。
      #
      # 例: ブランチ A で migration 実行後、git checkout branch-B すると、
      #   - schema.rb は branch-B のものに切り替わる
      #   - git diff HEAD は空（HEAD = branch-B）
      #   - orphan migration は検出されるが、git diff がないためロールバックされない
      #   - ユーザーが `rails makimodoshi:rollback` を手動実行するか、
      #     schema.rb が別途変更されるまで orphan は残り続ける
      #
      # この挙動は意図的で、ブランチ切り替え直後に意図しないロールバックが
      # 走ることを防いでいる。手動コマンドでは git diff チェックを省略するため、
      # ユーザーは必要に応じて明示的にロールバックできる。
      def git_diff_schema
        output, status = Open3.capture2(
          "git", "-C", Rails.root.to_s, "diff", "HEAD", "--", "db/schema.rb",
          err: File::NULL # git管理外ディレクトリでのエラーメッセージを抑制
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

      private

      # schema.rb のバージョンより新しい DB バージョンを返す（内部用）。
      # 外部からは orphan_versions を使うこと。
      def excess_versions
        schema_version = read_schema_version
        return [] unless schema_version

        db_versions = read_db_versions
        db_versions.select { |v| v > schema_version }.sort.reverse
      end
    end
  end
end
