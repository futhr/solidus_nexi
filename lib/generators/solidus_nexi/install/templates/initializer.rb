# frozen_string_literal: true

SolidusNexi.configure do |config|
  config.public_base_url = ENV["NEXI_CHECKOUT_PUBLIC_BASE_URL"]
  # Override these paths for a headless or custom storefront. They receive the
  # SolidusNexi::PaymentSource associated with the returning checkout.
  # config.return_path_resolver = ->(source) { "/orders/#{source.payments.first.order.number}" }
  # config.cancel_path_resolver = ->(_source) { "/checkout/payment" }
end

api_key = ENV["NEXI_CHECKOUT_API_KEY"]
webhook_secret = ENV["NEXI_CHECKOUT_WEBHOOK_SECRET"]
if api_key.present? || webhook_secret.present?
  unless api_key.present? && webhook_secret.present?
    raise "NEXI_CHECKOUT_API_KEY and NEXI_CHECKOUT_WEBHOOK_SECRET must be configured together"
  end

  environment = ENV.fetch("NEXI_CHECKOUT_ENVIRONMENT", "test")
  unless %w[test live].include?(environment)
    raise "NEXI_CHECKOUT_ENVIRONMENT must be test or live"
  end

  Spree::Config.static_model_preferences.add(
    "SolidusNexi::PaymentMethod",
    "nexi_checkout_env_credentials",
    api_key:,
    webhook_secret:,
    previous_webhook_secret: ENV["NEXI_CHECKOUT_PREVIOUS_WEBHOOK_SECRET"],
    server: (environment == "live") ? "production" : "test",
    test_mode: environment != "live",
    checkout_country: ENV.fetch("NEXI_CHECKOUT_COUNTRY", "SWE"),
    terms_url: ENV.fetch("NEXI_CHECKOUT_TERMS_URL"),
    merchant_terms_url: ENV["NEXI_CHECKOUT_MERCHANT_TERMS_URL"]
  )
end
