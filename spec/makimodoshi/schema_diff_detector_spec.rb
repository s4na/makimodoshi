# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Makimodoshi::SchemaDiffDetector do
  let(:schema_dir) { Rails.root.join("db") }
  let(:schema_file) { schema_dir.join("schema.rb") }

  before do
    FileUtils.mkdir_p(schema_dir)
    ActiveRecord::SchemaDumper.ignore_tables << Makimodoshi::HIDDEN_TABLE_NAME unless
      ActiveRecord::SchemaDumper.ignore_tables.include?(Makimodoshi::HIDDEN_TABLE_NAME)
  end

  after do
    FileUtils.rm_f(schema_file)
    conn = ActiveRecord::Base.connection
    conn.drop_table(:diff_test_posts) if conn.table_exists?(:diff_test_posts)
  end

  describe ".schema_matches?" do
    it "returns true when schema.rb does not exist" do
      FileUtils.rm_f(schema_file)
      expect(described_class.schema_matches?).to be true
    end

    it "returns true when DB schema matches schema.rb" do
      # DB の現在の状態をダンプして schema.rb に書き込む
      current_schema = described_class.dump_current_schema
      File.write(schema_file, current_schema)

      expect(described_class.schema_matches?).to be true
    end

    it "returns false when DB has extra tables not in schema.rb" do
      # まず現在の状態で schema.rb を生成
      current_schema = described_class.dump_current_schema
      File.write(schema_file, current_schema)

      # テーブルを追加して DB を変更
      ActiveRecord::Base.connection.create_table(:diff_test_posts) do |t|
        t.string :title
      end

      expect(described_class.schema_matches?).to be false
    end

    it "returns false when DB is missing tables present in schema.rb" do
      # テーブルがある状態でスキーマを書き出す
      ActiveRecord::Base.connection.create_table(:diff_test_posts) do |t|
        t.string :title
      end
      current_schema = described_class.dump_current_schema
      File.write(schema_file, current_schema)

      # テーブルを削除して DB を変更
      ActiveRecord::Base.connection.drop_table(:diff_test_posts)

      expect(described_class.schema_matches?).to be false
    end

    it "ignores comment-only differences" do
      current_schema = described_class.dump_current_schema
      # コメントを追加しても差分なしと判定
      schema_with_extra_comments = "# Extra comment\n" + current_schema
      File.write(schema_file, schema_with_extra_comments)

      expect(described_class.schema_matches?).to be true
    end
  end

  describe ".dump_current_schema" do
    it "returns a string containing ActiveRecord::Schema" do
      schema = described_class.dump_current_schema
      expect(schema).to include("ActiveRecord::Schema")
    end

    it "excludes the hidden makimodoshi table" do
      Makimodoshi::MigrationStore.ensure_table!
      schema = described_class.dump_current_schema
      expect(schema).not_to include(Makimodoshi::HIDDEN_TABLE_NAME)
    end
  end

  describe ".read_schema_file" do
    it "returns file contents when schema.rb exists" do
      File.write(schema_file, "test content")
      expect(described_class.read_schema_file).to eq("test content")
    end

    it "returns nil when schema.rb does not exist" do
      FileUtils.rm_f(schema_file)
      expect(described_class.read_schema_file).to be_nil
    end
  end
end
