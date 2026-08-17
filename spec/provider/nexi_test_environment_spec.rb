# frozen_string_literal: true

RSpec.describe "Nexi merchant test environment", :nexi_test_environment do
  let(:client) do
    SolidusNexi::Nexi::Client.new(
      api_key: ENV.fetch("NEXI_CHECKOUT_API_KEY"),
      environment: :test
    )
  end

  it "authenticates a read-only request with the merchant Test Secret key" do
    expect { client.retrieve_payment(payment_id: "0" * 32) }
      .to raise_error(SolidusNexi::Nexi::NotFoundError) { |error|
        expect(error.http_status).to eq(404)
      }
  end

  it "creates and retrieves a disposable hosted checkout under the merchant" do
    reference = "solidus-nexi-#{SecureRandom.hex(10)}"
    created = client.create_payment(payload: provider_payload(reference))
    payment_id = created["paymentId"]
    checkout_url = created["hostedPaymentPageUrl"]

    expect(payment_id).to match(SolidusNexi::Nexi::Client::IDENTIFIER)
    expect(checkout_url).to start_with("https://test.checkout.dibspayment.eu/")

    retrieved = client.retrieve_payment(payment_id:)
    snapshot = SolidusNexi::Nexi::PaymentSnapshot.new(retrieved.body, expected_payment_id: payment_id)
    expect(snapshot).to have_attributes(
      amount_minor: 10_000,
      currency: "SEK",
      order_reference: reference,
      my_reference: reference
    )
  end

  def provider_payload(reference)
    checkout = {
      integrationType: "HostedPaymentPage",
      returnUrl: "https://example.com/solidus-nexi/provider-test-return",
      cancelUrl: "https://example.com/solidus-nexi/provider-test-cancel",
      termsUrl: ENV.fetch("NEXI_CHECKOUT_TERMS_URL"),
      charge: false,
      countryCode: ENV.fetch("NEXI_CHECKOUT_COUNTRY", "SWE")
    }
    merchant_terms_url = ENV["NEXI_CHECKOUT_MERCHANT_TERMS_URL"]
    checkout[:merchantTermsUrl] = merchant_terms_url if merchant_terms_url.present?

    {
      order: {
        items: [
          {
            reference: "solidus-nexi-test-item",
            name: "Solidus Nexi provider contract test",
            quantity: 1,
            unit: "pcs",
            unitPrice: 8_000,
            taxRate: 2_500,
            taxAmount: 2_000,
            grossTotalAmount: 10_000,
            netTotalAmount: 8_000
          }
        ],
        amount: 10_000,
        currency: "SEK",
        reference:
      },
      checkout:,
      myReference: reference
    }
  end
end
