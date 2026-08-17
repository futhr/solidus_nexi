# frozen_string_literal: true

RSpec.describe SolidusNexi::CheckoutPayload, type: :model do
  let(:order) do
    create(:order_with_line_items, currency: "SEK", line_items_price: BigDecimal("100"), shipment_cost: 0)
  end
  let(:payment_method) do
    SolidusNexi::PaymentMethod.create!(
      name: "Nexi Checkout",
      auto_capture: true,
      preferred_webhook_secret: "WebhookSecret123",
      preferred_terms_url: "https://shop.example/terms",
      preferred_merchant_terms_url: "https://shop.example/privacy",
      preferred_checkout_country: "SWE"
    )
  end
  let(:source) { SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK") }
  let(:payment) { create(:payment, order:, payment_method:, source:, amount: 100) }
  let(:attributes) do
    {
      order:,
      payment:,
      payment_method:,
      webhook_url: "https://shop.example/solidus_nexi/webhooks/1",
      return_url: "https://shop.example/solidus_nexi/returns/token",
      cancel_url: "https://shop.example/solidus_nexi/cancels/token"
    }
  end

  it "builds the documented hosted checkout and complete webhook subscription set" do
    payload = described_class.new(**attributes).call

    expect(payload[:checkout]).to eq(
      integrationType: "HostedPaymentPage",
      returnUrl: attributes[:return_url],
      cancelUrl: attributes[:cancel_url],
      termsUrl: "https://shop.example/terms",
      merchantTermsUrl: "https://shop.example/privacy",
      charge: true,
      countryCode: "SWE"
    )
    expect(payload[:myReference]).to eq(payment.number)
    expect(payload.dig(:notifications, :webHooks).pluck(:eventName))
      .to eq(described_class::WEBHOOK_EVENTS)
    expect(payload.dig(:notifications, :webHooks)).to all(include(
      url: attributes[:webhook_url],
      authorization: "WebhookSecret123"
    ))
  end

  it "omits the optional merchant terms URL when it is not configured" do
    payment_method.preferred_merchant_terms_url = nil

    payload = described_class.new(**attributes).call

    expect(payload[:checkout]).not_to have_key(:merchantTermsUrl)
  end

  it "rejects non-HTTPS, credential-bearing, oversized, and malformed URLs" do
    [
      attributes.merge(webhook_url: "http://shop.example/webhook"),
      attributes.merge(return_url: "https://user:pass@shop.example/return"),
      attributes.merge(cancel_url: "https://shop.example/#{"a" * 257}"),
      attributes.merge(cancel_url: "https://[invalid")
    ].each do |invalid_attributes|
      expect { described_class.new(**invalid_attributes) }
        .to raise_error(SolidusNexi::Nexi::ConfigurationError)
    end
  end

  it "rejects webhook credentials outside Nexi's callback contract" do
    payment_method.preferred_webhook_secret = "not-valid!"

    expect { described_class.new(**attributes) }
      .to raise_error(SolidusNexi::Nexi::ConfigurationError, /webhook_secret/)
  end
end
