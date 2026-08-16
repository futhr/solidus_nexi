# frozen_string_literal: true

RSpec.describe SolidusNexi::CreateCheckout, type: :model do
  let(:order) do
    create(:order_with_line_items, currency: "SEK", line_items_price: BigDecimal("100"), shipment_cost: 10)
  end
  let(:payment_method) do
    SolidusNexi::PaymentMethod.create!(
      name: "Nexi Checkout",
      preferred_api_key: "test-api-key",
      preferred_webhook_secret: "WebhookSecret123456789",
      preferred_terms_url: "https://shop.example/terms",
      preferred_checkout_country: "SWE"
    )
  end
  let(:service) do
    described_class.new(
      order:,
      payment_method:,
      webhook_url: "https://shop.example/solidus_nexi/webhooks/#{payment_method.id}",
      return_url_for: ->(source) { "https://shop.example/solidus_nexi/returns/#{source.return_token}" },
      cancel_url_for: ->(source) { "https://shop.example/solidus_nexi/cancels/#{source.return_token}" }
    )
  end

  it "persists the local intent before dispatch and reuses the open hosted checkout" do
    requests = []
    client = Object.new
    client.define_singleton_method(:create_payment) do |payload:|
      requests << payload
      SolidusNexi::Nexi::Result.new(
        body: JSON.parse(File.read(Rails.root.join("..", "fixtures/nexi/payments/created.json"))),
        http_status: 201,
        provider_request_id: "request-create"
      )
    end
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    first = service.call
    second = service.call

    expect(first.reused).to be(false)
    expect(second.reused).to be(true)
    expect(second.payment).to eq(first.payment)
    expect(requests.length).to eq(1)
    expect(requests.first.dig(:order, :items).sum { |item| item.fetch(:grossTotalAmount) })
      .to eq(requests.first.dig(:order, :amount))
    expect(SolidusNexi::Operation.find_by!(payment: first.payment, kind: "create"))
      .to have_attributes(status: "succeeded", idempotency_key: nil)
  end

  it "blocks a new create after an ambiguous response" do
    calls = 0
    client = Object.new
    client.define_singleton_method(:create_payment) do |**|
      calls += 1
      raise SolidusNexi::Nexi::TimeoutUnknownOutcome, "lost response"
    end
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    2.times do
      expect { service.call }.to raise_error(SolidusNexi::Nexi::ReconciliationRequired)
    end
    expect(calls).to eq(1)
    expect(SolidusNexi::Operation.find_by!(kind: "create")).to have_attributes(
      status: "unknown",
      reconciliation_required: true,
      idempotency_key: nil
    )
  end
end
