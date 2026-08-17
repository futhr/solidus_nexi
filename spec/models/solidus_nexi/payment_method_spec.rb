# frozen_string_literal: true

RSpec.describe SolidusNexi::PaymentMethod, type: :model do
  subject(:payment_method) { described_class.new(name: "Nexi Checkout") }

  it "uses Solidus's expected source and gateway contracts" do
    expect(payment_method).to have_attributes(
      partial_name: "nexi_checkout",
      cart_partial_name: "nexi_checkout",
      product_page_partial_name: "nexi_checkout",
      risky_partial_name: "nexi_checkout",
      payment_source_class: SolidusNexi::PaymentSource,
      gateway_class: SolidusNexi::Gateway
    )
    expect(payment_method).to be_source_required
    expect(payment_method).not_to be_payment_profiles_supported
  end

  it "supports only its own Nexi payment sources" do
    payment_method.save!
    other_method = described_class.create!(name: "Other Nexi Checkout")
    own_source = SolidusNexi::PaymentSource.new(payment_method:, currency: "SEK")
    other_source = SolidusNexi::PaymentSource.new(payment_method: other_method, currency: "SEK")

    expect(payment_method.supports?(own_source)).to be(true)
    expect(payment_method.supports?(other_source)).to be(false)
    expect(payment_method.supports?(Object.new)).to be(false)
  end

  it "checks every required checkout preference before creating local payment state" do
    expect { payment_method.ready_for_checkout! }
      .to raise_error(SolidusNexi::Nexi::ConfigurationError, /api_key.*webhook_secret.*terms_url/)

    payment_method.preferred_api_key = "test-api-key"
    payment_method.preferred_webhook_secret = "WebhookSecret123"
    payment_method.preferred_terms_url = "https://checkout.merchant.se/terms"
    expect(payment_method.ready_for_checkout!).to eq(payment_method)

    payment_method.preferred_merchant_terms_url = "https://shop.example/privacy"
    expect { payment_method.ready_for_checkout! }
      .to raise_error(SolidusNexi::Nexi::ConfigurationError, /merchant_terms_url/)
  end

  it "never exposes encrypted credentials in the generic admin form" do
    expect(payment_method.admin_form_preference_names)
      .not_to include(:api_key, :webhook_secret, :previous_webhook_secret)
  end

  it "selects live only when both production server and live mode are explicit" do
    payment_method.preferred_server = "production"
    payment_method.preferred_test_mode = false
    expect(payment_method.nexi_environment).to eq(:live)

    payment_method.preferred_test_mode = true
    expect(payment_method.nexi_environment).to eq(:test)
  end

  it "builds a client with decrypted preferences and the configured logger" do
    logger = instance_double(Logger)
    SolidusNexi.configuration.logger = -> { logger }
    payment_method.preferred_api_key = "test-secret"

    expect(SolidusNexi::Nexi::Client).to receive(:new).with(
      api_key: "test-secret",
      environment: :test,
      logger:
    )

    payment_method.build_client
  end

  it "accepts the current and previous webhook secrets during rotation" do
    payment_method.preferred_webhook_secret = "CurrentSecret123"
    payment_method.preferred_previous_webhook_secret = "PreviousSecret123"

    authenticator = payment_method.webhook_authenticator
    expect(authenticator.valid?("CurrentSecret123")).to be(true)
    expect(authenticator.valid?("PreviousSecret123")).to be(true)
    expect(authenticator.valid?("UnknownSecret123")).to be(false)
  end

  it "validates country and both webhook secret generations" do
    payment_method.preferred_checkout_country = "se"
    payment_method.preferred_webhook_secret = "bad-secret"
    payment_method.preferred_previous_webhook_secret = "also-bad!"

    expect(payment_method).not_to be_valid
    expect(payment_method.errors[:preferred_checkout_country]).to be_present
    expect(payment_method.errors[:preferred_webhook_secret]).to be_present
    expect(payment_method.errors[:preferred_previous_webhook_secret]).to be_present
  end
end
