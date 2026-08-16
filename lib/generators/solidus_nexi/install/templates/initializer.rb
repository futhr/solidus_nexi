# frozen_string_literal: true

SolidusNexi.configure do |config|
  config.public_base_url = ENV["NEXI_CHECKOUT_PUBLIC_BASE_URL"]
  # Override these paths for a headless or custom storefront. They receive the
  # SolidusNexi::PaymentSource associated with the returning checkout.
  # config.return_path_resolver = ->(source) { "/orders/#{source.payments.first.order.number}" }
  # config.cancel_path_resolver = ->(_source) { "/checkout/payment" }
end

if ENV.values_at("NEXI_CHECKOUT_API_KEY", "NEXI_CHECKOUT_WEBHOOK_SECRET").all?(&:present?)
  Spree::Config.static_model_preferences.add(
    "SolidusNexi::PaymentMethod",
    "nexi_checkout_env_credentials",
    api_key: ENV.fetch("NEXI_CHECKOUT_API_KEY"),
    webhook_secret: ENV.fetch("NEXI_CHECKOUT_WEBHOOK_SECRET"),
    previous_webhook_secret: ENV["NEXI_CHECKOUT_PREVIOUS_WEBHOOK_SECRET"],
    server: (ENV.fetch("NEXI_CHECKOUT_ENVIRONMENT", "test") == "live") ? "production" : "test",
    test_mode: ENV.fetch("NEXI_CHECKOUT_ENVIRONMENT", "test") != "live",
    checkout_country: ENV.fetch("NEXI_CHECKOUT_COUNTRY", "SWE"),
    terms_url: ENV.fetch("NEXI_CHECKOUT_TERMS_URL"),
    merchant_terms_url: ENV["NEXI_CHECKOUT_MERCHANT_TERMS_URL"]
  )
end
