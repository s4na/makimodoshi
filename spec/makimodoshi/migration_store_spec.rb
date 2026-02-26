# frozen_string_literal: true

require "spec_helper"

RSpec.describe Makimodoshi::MigrationStore do
  let(:version) { "20240201000000" }
  let(:filename) { "20240201000000_create_posts.rb" }
  let(:source) do
    <<~RUBY
      class CreatePosts < ActiveRecord::Migration[7.0]
        def change
          create_table :posts do |t|
            t.string :title
            t.timestamps
          end
        end
      end
    RUBY
  end

  describe ".ensure_table!" do
    it "creates the hidden table if it does not exist" do
      conn = ActiveRecord::Base.connection
      conn.drop_table(Makimodoshi::HIDDEN_TABLE_NAME) if conn.table_exists?(Makimodoshi::HIDDEN_TABLE_NAME)

      described_class.ensure_table!

      expect(conn.table_exists?(Makimodoshi::HIDDEN_TABLE_NAME)).to be true
    end

    it "is idempotent" do
      described_class.ensure_table!
      expect { described_class.ensure_table! }.not_to raise_error
    end
  end

  describe ".store and .fetch" do
    it "stores and retrieves migration info" do
      described_class.store(version: version, filename: filename, source: source)

      result = described_class.fetch(version)

      expect(result["version"]).to eq(version)
      expect(result["filename"]).to eq(filename)
      expect(result["migration_source"]).to eq(source)
    end

    it "updates existing record on re-store" do
      described_class.store(version: version, filename: filename, source: source)
      described_class.store(version: version, filename: filename, source: "updated source")

      result = described_class.fetch(version)
      expect(result["migration_source"]).to eq("updated source")
    end
  end

  describe ".exists?" do
    it "returns false when version is not stored" do
      expect(described_class.exists?("99999999999999")).to be false
    end

    it "returns true when version is stored" do
      described_class.store(version: version, filename: filename, source: source)
      expect(described_class.exists?(version)).to be true
    end
  end

  describe ".all_stored" do
    it "returns all stored migrations ordered by version desc" do
      described_class.store(version: "20240101000000", filename: "20240101000000_first.rb", source: "first")
      described_class.store(version: "20240201000000", filename: "20240201000000_second.rb", source: "second")

      results = described_class.all_stored

      expect(results.size).to eq(2)
      expect(results.first["version"]).to eq("20240201000000")
      expect(results.last["version"]).to eq("20240101000000")
    end
  end

  describe ".remove" do
    it "removes stored migration info" do
      described_class.store(version: version, filename: filename, source: source)
      described_class.remove(version)

      expect(described_class.exists?(version)).to be false
    end
  end
end
