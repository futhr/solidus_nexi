# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
ENV["SOLIDUS_PREFERENCES_MASTER_KEY"] ||= "0123456789abcdef0123456789abcdef"

require "solidus_dev_support/rspec/coverage"

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
