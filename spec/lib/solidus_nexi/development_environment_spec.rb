# frozen_string_literal: true

require "tempfile"

RSpec.describe SolidusNexi::DevelopmentEnvironment do
  around do |example|
    original = ENV.delete("SOLIDUS_NEXI_DOTENV_SPEC")
    example.run
  ensure
    ENV["SOLIDUS_NEXI_DOTENV_SPEC"] = original
  end

  it "loads a local env file for development without replacing exported values" do
    with_env_file("SOLIDUS_NEXI_DOTENV_SPEC=from-file\n") do |path|
      ENV["SOLIDUS_NEXI_DOTENV_SPEC"] = "from-shell"

      expect(described_class.load(path:, environment: {"RAILS_ENV" => "development"})).to be(true)
      expect(ENV.fetch("SOLIDUS_NEXI_DOTENV_SPEC")).to eq("from-shell")
    end
  end

  it "does not load an env file for production" do
    with_env_file("SOLIDUS_NEXI_DOTENV_SPEC=from-file\n") do |path|
      expect(described_class.load(path:, environment: {"RAILS_ENV" => "production"})).to be(false)
      expect(ENV["SOLIDUS_NEXI_DOTENV_SPEC"]).to be_nil
    end
  end

  private

  def with_env_file(contents)
    Tempfile.create("solidus-nexi-env") do |file|
      file.write(contents)
      file.flush
      yield file.path
    end
  end

  it "accepts a complete local test configuration" do
    expect(described_class.validate!(environment: valid_environment)).to be(true)
  end

  it "reports every unsafe or missing local setting without printing values" do
    environment = valid_environment.merge(
      "SOLIDUS_PREFERENCES_MASTER_KEY" => "too-long" * 8,
      "NEXI_CHECKOUT_API_KEY" => "",
      "NEXI_CHECKOUT_WEBHOOK_SECRET" => "bad-secret!",
      "NEXI_CHECKOUT_PREVIOUS_WEBHOOK_SECRET" => "bad-secret!",
      "NEXI_CHECKOUT_ENVIRONMENT" => "production",
      "NEXI_CHECKOUT_COUNTRY" => "se",
      "NEXI_CHECKOUT_TERMS_URL" => "http://shop.example/terms",
      "NEXI_CHECKOUT_MERCHANT_TERMS_URL" => "https://[invalid",
      "NEXI_CHECKOUT_PUBLIC_BASE_URL" => "https://shop.example/store?tenant=one"
    )

    expect { described_class.validate!(environment:) }.to raise_error(ArgumentError) { |error|
      expect(error.message).to include(
        "SOLIDUS_PREFERENCES_MASTER_KEY",
        "NEXI_CHECKOUT_API_KEY",
        "NEXI_CHECKOUT_WEBHOOK_SECRET",
        "NEXI_CHECKOUT_PREVIOUS_WEBHOOK_SECRET",
        "NEXI_CHECKOUT_ENVIRONMENT",
        "NEXI_CHECKOUT_COUNTRY",
        "NEXI_CHECKOUT_TERMS_URL",
        "NEXI_CHECKOUT_MERCHANT_TERMS_URL",
        "NEXI_CHECKOUT_PUBLIC_BASE_URL"
      )
      expect(error.message).not_to include("bad-secret!")
    }
  end

  def valid_environment
    {
      "SOLIDUS_PREFERENCES_MASTER_KEY" => "0123456789abcdef0123456789abcdef",
      "NEXI_CHECKOUT_API_KEY" => "test-api-key",
      "NEXI_CHECKOUT_WEBHOOK_SECRET" => "WebhookSecret123",
      "NEXI_CHECKOUT_PREVIOUS_WEBHOOK_SECRET" => "",
      "NEXI_CHECKOUT_ENVIRONMENT" => "test",
      "NEXI_CHECKOUT_COUNTRY" => "SWE",
      "NEXI_CHECKOUT_TERMS_URL" => "https://shop.example/terms",
      "NEXI_CHECKOUT_MERCHANT_TERMS_URL" => "https://shop.example/privacy",
      "NEXI_CHECKOUT_PUBLIC_BASE_URL" => "https://shop.example"
    }
  end
end
