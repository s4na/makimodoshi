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
end
