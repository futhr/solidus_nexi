# frozen_string_literal: true

require_relative "lib/solidus_nexi/version"

Gem::Specification.new do |spec|
  spec.name = "solidus_nexi"
  spec.version = SolidusNexi::VERSION
  spec.authors = ["Tobias Bohwalli"]
  spec.email = ["hi@futhr.io"]

  spec.summary = "Nexi Checkout payment integration for Solidus"
  spec.description = "A Solidus-native Nexi Checkout adapter with durable idempotency, authenticated webhooks, and payment reconciliation."
  spec.homepage = "https://github.com/futhr/solidus_nexi"
  spec.license = "BSD-3-Clause"

  release_source_uri = "#{spec.homepage}/tree/v#{spec.version}"
  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/blob/v#{spec.version}/CHANGELOG.md",
    "documentation_uri" => "#{release_source_uri}#readme",
    "homepage_uri" => spec.homepage,
    "rubygems_mfa_required" => "true",
    "source_code_uri" => release_source_uri
  }

  spec.required_ruby_version = Gem::Requirement.new(">= 3.2")

  files = Dir.glob("{app,config,db,docs,lib}/**/*", File::FNM_DOTMATCH).select { |path| File.file?(path) }
  spec.files = (files + %w[CHANGELOG.md CONTRIBUTING.md LICENSE.md README.md SECURITY.md]).sort
  spec.require_paths = ["lib"]

  spec.add_dependency "solidus_core", ">= 4.6", "< 5"
  spec.add_dependency "solidus_support", ">= 0.12", "< 1"
  spec.add_dependency "railties", ">= 7.2.3.2", "< 7.3"

  spec.add_development_dependency "solidus_dev_support", "~> 2.12"
  spec.add_development_dependency "bundler-audit", "~> 0.9"
  spec.add_development_dependency "dotenv", "~> 3.1"
  spec.add_development_dependency "faraday-retry", "~> 2.4"
  spec.add_development_dependency "rubocop-rails", "~> 2.33"
  spec.add_development_dependency "simplecov-lcov", "~> 0.9"
  spec.add_development_dependency "webmock", "~> 3.24"
end
