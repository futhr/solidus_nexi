# frozen_string_literal: true

require_relative "dev/load_env"
require "bundler/gem_tasks"
require "solidus_dev_support/rake_tasks"

SolidusDevSupport::RakeTasks.install

Rake::Task["release"].clear
desc "Disabled: follow docs/releasing.md after explicit release approval"
# This guard must run before loading a host application.
# rubocop:disable Rails/RakeEnvironment
task :release do
  raise "Automatic release is disabled; follow docs/releasing.md after explicit approval"
end
# rubocop:enable Rails/RakeEnvironment

task default: "extension:specs"
