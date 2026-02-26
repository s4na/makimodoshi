# frozen_string_literal: true

require_relative "makimodoshi/version"
require_relative "makimodoshi/railtie" if defined?(Rails::Railtie)

module Makimodoshi
  HIDDEN_TABLE_NAME = "_makimodoshi_migrations"

  class << self
    def development?
      Rails.env.development?
    end
  end
end
