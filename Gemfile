# frozen_string_literal: true

source "https://rubygems.org"

gemspec

rails_version = ENV.fetch("RAILS_VERSION", nil)
if rails_version
  gem "rails", "~> #{rails_version}.0"
end

group :development, :test do
  gem "rspec", "~> 3.0"
  gem "rake", "~> 13.0"
  gem "sqlite3"
end
