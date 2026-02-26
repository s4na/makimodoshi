# frozen_string_literal: true

require "logger"
require "active_record"
require "makimodoshi"
require "makimodoshi/migration_store"
require "makimodoshi/schema_checker"
require "makimodoshi/rollbacker"
require "makimodoshi/migration_interceptor"

# Setup in-memory SQLite database for testing
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

# Create schema_migrations table
ActiveRecord::Base.connection.create_table(:schema_migrations, id: false) do |t|
  t.string :version, null: false
end
ActiveRecord::Base.connection.add_index(:schema_migrations, :version, unique: true)

# Stub Rails module for testing
unless defined?(Rails)
  module Rails
    class << self
      def env
        ActiveSupport::StringInquirer.new(ENV.fetch("RAILS_ENV", "development"))
      end

      def root
        Pathname.new(File.expand_path("../tmp", __dir__))
      end
    end
  end
end

RSpec.configure do |config|
  config.before(:each) do
    # Clean up tables before each test
    conn = ActiveRecord::Base.connection

    if conn.table_exists?(Makimodoshi::HIDDEN_TABLE_NAME)
      conn.execute("DELETE FROM #{Makimodoshi::HIDDEN_TABLE_NAME}")
    end

    conn.execute("DELETE FROM schema_migrations")

    # Reset ensure_table! cache so each test starts fresh
    Makimodoshi::MigrationStore.reset_table_cache!

    # Snapshot constants before each test for leak detection
    @constants_before = Object.constants.dup
  end

  config.after(:each) do
    # Clean up dynamically defined migration classes to prevent leaks between tests
    new_constants = Object.constants - @constants_before
    new_constants.each do |const_name|
      klass = Object.const_get(const_name)
      if klass.is_a?(Class) && klass < ActiveRecord::Migration
        Object.send(:remove_const, const_name)
      end
    rescue => e # rubocop:disable Lint/SuppressedException
    end
  end
end
