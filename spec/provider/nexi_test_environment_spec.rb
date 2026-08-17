# frozen_string_literal: true

RSpec.describe "Nexi merchant test environment", :nexi_test_environment do
  let(:order) do
    create(:order_with_line_items, currency: "SEK", line_items_price: BigDecimal("100"), shipment_cost: 0)
  end
  let(:payment_method) do
    SolidusNexi::PaymentMethod.create!(
      name: "Nexi provider contract",
      preferred_api_key: ENV.fetch("NEXI_CHECKOUT_API_KEY"),
      preferred_webhook_secret: ENV.fetch("NEXI_CHECKOUT_WEBHOOK_SECRET"),
      preferred_terms_url: ENV.fetch("NEXI_CHECKOUT_TERMS_URL"),
      preferred_merchant_terms_url: ENV["NEXI_CHECKOUT_MERCHANT_TERMS_URL"],
      preferred_checkout_country: ENV.fetch("NEXI_CHECKOUT_COUNTRY", "SWE")
    )
  end
  let(:source) { SolidusNexi::PaymentSource.create!(payment_method:, currency: order.currency) }
  let(:payment) { create(:payment, order:, payment_method:, source:, amount: order.total) }
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
    created = client.create_payment(payload: provider_payload)
    payment_id = created["paymentId"]
    checkout_url = created["hostedPaymentPageUrl"]

    expect(payment_id).to match(SolidusNexi::Nexi::Client::IDENTIFIER)
    expect(checkout_url).to start_with("https://test.checkout.dibspayment.eu/")

    retrieved = client.retrieve_payment(payment_id:)
    snapshot = SolidusNexi::Nexi::PaymentSnapshot.new(retrieved.body, expected_payment_id: payment_id)
    expect(snapshot).to have_attributes(
      amount_minor: 10_000,
      currency: "SEK",
      order_reference: order.number,
      my_reference: payment.number
    )
  end

  def provider_payload
    base_url = ENV.fetch("NEXI_CHECKOUT_PUBLIC_BASE_URL").delete_suffix("/")
    unless SolidusNexi::PublicUrl.valid_https?(base_url, origin: true)
      raise "NEXI_CHECKOUT_PUBLIC_BASE_URL must be a public HTTPS origin for provider specs"
    end

    SolidusNexi::CheckoutPayload.new(
      order:,
      payment:,
      payment_method:,
      webhook_url: "#{base_url}/solidus_nexi/webhooks/#{payment_method.id}",
      return_url: "#{base_url}/solidus_nexi/returns/#{source.return_token}",
      cancel_url: "#{base_url}/solidus_nexi/cancels/#{source.return_token}"
    ).call
  end
end
