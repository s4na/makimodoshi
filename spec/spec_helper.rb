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
  end
end
