# frozen_string_literal: true

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

solidus_branch = ENV.fetch("SOLIDUS_BRANCH", "v4.7")
gem "solidus", github: "solidusio/solidus", branch: solidus_branch

rails_series = ENV.fetch("RAILS_VERSION", "7.2")
unless rails_series == "7.2"
  raise "Unsupported RAILS_VERSION=#{rails_series.inspect}; solidus_nexi requires the maintained Rails 7.2 line"
end
rails_requirement = (rails_series.count(".") == 1) ? "~> #{rails_series}.0" : "~> #{rails_series}"
gem "rails", rails_requirement, ">= 7.2.3.2"
case ENV.fetch("DB", "sqlite")
when "postgresql" then gem "pg"
when "mysql" then gem "mysql2"
else
  sqlite_requirement = (Gem::Version.new(rails_series) < Gem::Version.new("7.2")) ? "~> 1.4" : "~> 2.0"
  gem "sqlite3", sqlite_requirement
end

gem "csv" if RUBY_VERSION >= "3.4"

gemspec
