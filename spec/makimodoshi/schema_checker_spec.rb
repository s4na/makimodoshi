# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Makimodoshi::SchemaChecker do
  let(:schema_dir) { Rails.root.join("db") }
  let(:schema_file) { schema_dir.join("schema.rb") }

  before do
    FileUtils.mkdir_p(schema_dir)
  end

  after do
    FileUtils.rm_f(schema_file)
  end

  describe ".read_schema_version" do
    it "reads version from schema.rb" do
      File.write(schema_file, <<~RUBY)
        ActiveRecord::Schema[7.0].define(version: 20240101000000) do
        end
      RUBY

      expect(described_class.read_schema_version).to eq("20240101000000")
    end

    it "reads version with underscores" do
      File.write(schema_file, <<~RUBY)
        ActiveRecord::Schema[7.0].define(version: 2024_01_01_000000) do
        end
      RUBY

      expect(described_class.read_schema_version).to eq("20240101000000")
    end

    it "returns nil when schema.rb does not exist" do
      FileUtils.rm_f(schema_file)
      expect(described_class.read_schema_version).to be_nil
    end
  end

  describe ".read_db_versions" do
    it "returns versions from schema_migrations table" do
      conn = ActiveRecord::Base.connection
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000000')")
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240201000000')")

      versions = described_class.read_db_versions
      expect(versions).to contain_exactly("20240101000000", "20240201000000")
    end
  end

  describe ".excess_versions" do
    before do
      File.write(schema_file, <<~RUBY)
        ActiveRecord::Schema[7.0].define(version: 20240101000000) do
        end
      RUBY
    end

    it "returns versions in DB that are ahead of schema.rb" do
      conn = ActiveRecord::Base.connection
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000000')")
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240201000000')")
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240301000000')")

      excess = described_class.excess_versions
      expect(excess).to eq(["20240301000000", "20240201000000"])
    end

    it "returns empty array when DB matches schema.rb" do
      conn = ActiveRecord::Base.connection
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000000')")

      expect(described_class.excess_versions).to be_empty
    end

    it "returns empty array when DB is behind schema.rb" do
      expect(described_class.excess_versions).to be_empty
    end
  end

  describe ".migration_file_exists?" do
    let(:migrate_dir) { Rails.root.join("db", "migrate") }

    before do
      FileUtils.mkdir_p(migrate_dir)
    end

    after do
      FileUtils.rm_rf(migrate_dir)
    end

    it "returns true when migration file exists" do
      File.write(migrate_dir.join("20240201000000_create_users.rb"), "")
      expect(described_class.migration_file_exists?("20240201000000")).to be true
    end

    it "returns false when migration file does not exist" do
      expect(described_class.migration_file_exists?("20240201000000")).to be false
    end
  end

  describe ".orphan_versions" do
    let(:migrate_dir) { Rails.root.join("db", "migrate") }

    before do
      FileUtils.mkdir_p(migrate_dir)
      File.write(schema_file, <<~RUBY)
        ActiveRecord::Schema[7.0].define(version: 20240101000000) do
        end
      RUBY

      conn = ActiveRecord::Base.connection
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000000')")
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240201000000')")
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('20240301000000')")
    end

    after do
      FileUtils.rm_rf(migrate_dir)
    end

    it "returns only excess versions without migration files" do
      # 20240201000000 にはファイルがある → orphanではない
      File.write(migrate_dir.join("20240201000000_create_users.rb"), "")

      orphans = described_class.orphan_versions
      expect(orphans).to eq(["20240301000000"])
    end

    it "returns empty when all excess versions have migration files" do
      File.write(migrate_dir.join("20240201000000_create_users.rb"), "")
      File.write(migrate_dir.join("20240301000000_add_email.rb"), "")

      expect(described_class.orphan_versions).to be_empty
    end

    it "returns all excess versions when none have migration files" do
      orphans = described_class.orphan_versions
      expect(orphans).to eq(["20240301000000", "20240201000000"])
    end
  end

  describe ".schema_file_changed_from_git?" do
    it "returns false when schema.rb does not exist" do
      FileUtils.rm_f(schema_file)
      expect(described_class.schema_file_changed_from_git?).to be false
    end

    it "returns false when git command fails (non-git directory)" do
      File.write(schema_file, "test")
      allow(described_class).to receive(:git_diff_schema).and_return(nil)
      expect(described_class.schema_file_changed_from_git?).to be false
    end

    it "returns false when schema.rb has no git diff" do
      File.write(schema_file, "test")
      allow(described_class).to receive(:git_diff_schema).and_return("")
      expect(described_class.schema_file_changed_from_git?).to be false
    end

    it "returns true when schema.rb has git diff" do
      File.write(schema_file, "test")
      allow(described_class).to receive(:git_diff_schema).and_return("diff --git a/db/schema.rb b/db/schema.rb\n...")
      expect(described_class.schema_file_changed_from_git?).to be true
    end
  end
end
