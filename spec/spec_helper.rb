# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
ENV["SOLIDUS_PREFERENCES_MASTER_KEY"] ||= "0123456789abcdef0123456789abcdef"

require "simplecov"
if ENV["CI"]
  require "simplecov-lcov"
  SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
  SimpleCov::Formatter::LcovFormatter.config.lcov_file_name = "lcov.info"
  SimpleCov.formatter = SimpleCov::Formatter::LcovFormatter
end
SimpleCov.start("rails") do
  enable_coverage :branch
  if ENV["CI"]
    minimum_coverage line: 94, branch: 72
    minimum_coverage_by_file 80
  end
  add_filter %r{/lib/.*/factories.rb}
  add_filter %r{/lib/.*/version.rb}
end

require_relative "../dev/load_env"

dummy_environment = "#{__dir__}/dummy/config/environment.rb"
system("bin/rake", "extension:test_app") unless File.exist?(dummy_environment)
require dummy_environment

require "solidus_dev_support/rspec/feature_helper"
require "webmock/rspec"

Dir["#{__dir__}/support/**/*.rb"].sort.each { |file| require file }

SolidusDevSupport::TestingSupport::Factories.load_for(SolidusNexi::Engine)

RSpec.configure do |config|
  unless ENV["NEXI_TEST_ENVIRONMENT"] == "1"
    config.filter_run_excluding nexi_test_environment: true
  end

  config.infer_spec_type_from_file_location!
  config.use_transactional_fixtures = true
  config.include ActiveJob::TestHelper

  config.before do
    ActiveJob::Base.queue_adapter = :test
    SolidusNexi.reset_configuration!
  end

  config.before(:each, :nexi_test_environment) do
    unless ENV["NEXI_CHECKOUT_ENVIRONMENT"] == "test"
      raise "Provider specs are restricted to NEXI_CHECKOUT_ENVIRONMENT=test"
    end
    SolidusNexi::DevelopmentEnvironment.validate!

    WebMock.allow_net_connect!
  end

  config.after(:each, :nexi_test_environment) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end
