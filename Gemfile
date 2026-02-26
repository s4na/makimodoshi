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

  if rails_version
    rv = Gem::Version.new(rails_version)
    # Rails < 7.1 requires sqlite3 ~> 1.4 (incompatible with sqlite3 2.x)
    if rv < Gem::Version.new("7.1")
      gem "sqlite3", "~> 1.4"
    else
      gem "sqlite3"
    end
    # Rails 6.x has compatibility issues with logger gem >= 1.6
    if rv < Gem::Version.new("7.0")
      gem "logger", "< 1.6"
    end
  else
    gem "sqlite3"
  end
end
