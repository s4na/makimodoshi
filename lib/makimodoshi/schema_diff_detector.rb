# frozen_string_literal: true

require "stringio"

module Makimodoshi
  class SchemaDiffDetector
    class << self
      def schema_matches?
        on_disk = read_schema_file
        return true unless on_disk

        from_db = dump_current_schema
        normalize(on_disk) == normalize(from_db)
      end

      def dump_current_schema
        # Railtie が設定済みのはずだが、rake タスク単独実行時にも
        # 隠しテーブルを除外するための防御的チェック
        unless ActiveRecord::SchemaDumper.ignore_tables.include?(HIDDEN_TABLE_NAME)
          ActiveRecord::SchemaDumper.ignore_tables << HIDDEN_TABLE_NAME
        end

        stream = StringIO.new
        # Rails 7.2+ では SchemaDumper.dump の第一引数が connection から
        # connection_pool に変更された
        if pool_based_schema_dumper?
          ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
        else
          ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, stream)
        end
        stream.string
      end

      def read_schema_file
        schema_file = Rails.root.join("db", "schema.rb")
        return nil unless File.exist?(schema_file)

        File.read(schema_file)
      end

      private

      def pool_based_schema_dumper?
        ActiveRecord::VERSION::MAJOR >= 8 ||
          (ActiveRecord::VERSION::MAJOR == 7 && ActiveRecord::VERSION::MINOR >= 2)
      end

      def normalize(schema)
        schema
          .lines
          .reject { |line| line.strip.start_with?("#") || line.strip.empty? }
          .map(&:rstrip)
          .join("\n")
      end
    end
  end
end
