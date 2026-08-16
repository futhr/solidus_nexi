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
  add_filter %r{^/lib/generators/.*/install/install_generator.rb}
  add_filter %r{^/lib/.*/factories.rb}
  add_filter %r{^/lib/.*/version.rb}
end

dummy_environment = "#{__dir__}/dummy/config/environment.rb"
system("bin/rake", "extension:test_app") unless File.exist?(dummy_environment)
require dummy_environment

require "solidus_dev_support/rspec/feature_helper"
require "webmock/rspec"

Dir["#{__dir__}/support/**/*.rb"].sort.each { |file| require file }

SolidusDevSupport::TestingSupport::Factories.load_for(SolidusNexi::Engine)

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.use_transactional_fixtures = true
  config.include ActiveJob::TestHelper

  config.before do
    ActiveJob::Base.queue_adapter = :test
    SolidusNexi.reset_configuration!
  end
end
