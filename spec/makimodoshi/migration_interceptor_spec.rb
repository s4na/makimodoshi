# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Makimodoshi::MigrationInterceptor do
  let(:migrate_dir) { Rails.root.join("db", "migrate") }

  before do
    FileUtils.mkdir_p(migrate_dir)
  end

  after do
    FileUtils.rm_rf(migrate_dir)
  end

  describe ".store_all_pending" do
    let(:migration_version) { "#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}" }
    let(:version) { "20240201000000" }
    let(:filename) { "20240201000000_create_users.rb" }
    let(:source) do
      <<~RUBY
        class CreateUsers < ActiveRecord::Migration[#{migration_version}]
          def change
            create_table :users do |t|
              t.string :name
              t.timestamps
            end
          end
        end
      RUBY
    end

    before do
      File.write(migrate_dir.join(filename), source)
    end

    it "stores pending migrations that exist in schema_migrations" do
      conn = ActiveRecord::Base.connection
      conn.execute(ActiveRecord::Base.sanitize_sql_array(
        ["INSERT INTO schema_migrations (version) VALUES (?)", version]
      ))

      described_class.store_all_pending

      expect(Makimodoshi::MigrationStore.exists?(version)).to be true
      stored = Makimodoshi::MigrationStore.fetch(version)
      expect(stored["filename"]).to eq(filename)
      expect(stored["migration_source"]).to eq(source)
    end

    it "skips migrations not in schema_migrations" do
      described_class.store_all_pending

      expect(Makimodoshi::MigrationStore.exists?(version)).to be false
    end

    it "skips already stored migrations" do
      conn = ActiveRecord::Base.connection
      conn.execute(ActiveRecord::Base.sanitize_sql_array(
        ["INSERT INTO schema_migrations (version) VALUES (?)", version]
      ))
      Makimodoshi::MigrationStore.store(version: version, filename: filename, source: "original")

      described_class.store_all_pending

      stored = Makimodoshi::MigrationStore.fetch(version)
      expect(stored["migration_source"]).to eq("original")
    end

    it "does nothing in non-development environment" do
      allow(Makimodoshi).to receive(:development?).and_return(false)

      conn = ActiveRecord::Base.connection
      conn.execute(ActiveRecord::Base.sanitize_sql_array(
        ["INSERT INTO schema_migrations (version) VALUES (?)", version]
      ))

      described_class.store_all_pending

      expect(Makimodoshi::MigrationStore.exists?(version)).to be false
    end
  end
end
