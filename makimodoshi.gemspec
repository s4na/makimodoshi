# frozen_string_literal: true

require_relative "lib/makimodoshi/version"

Gem::Specification.new do |spec|
  spec.name = "makimodoshi"
  spec.version = Makimodoshi::VERSION
  spec.authors = ["s4na"]
  spec.summary = "Rollback orphaned Rails migrations after branch switches"
  spec.description = "A Rails gem that stores migration source code and helps roll back " \
                     "orphaned migrations after branch switches during development."
  spec.homepage = "https://github.com/s4na/makimodoshi"
  spec.license = "MIT"

  spec.metadata = {
    "source_code_uri" => "https://github.com/s4na/makimodoshi",
    "bug_tracker_uri" => "https://github.com/s4na/makimodoshi/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir["lib/**/*", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 6.1"
end
