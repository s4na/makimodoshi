# frozen_string_literal: true

require "spec_helper"
require "fileutils"

# auto_rollback! の判定ロジック should_auto_rollback? をテストする。
# should_auto_rollback? は SchemaChecker に定義されており、
# Railtie.auto_rollback! から呼び出される。
RSpec.describe "Makimodoshi::SchemaChecker.should_auto_rollback?" do
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

  context "excess versions があるがすべてマイグレーションファイルが存在する場合" do
    before do
      conn = ActiveRecord::Base.connection
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000000')")
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240201000000')")
      File.write(migrate_dir.join("20240201000000_create_users.rb"), "")
    end

    it "nil を返す（ロールバック不要）" do
      expect(Makimodoshi::SchemaChecker.should_auto_rollback?).to be_nil
    end
  end

  context "orphan migrations があるが schema.rb に git diff がない場合" do
    before do
      conn = ActiveRecord::Base.connection
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000000')")
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240201000000')")
      allow(Makimodoshi::SchemaChecker).to receive(:git_diff_schema).and_return("")
    end

    it "nil を返す（ロールバック不要）" do
      expect(Makimodoshi::SchemaChecker.should_auto_rollback?).to be_nil
    end
  end

  context "orphan migrations があり schema.rb に git diff がある場合" do
    before do
      conn = ActiveRecord::Base.connection
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000000')")
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240201000000')")
      allow(Makimodoshi::SchemaChecker).to receive(:git_diff_schema).and_return("diff --git ...")
    end

    it "orphan versions を返す（ロールバック対象）" do
      result = Makimodoshi::SchemaChecker.should_auto_rollback?
      expect(result).to eq(["20240201000000"])
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

    it "orphan のみを返す" do
      result = Makimodoshi::SchemaChecker.should_auto_rollback?
      expect(result).to eq(["20240301000000"])
    end
  end
end
