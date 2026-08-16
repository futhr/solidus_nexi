# frozen_string_literal: true

require "solidus_core"
require "solidus_support"

module SolidusNexi
  class Engine < Rails::Engine
    include SolidusSupport::EngineExtensions

    isolate_namespace SolidusNexi
    engine_name "solidus_nexi"

    initializer "solidus_nexi.add_payment_method", after: "spree.register.payment_methods" do |app|
      app.config.spree.payment_methods << "SolidusNexi::PaymentMethod"
    end

    initializer "solidus_nexi.filter_parameters" do |app|
      app.config.filter_parameters += %i[api_key authorization webhook_secret previous_webhook_secret]
    end

    config.to_prepare do
      unless Spree::Payment < SolidusNexi::PaymentProcessing
        Spree::Payment.prepend(SolidusNexi::PaymentProcessing)
      end
    end

    config.generators do |generator|
      generator.test_framework :rspec
    end
  end
end
