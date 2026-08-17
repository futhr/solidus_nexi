# frozen_string_literal: true

require_relative "dev/load_env"
require "bundler/gem_tasks"
require "solidus_dev_support/rake_tasks"

SolidusDevSupport::RakeTasks.install

task default: "extension:specs"
