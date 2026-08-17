# frozen_string_literal: true

RSpec.describe "generated Solidus Nexi initializer", type: :generator do
  after(:context) do
    names = %w[
      NEXI_CHECKOUT_API_KEY NEXI_CHECKOUT_COUNTRY NEXI_CHECKOUT_ENVIRONMENT
      NEXI_CHECKOUT_PUBLIC_BASE_URL NEXI_CHECKOUT_TERMS_URL NEXI_CHECKOUT_WEBHOOK_SECRET
    ]
    original = ENV.to_h.slice(*names)
    names.each { |name| ENV.delete(name) }
    ENV.update(
      "NEXI_CHECKOUT_API_KEY" => "coverage-api-key",
      "NEXI_CHECKOUT_WEBHOOK_SECRET" => "CoverageWebhookSecret123",
      "NEXI_CHECKOUT_ENVIRONMENT" => "test",
      "NEXI_CHECKOUT_COUNTRY" => "SWE",
      "NEXI_CHECKOUT_PUBLIC_BASE_URL" => "https://checkout.merchant.se",
      "NEXI_CHECKOUT_TERMS_URL" => "https://checkout.merchant.se/terms"
    )
    template = File.expand_path("../../../lib/generators/solidus_nexi/install/templates/initializer.rb", __dir__)
    RSpec::Mocks.with_temporary_scope do
      allow(Spree::Config.static_model_preferences).to receive(:add)
      load template
    end
  ensure
    names.each { |name| ENV.delete(name) }
    original.each { |name, value| ENV[name] = value }
  end

  let(:template) do
    File.expand_path("../../../lib/generators/solidus_nexi/install/templates/initializer.rb", __dir__)
  end
  let(:preferences) { Spree::Config.static_model_preferences }
  let(:environment_names) do
    %w[
      NEXI_CHECKOUT_API_KEY
      NEXI_CHECKOUT_COUNTRY
      NEXI_CHECKOUT_ENVIRONMENT
      NEXI_CHECKOUT_MERCHANT_TERMS_URL
      NEXI_CHECKOUT_PREVIOUS_WEBHOOK_SECRET
      NEXI_CHECKOUT_PUBLIC_BASE_URL
      NEXI_CHECKOUT_TERMS_URL
      NEXI_CHECKOUT_WEBHOOK_SECRET
    ]
  end

  around do |example|
    original = ENV.to_h.slice(*environment_names)
    environment_names.each { |name| ENV.delete(name) }
    example.run
  ensure
    environment_names.each { |name| ENV.delete(name) }
    original.each { |name, value| ENV[name] = value }
  end

  before do
    allow(preferences).to receive(:add)
    ENV["NEXI_CHECKOUT_PUBLIC_BASE_URL"] = "https://checkout.merchant.se"
  end

  it "leaves static preferences disabled when credentials are absent" do
    load template

    expect(preferences).not_to have_received(:add)
    expect(SolidusNexi.configuration.public_base_url).to eq("https://checkout.merchant.se")
  end

  it "fails fast when only one credential is configured" do
    ENV["NEXI_CHECKOUT_API_KEY"] = "test-api-key"

    expect { load template }.to raise_error(RuntimeError, /must be configured together/)
  end

  it "fails fast for an unknown provider environment" do
    configure_credentials(environment: "staging")

    expect { load template }.to raise_error(RuntimeError, /must be test or live/)
  end

  it "registers a complete test preference source" do
    configure_credentials(environment: "test")

    load template

    expect(preferences).to have_received(:add).with(
      "SolidusNexi::PaymentMethod",
      "nexi_checkout_env_credentials",
      hash_including(server: "test", test_mode: true, api_key: "test-api-key")
    )
  end

  it "requires explicit live mode before selecting the production server" do
    configure_credentials(environment: "live")

    load template

    expect(preferences).to have_received(:add).with(
      "SolidusNexi::PaymentMethod",
      "nexi_checkout_env_credentials",
      hash_including(server: "production", test_mode: false)
    )
  end

  def configure_credentials(environment:)
    ENV.update(
      "NEXI_CHECKOUT_API_KEY" => "test-api-key",
      "NEXI_CHECKOUT_WEBHOOK_SECRET" => "WebhookSecret123",
      "NEXI_CHECKOUT_ENVIRONMENT" => environment,
      "NEXI_CHECKOUT_COUNTRY" => "SWE",
      "NEXI_CHECKOUT_TERMS_URL" => "https://checkout.merchant.se/terms"
    )
  end
end
