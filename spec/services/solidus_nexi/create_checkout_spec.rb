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
        body: JSON.parse(Rails.root.join("../fixtures/nexi/payments/created.json").read),
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

  it "marks a malformed provider success unknown instead of creating another payment" do
    client = instance_double(SolidusNexi::Nexi::Client)
    allow(client).to receive(:create_payment).and_return(
      SolidusNexi::Nexi::Result.new(
        body: {
          "paymentId" => "provider-payment-1",
          "hostedPaymentPageUrl" => "https://attacker.example/checkout"
        },
        http_status: 201,
        provider_request_id: "request-malformed"
      )
    )
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    2.times do
      expect { service.call }.to raise_error(SolidusNexi::Nexi::ReconciliationRequired)
    end

    expect(client).to have_received(:create_payment).once
    operation = SolidusNexi::Operation.find_by!(kind: "create")
    expect(operation).to have_attributes(
      status: "unknown",
      provider_payment_id: "provider-payment-1",
      provider_request_id: "request-malformed",
      reconciliation_required: true
    )
    expect(SolidusNexi::ReconcilePaymentJob)
      .to have_been_enqueued
      .with(operation.payment.source_id, provider_payment_id: "provider-payment-1")
      .exactly(2).times
  end

  it "retains the returned payment ID when local checkout persistence rolls back" do
    client = instance_double(SolidusNexi::Nexi::Client, create_payment: created_response)
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }
    allow_any_instance_of(SolidusNexi::Operation).to receive(:mark_succeeded!)
      .and_raise(ActiveRecord::StatementInvalid, "database unavailable")

    expect { service.call }.to raise_error(SolidusNexi::Nexi::ReconciliationRequired)

    operation = SolidusNexi::Operation.find_by!(kind: "create")
    expect(operation).to have_attributes(
      status: "unknown",
      provider_payment_id: "06afca06db214766b3a230c991e14a5d",
      provider_request_id: "request-create",
      reconciliation_required: true
    )
    expect(operation.payment.source).to have_attributes(provider_payment_id: nil, hosted_payment_page_url: nil)
    expect(SolidusNexi::ReconcilePaymentJob)
      .to have_been_enqueued.with(
        operation.payment.source_id,
        provider_payment_id: "06afca06db214766b3a230c991e14a5d"
      )
  end

  it "rejects a provider validation error and invalidates the local payment" do
    client = instance_double(SolidusNexi::Nexi::Client)
    allow(client).to receive(:create_payment).and_raise(
      SolidusNexi::Nexi::ValidationError.new("invalid order", provider_code: "1005")
    )
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    expect { service.call }.to raise_error(SolidusNexi::Nexi::ValidationError)

    operation = SolidusNexi::Operation.find_by!(kind: "create")
    expect(operation).to have_attributes(status: "rejected", provider_code: "1005")
    expect(operation.payment).to be_invalid
  end

  it "blocks a second worker while checkout creation is in progress" do
    payment, = create_local_checkout_intent
    operation = SolidusNexi::Operation.create_or_find_intent!(
      payment:,
      kind: :create,
      logical_reference: "checkout:#{payment.number}",
      amount_minor: 11_000,
      currency: "SEK",
      request_fingerprint: "f" * 64
    )
    operation.update!(status: "dispatched", dispatched_at: Time.current)

    expect { service.call }.to raise_error(SolidusNexi::Nexi::OperationInProgress)

    operation.update!(dispatched_at: 6.minutes.ago)
    expect { service.call }.to raise_error(SolidusNexi::Nexi::ReconciliationRequired)
  end

  it "abandons an unknowable checkout only after Nexi's checkout lifetime" do
    old_payment, = create_local_checkout_intent
    old_operation = create_checkout_operation(old_payment)
    old_operation.update!(
      status: "unknown",
      dispatched_at: (described_class::UNKNOWN_CREATE_ABANDON_AFTER + 1.minute).ago,
      reconciliation_required: true
    )
    client = instance_double(SolidusNexi::Nexi::Client, create_payment: created_response)
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    result = service.call

    expect(result.payment).not_to eq(old_payment)
    expect(old_operation.reload).to have_attributes(
      status: "abandoned",
      provider_code: "checkout_expired_without_provider_identity",
      reconciliation_required: false
    )
    expect(old_payment.reload).to be_invalid
    expect(client).to have_received(:create_payment).once
  end

  it "never abandons a checkout whose returned provider identity is known" do
    payment, = create_local_checkout_intent
    operation = create_checkout_operation(payment)
    operation.update!(
      status: "unknown",
      provider_payment_id: "provider-payment-known",
      dispatched_at: (described_class::UNKNOWN_CREATE_ABANDON_AFTER + 1.day).ago,
      reconciliation_required: true
    )
    client = instance_double(SolidusNexi::Nexi::Client)
    allow(client).to receive(:create_payment)
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    expect { service.call }.to raise_error(SolidusNexi::Nexi::ReconciliationRequired)

    expect(operation.reload.status).to eq("unknown")
    expect(payment.reload).not_to be_invalid
    expect(client).not_to have_received(:create_payment)
    expect(SolidusNexi::ReconcilePaymentJob)
      .to have_been_enqueued.with(payment.source_id, provider_payment_id: "provider-payment-known")
  end

  def create_local_checkout_intent
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK")
    payment = order.payments.create!(payment_method:, source:, amount: order.order_total_after_store_credit)
    [payment, source]
  end

  def create_checkout_operation(payment)
    SolidusNexi::Operation.create_or_find_intent!(
      payment:,
      kind: :create,
      logical_reference: "checkout:#{payment.number}",
      amount_minor: 11_000,
      currency: "SEK",
      request_fingerprint: "f" * 64
    )
  end

  def created_response
    SolidusNexi::Nexi::Result.new(
      body: JSON.parse(Rails.root.join("../fixtures/nexi/payments/created.json").read),
      http_status: 201,
      provider_request_id: "request-create"
    )
  end
end
