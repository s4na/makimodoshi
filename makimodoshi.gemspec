# frozen_string_literal: true

require_relative "lib/makimodoshi/version"

Gem::Specification.new do |spec|
  spec.name = "makimodoshi"
  spec.version = Makimodoshi::VERSION
  spec.authors = ["s4na"]
  spec.summary = "Auto-rollback migrations when DB is ahead of schema.rb"
  spec.description = "A Rails gem that automatically rolls back migrations on server startup " \
                     "when the database state is ahead of schema.rb. Useful for branch switching " \
                     "during development."
  spec.homepage = "https://github.com/s4na/makimodoshi"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 2.7"

  spec.files = Dir["lib/**/*", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 6.1"
end
