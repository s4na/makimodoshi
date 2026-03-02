# frozen_string_literal: true

require "spec_helper"
require "fileutils"

# Rails::Railtie のスタブ（テスト環境で Railtie をロードするため）
unless defined?(Rails::Railtie)
  module Rails
    class Railtie
      def self.rake_tasks(&block); end
      def self.initializer(_name, &block); end
      def self.config
        @config ||= Struct.new(:after_initialize).new
      end
    end
  end
end

require "makimodoshi/railtie"

# Railtie.auto_rollback! の統合テスト。
# SchemaChecker.check_auto_rollback_preconditions と Rollbacker をスタブし、
# auto_rollback! の条件分岐とログ出力を検証する。
RSpec.describe Makimodoshi::Railtie do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, debug: nil) }

  before do
    allow(Makimodoshi).to receive(:logger).and_return(logger)
  end

  describe ".auto_rollback!" do
    context "orphan_versions が空の場合" do
      before do
        allow(Makimodoshi::SchemaChecker).to receive(:check_auto_rollback_preconditions)
          .and_return([[], :no_orphans])
      end

      it "何もせずリターンする" do
        expect(Makimodoshi::Rollbacker).not_to receive(:rollback_versions)
        expect(logger).not_to receive(:info)
        described_class.auto_rollback!
      end
    end

    context "orphan がありだが schema.rb に git diff がない場合" do
      before do
        allow(Makimodoshi::SchemaChecker).to receive(:check_auto_rollback_preconditions)
          .and_return([["20240201000000"], :no_git_diff])
      end

      it "ロールバックせずスキップログを出す" do
        expect(Makimodoshi::Rollbacker).not_to receive(:rollback_versions)
        expect(logger).to receive(:info).with(/Orphan migrations found.*Skipping rollback/)
        described_class.auto_rollback!
      end
    end

    context "orphan があり schema.rb に git diff がある場合" do
      before do
        allow(Makimodoshi::SchemaChecker).to receive(:check_auto_rollback_preconditions)
          .and_return([["20240201000000"], nil])
      end

      it "ロールバックを実行し完了ログを出す" do
        expect(Makimodoshi::Rollbacker).to receive(:rollback_versions)
          .with(["20240201000000"]).and_return(true)
        expect(logger).to receive(:info).with(/orphan migration/).ordered
        expect(logger).to receive(:info).with(/Auto-rolling back/).ordered
        expect(logger).to receive(:info).with(/Auto-rollback complete/).ordered
        described_class.auto_rollback!
      end
    end

    context "ロールバックが部分的に失敗した場合" do
      before do
        allow(Makimodoshi::SchemaChecker).to receive(:check_auto_rollback_preconditions)
          .and_return([["20240201000000"], nil])
        allow(Makimodoshi::Rollbacker).to receive(:rollback_versions).and_return(false)
      end

      it "警告ログを出す" do
        expect(logger).to receive(:warn).with(/completed with errors/)
        described_class.auto_rollback!
      end
    end
  end
end
