# frozen_string_literal: true

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

if ENV["SOLIDUS_BRANCH"]
  gem "solidus", github: "solidusio/solidus", branch: ENV.fetch("SOLIDUS_BRANCH")
else
  gem "solidus", "~> #{ENV.fetch("SOLIDUS_VERSION", "4.8")}.0"
end

rails_series = ENV.fetch("RAILS_VERSION", "8.1")
unless %w[7.2 8.0 8.1].include?(rails_series)
  raise "Unsupported RAILS_VERSION=#{rails_series.inspect}; solidus_nexi supports Rails 7.2, 8.0, and 8.1"
end
rails_minimum = {"7.2" => "7.2.4", "8.0" => "8.0.5.1", "8.1" => "8.1.4"}.fetch(rails_series)
gem "rails", "~> #{rails_series}.0", ">= #{rails_minimum}"
case ENV.fetch("DB", "sqlite")
when "postgresql" then gem "pg", "~> 1.7", force_ruby_platform: true
when "mysql" then gem "mysql2"
when "sqlite" then gem "sqlite3", "~> 2.0"
else raise "Unsupported DB=#{ENV.fetch("DB").inspect}; choose sqlite, postgresql, or mysql"
end

gem "csv" if RUBY_VERSION >= "3.4"

gemspec
