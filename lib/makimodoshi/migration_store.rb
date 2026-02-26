# frozen_string_literal: true

module Makimodoshi
  class MigrationStore
    class << self
      def ensure_table!
        return if connection.table_exists?(HIDDEN_TABLE_NAME)

        connection.create_table(HIDDEN_TABLE_NAME, id: false) do |t|
          t.string :version, null: false
          t.text :migration_source, null: false
          t.string :filename, null: false
          t.datetime :migrated_at, null: false
        end

        connection.add_index(HIDDEN_TABLE_NAME, :version, unique: true)
      end

      def store(version:, filename:, source:)
        ensure_table!

        if exists?(version)
          connection.execute(
            sanitize(
              "UPDATE #{HIDDEN_TABLE_NAME} SET migration_source = ?, filename = ?, migrated_at = ? WHERE version = ?",
              source, filename, Time.now.utc, version
            )
          )
        else
          connection.execute(
            sanitize(
              "INSERT INTO #{HIDDEN_TABLE_NAME} (version, migration_source, filename, migrated_at) VALUES (?, ?, ?, ?)",
              version, source, filename, Time.now.utc
            )
          )
        end
      end

      def fetch(version)
        ensure_table!

        result = connection.select_one(
          sanitize("SELECT * FROM #{HIDDEN_TABLE_NAME} WHERE version = ?", version)
        )
        result
      end

      def exists?(version)
        ensure_table!

        count = connection.select_value(
          sanitize("SELECT COUNT(*) FROM #{HIDDEN_TABLE_NAME} WHERE version = ?", version)
        )
        count.to_i > 0
      end

      def all_stored
        ensure_table!

        connection.select_all(
          "SELECT version, filename, migrated_at FROM #{HIDDEN_TABLE_NAME} ORDER BY version DESC"
        ).to_a
      end

      def remove(version)
        ensure_table!

        connection.execute(
          sanitize("DELETE FROM #{HIDDEN_TABLE_NAME} WHERE version = ?", version)
        )
      end

      private

      def connection
        ActiveRecord::Base.connection
      end

      def sanitize(sql, *binds)
        ActiveRecord::Base.sanitize_sql_array([sql, *binds])
      end
    end
  end
end
