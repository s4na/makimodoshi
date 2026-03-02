# frozen_string_literal: true

require "spec_helper"
require "fileutils"

# Railtie のクラスメソッドのみテストする（Rails 初期化フックは対象外）
RSpec.describe "Makimodoshi::Railtie.auto_rollback!" do
  # Railtie クラスを定義していない環境でもテストできるよう、
  # auto_rollback! ロジックを直接呼び出す形でテストする
  let(:schema_dir) { Rails.root.join("db") }
  let(:schema_file) { schema_dir.join("schema.rb") }
  let(:migrate_dir) { Rails.root.join("db", "migrate") }

  before do
    FileUtils.mkdir_p(schema_dir)
    FileUtils.mkdir_p(migrate_dir)
    File.write(schema_file, <<~RUBY)
      ActiveRecord::Schema[7.0].define(version: 20240101000000) do
      end
    RUBY
  end

  after do
    FileUtils.rm_f(schema_file)
    FileUtils.rm_rf(migrate_dir)
  end

  # auto_rollback! のロジックを再現するヘルパー
  #
  # 制約: Railtie 本体は Rails::Railtie 継承が必要であり、テスト環境での
  # 完全な初期化が困難なため、ロジックだけ抽出してテストしている。
  # auto_rollback! 本体のロジックを変更した場合は、このヘルパーも
  # 必ず同期して更新すること。
  # TODO: Railtie の初期化なしに auto_rollback! を直接呼び出せる構成への
  #       リファクタリングを検討する。
  def auto_rollback_logic
    orphans = Makimodoshi::SchemaChecker.orphan_versions
    return :no_orphans if orphans.empty?

    unless Makimodoshi::SchemaChecker.schema_file_changed_from_git?
      return :no_git_diff
    end

    :should_rollback
  end

  context "excess versions があるがすべてマイグレーションファイルが存在する場合" do
    before do
      conn = ActiveRecord::Base.connection
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000000')")
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240201000000')")
      File.write(migrate_dir.join("20240201000000_create_users.rb"), "")
    end

    it "ロールバックしない" do
      expect(auto_rollback_logic).to eq(:no_orphans)
    end
  end

  context "orphan migrations があるが schema.rb に git diff がない場合" do
    before do
      conn = ActiveRecord::Base.connection
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000000')")
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240201000000')")
      allow(Makimodoshi::SchemaChecker).to receive(:git_diff_schema).and_return("")
    end

    it "ロールバックしない" do
      expect(auto_rollback_logic).to eq(:no_git_diff)
    end
  end

  context "orphan migrations があり schema.rb に git diff がある場合" do
    before do
      conn = ActiveRecord::Base.connection
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000000')")
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240201000000')")
      allow(Makimodoshi::SchemaChecker).to receive(:git_diff_schema).and_return("diff --git ...")
    end

    it "ロールバックすべきと判定する" do
      expect(auto_rollback_logic).to eq(:should_rollback)
    end
  end

  context "excess versions のうち一部のみ orphan の場合" do
    before do
      conn = ActiveRecord::Base.connection
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000000')")
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240201000000')")
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240301000000')")
      # 20240201000000 にはファイルがある（通常のマイグレーション）
      File.write(migrate_dir.join("20240201000000_create_users.rb"), "")
      # 20240301000000 にはファイルがない（orphan）
      allow(Makimodoshi::SchemaChecker).to receive(:git_diff_schema).and_return("diff --git ...")
    end

    it "orphan のみがロールバック対象になる" do
      orphans = Makimodoshi::SchemaChecker.orphan_versions
      expect(orphans).to eq(["20240301000000"])
      expect(auto_rollback_logic).to eq(:should_rollback)
    end
  end
end
