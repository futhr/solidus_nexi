# frozen_string_literal: true

require_relative "lib/solidus_nexi/version"

Gem::Specification.new do |spec|
  spec.name = "solidus_nexi"
  spec.version = SolidusNexi::VERSION
  spec.authors = ["Tobias Bohwalli", "FreeRunning Technologies"]
  spec.email = ["hi@futhr.io"]

  spec.summary = "Nexi Checkout payment integration for Solidus"
  spec.description = "A Solidus-native Nexi Checkout adapter with durable idempotency, authenticated webhooks, and payment reconciliation."
  spec.homepage = "https://github.com/futhr/solidus-nexi"
  spec.license = "BSD-3-Clause"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.required_ruby_version = Gem::Requirement.new(">= 3.2")

  files = Dir.glob("{app,config,db,docs,lib}/**/*", File::FNM_DOTMATCH).select { |path| File.file?(path) }
  spec.files = files + %w[CHANGELOG.md LICENSE.md README.md SECURITY.md]
  spec.require_paths = ["lib"]

  spec.add_dependency "solidus_core", ">= 4.6", "< 5"
  spec.add_dependency "solidus_support", ">= 0.12"

  spec.add_development_dependency "solidus_dev_support"
  spec.add_development_dependency "simplecov-lcov", "~> 0.9"
  spec.add_development_dependency "webmock", "~> 3.24"
end
