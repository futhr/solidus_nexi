# frozen_string_literal: true

module SolidusNexi
  module Generators
    class InstallGenerator < Rails::Generators::Base
      class_option :auto_run_migrations, type: :boolean, default: false
      source_root File.expand_path("templates", __dir__)

      def self.exit_on_failure?
        true
      end

      def copy_initializer
        template "initializer.rb", "config/initializers/solidus_nexi.rb"
      end

      def mount_engine
        route "mount SolidusNexi::Engine, at: '/solidus_nexi'"
      end

      def add_migrations
        run "bin/rails railties:install:migrations FROM=solidus_nexi"
      end

      def run_migrations
        should_run = options[:auto_run_migrations] || ["", "y", "Y"].include?(ask("Run migrations now? [Y/n]"))
        should_run ? run("bin/rails db:migrate") : say("Run bin/rails db:migrate before enabling Nexi Checkout.")
      end
    end
  end
end
