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
    conn.execute(ActiveRecord::Base.sanitize_sql_array(
      ["INSERT INTO schema_migrations (version) VALUES (?)", version]
    ))

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
    conn.drop_table(:posts_for_test_v2) if conn.table_exists?(:posts_for_test_v2)
  end

  describe ".rollback_one" do
    it "executes the down migration and removes records" do
      described_class.rollback_one(version)

      conn = ActiveRecord::Base.connection

      expect(conn.table_exists?(:posts_for_test)).to be false
      expect(conn.select_value(ActiveRecord::Base.sanitize_sql_array(
        ["SELECT COUNT(*) FROM schema_migrations WHERE version = ?", version]
      )).to_i).to eq(0)
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

      expect(Makimodoshi.logger).to receive(:error).at_least(:once)
      result = described_class.rollback_one(version)
      expect(result).to be false
    end

    it "raises InvalidMigrationSourceError for invalid migration source" do
      Makimodoshi::MigrationStore.store(version: version, filename: filename, source: "puts 'malicious code'")

      expect { described_class.rollback_one(version) }.to raise_error(Makimodoshi::InvalidMigrationSourceError)
    end

    it "raises InvalidMigrationSourceError for dangerous method calls in class body" do
      dangerous_source = <<~RUBY
        class DangerousMigration < ActiveRecord::Migration[#{migration_version}]
          system("echo pwned")
          def down; end
        end
      RUBY
      Makimodoshi::MigrationStore.store(version: version, filename: filename, source: dangerous_source)

      expect { described_class.rollback_one(version) }.to raise_error(Makimodoshi::InvalidMigrationSourceError, /dangerous method calls/)
    end

    it "handles class name collision by reloading from correct source" do
      # Create a second migration with the same class name but different behavior
      version2 = "20240301000000"
      filename2 = "20240301000000_create_posts_for_test.rb"
      source2 = <<~RUBY
        class CreatePostsForTest < ActiveRecord::Migration[#{migration_version}]
          def up
            create_table :posts_for_test_v2 do |t|
              t.string :title
              t.timestamps
            end
          end

          def down
            drop_table :posts_for_test_v2
          end
        end
      RUBY

      conn = ActiveRecord::Base.connection
      conn.execute(ActiveRecord::Base.sanitize_sql_array(
        ["INSERT INTO schema_migrations (version) VALUES (?)", version2]
      ))
      Makimodoshi::MigrationStore.store(version: version2, filename: filename2, source: source2)
      conn.create_table(:posts_for_test_v2) do |t|
        t.string :title
        t.timestamps
      end

      # Rollback the first version (which defines CreatePostsForTest)
      described_class.rollback_one(version)
      expect(conn.table_exists?(:posts_for_test)).to be false

      # Now rollback the second version (same class name, different behavior)
      # This should reload the class with the new source, not use the old definition
      described_class.rollback_one(version2)
      expect(conn.table_exists?(:posts_for_test_v2)).to be false
    end

    it "raises InvalidMigrationSourceError for code after class definition" do
      malicious_source = <<~RUBY
        class TrojanMigration < ActiveRecord::Migration[#{migration_version}]
          def down; end
        end
        system("echo pwned")
      RUBY
      Makimodoshi::MigrationStore.store(version: version, filename: filename, source: malicious_source)

      expect { described_class.rollback_one(version) }.to raise_error(Makimodoshi::InvalidMigrationSourceError, /contains code after class definition/)
    end
  end

  describe ".rollback_versions" do
    it "rolls back multiple versions in order and returns true on success" do
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
      conn.execute(ActiveRecord::Base.sanitize_sql_array(
        ["INSERT INTO schema_migrations (version) VALUES (?)", version2]
      ))
      Makimodoshi::MigrationStore.store(version: version2, filename: filename2, source: source2)
      conn.create_table(:comments_for_test) do |t|
        t.string :body
        t.timestamps
      end

      result = described_class.rollback_versions([version2, version])

      expect(result).to be true
      expect(conn.table_exists?(:posts_for_test)).to be false
      expect(conn.table_exists?(:comments_for_test)).to be false
    end

    it "returns false when any rollback fails" do
      failing_version = "20240301000000"
      failing_filename = "20240301000000_failing.rb"
      failing_source = <<~RUBY
        class PartialFailMigration < ActiveRecord::Migration[#{migration_version}]
          def down
            raise "intentional failure"
          end
        end
      RUBY

      conn = ActiveRecord::Base.connection
      conn.execute(ActiveRecord::Base.sanitize_sql_array(
        ["INSERT INTO schema_migrations (version) VALUES (?)", failing_version]
      ))
      Makimodoshi::MigrationStore.store(version: failing_version, filename: failing_filename, source: failing_source)

      result = described_class.rollback_versions([failing_version, version])

      expect(result).to be false
      # map ensures all versions are attempted even after failure;
      # verify the second (valid) rollback still executed successfully
      expect(conn.table_exists?(:posts_for_test)).to be false
      expect(Makimodoshi::MigrationStore.exists?(version)).to be false
    end
  end
end
