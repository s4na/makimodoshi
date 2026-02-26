# frozen_string_literal: true

require "spec_helper"

RSpec.describe Makimodoshi::Rollbacker do
  let(:migration_version) { "#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}" }
  let(:version) { "20240201000000" }
  let(:filename) { "20240201000000_create_posts.rb" }
  let(:source) do
    <<~RUBY
      class CreatePostsForTest < ActiveRecord::Migration[#{migration_version}]
        def up
          create_table :posts_for_test do |t|
            t.string :title
            t.timestamps
          end
        end

        def down
          drop_table :posts_for_test
        end
      end
    RUBY
  end

  before do
    conn = ActiveRecord::Base.connection

    # Insert into schema_migrations
    conn.execute("INSERT INTO schema_migrations (version) VALUES ('#{version}')")

    # Store migration info
    Makimodoshi::MigrationStore.store(version: version, filename: filename, source: source)

    # Actually create the table so down migration can drop it
    conn.create_table(:posts_for_test) do |t|
      t.string :title
      t.timestamps
    end
  end

  after do
    conn = ActiveRecord::Base.connection
    conn.drop_table(:posts_for_test) if conn.table_exists?(:posts_for_test)
  end

  describe ".rollback_one" do
    it "executes the down migration and removes records" do
      described_class.rollback_one(version)

      conn = ActiveRecord::Base.connection

      expect(conn.table_exists?(:posts_for_test)).to be false
      expect(conn.select_value("SELECT COUNT(*) FROM schema_migrations WHERE version = '#{version}'").to_i).to eq(0)
      expect(Makimodoshi::MigrationStore.exists?(version)).to be false
    end

    it "returns false when no stored info exists" do
      Makimodoshi::MigrationStore.remove(version)

      result = described_class.rollback_one(version)
      expect(result).to be false
    end

    it "returns false and logs error when rollback fails" do
      invalid_source = <<~RUBY
        class FailingMigration < ActiveRecord::Migration[#{migration_version}]
          def down
            raise "intentional failure"
          end
        end
      RUBY
      Makimodoshi::MigrationStore.store(version: version, filename: filename, source: invalid_source)

      result = described_class.rollback_one(version)
      expect(result).to be false
    end

    it "raises error for invalid migration source" do
      Makimodoshi::MigrationStore.store(version: version, filename: filename, source: "puts 'malicious code'")

      expect { described_class.rollback_one(version) }.to raise_error(RuntimeError, /Invalid migration source/)
    end
  end

  describe ".rollback_versions" do
    it "rolls back multiple versions in order" do
      version2 = "20240301000000"
      filename2 = "20240301000000_create_comments_for_test.rb"
      source2 = <<~RUBY
        class CreateCommentsForTest < ActiveRecord::Migration[#{migration_version}]
          def up
            create_table :comments_for_test do |t|
              t.string :body
              t.timestamps
            end
          end

          def down
            drop_table :comments_for_test
          end
        end
      RUBY

      conn = ActiveRecord::Base.connection
      conn.execute("INSERT INTO schema_migrations (version) VALUES ('#{version2}')")
      Makimodoshi::MigrationStore.store(version: version2, filename: filename2, source: source2)
      conn.create_table(:comments_for_test) do |t|
        t.string :body
        t.timestamps
      end

      described_class.rollback_versions([version2, version])

      expect(conn.table_exists?(:posts_for_test)).to be false
      expect(conn.table_exists?(:comments_for_test)).to be false
    end
  end
end
