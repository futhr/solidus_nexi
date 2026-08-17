# frozen_string_literal: true

RSpec.describe SolidusNexi::ReconcilePayment, type: :model do
  let(:payment_method) { SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout") }
  let(:order) { create(:order, currency: "SEK") }
  let(:provider_payment_id) { "06afca06db214766b3a230c991e14a5d" }

  it "applies an authoritative charge once even when reconciliation repeats" do
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK", provider_payment_id:)
    payment = create(:payment, order:, payment_method:, source:, amount: 100)
    use_provider_fixture("nexi/payments/charged.json", order:)

    2.times { described_class.new(source:).call }

    expect(payment.reload).to be_completed
    expect(payment.capture_events.count).to eq(1)
    expect(payment.capture_events.sum(:amount)).to eq(BigDecimal("100"))
    expect(source.reload).to have_attributes(
      provider_charge_id: "050491ace345418d8ca70605a0c9df96",
      charged_amount_minor: 10_000,
      provider_status: "charged"
    )
  end

  it "recovers a create response lost before the provider ID was stored" do
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK")
    payment = create(:payment, order:, payment_method:, source:, amount: 100)
    operation = SolidusNexi::Operation.create_or_find_intent!(
      payment:,
      kind: :create,
      logical_reference: "checkout:#{payment.number}",
      amount_minor: 10_000,
      currency: "SEK",
      request_fingerprint: "f" * 64
    )
    operation.claim_dispatch!
    operation.mark_unknown!(SolidusNexi::Nexi::TimeoutUnknownOutcome.new("lost response"))
    use_provider_fixture("nexi/payments/reserved.json", order:)

    described_class.new(
      payment_method:,
      provider_payment_id:,
      order_reference: order.number,
      event_name: "payment.created"
    ).call

    expect(source.reload.provider_payment_id).to eq(provider_payment_id)
    expect(payment.reload).to be_pending
    expect(operation.reload.status).to eq("reconciled")
  end

  it "reconciles the exact provider payment when a newer checkout exists" do
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK", provider_payment_id:)
    payment = create(:payment, order:, payment_method:, source:, amount: 100)
    newer_source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK")
    newer_payment = create(:payment, order:, payment_method:, source: newer_source, amount: 100)
    use_provider_fixture("nexi/payments/charged.json", order:)

    described_class.new(payment_method:, provider_payment_id:).call

    expect(payment.reload.capture_events.sum(:amount)).to eq(BigDecimal("100"))
    expect(newer_payment.reload).to be_checkout
    expect(newer_source.reload.provider_payment_id).to be_nil
    expect(source.reload).to have_attributes(
      provider_status: "local_state_conflict",
      reconciliation_required: true,
      charged_amount_minor: 10_000
    )
  end

  it "uses the provider myReference to recover one of several open checkouts" do
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK")
    payment = create(:payment, order:, payment_method:, source:, amount: 100)
    other_source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK")
    other_payment = create(:payment, order:, payment_method:, source: other_source, amount: 100)
    payment.update!(state: "checkout")
    other_payment.update!(state: "checkout")
    use_provider_fixture("nexi/payments/reserved.json", order:, my_reference: payment.number)

    described_class.new(payment_method:, provider_payment_id:).call

    expect(source.reload.provider_payment_id).to eq(provider_payment_id)
    expect(payment.reload).to be_pending
    expect(other_source.reload.provider_payment_id).to be_nil
  end

  it "does not guess when several open checkouts have no provider reference" do
    payments = 2.times.map do
      source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK")
      create(:payment, order:, payment_method:, source:, amount: 100)
    end
    payments.each { |payment| payment.update!(state: "checkout") }
    use_provider_fixture("nexi/payments/reserved.json", order:)

    result = described_class.new(payment_method:, provider_payment_id:).call

    expect(result.payment).to be_nil
    expect(order.payments.map(&:source).map(&:provider_payment_id)).to all(be_nil)
  end

  it "records an unexpected partial charge and keeps it visible for reconciliation" do
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK", provider_payment_id:)
    payment = create(:payment, order:, payment_method:, source:, amount: 100)
    use_provider_fixture("nexi/payments/partially_charged.json", order:)

    result = described_class.new(source:).call

    expect(result.mapping).to have_attributes(
      target_state: nil,
      reconciliation_required: true,
      reason: "unexpected_partial_charge"
    )
    expect(payment.reload).to be_checkout
    expect(payment.capture_events.sum(:amount)).to eq(BigDecimal("50"))
    expect(source.reload).to have_attributes(
      charged_amount_minor: 5_000,
      reconciliation_required: true,
      provider_status: "unexpected_partial_charge"
    )
  end

  it "requires a payment method and provider payment ID" do
    expect { described_class.new.call }
      .to raise_error(SolidusNexi::Nexi::ValidationError, /payment method and provider payment ID/)
  end

  it "refuses webhook, payment reference, amount, and order mismatches" do
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK")
    payment = create(:payment, order:, payment_method:, source:, amount: 100)

    use_provider_fixture("nexi/payments/reserved.json", order:, my_reference: payment.number)
    expect do
      described_class.new(
        payment_method:,
        provider_payment_id:,
        order_reference: "another-order"
      ).call
    end.to raise_error(SolidusNexi::Nexi::ConflictError, /webhook order reference/)

    use_provider_fixture("nexi/payments/reserved.json", order:, my_reference: "missing-payment")
    expect { described_class.new(payment_method:, provider_payment_id:).call }
      .to raise_error(SolidusNexi::Nexi::ConflictError, /reference does not match/)

    source.update!(provider_payment_id:)
    use_provider_fixture("nexi/payments/reserved.json", order:, amount_minor: 9_999)
    expect { described_class.new(source:).call }
      .to raise_error(SolidusNexi::Nexi::ConflictError, /does not match/)

    use_provider_fixture("nexi/payments/reserved.json", order_reference: "another-order")
    expect { described_class.new(source:).call }
      .to raise_error(SolidusNexi::Nexi::ConflictError, /different order reference/)
  end

  it "requires a local Solidus payment for a known provider source" do
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK", provider_payment_id:)
    use_provider_fixture("nexi/payments/reserved.json", order:)

    expect { described_class.new(source:).call }
      .to raise_error(SolidusNexi::Nexi::ReconciliationRequired, /no Solidus payment/)
  end

  it "defers state changes while a local provider mutation is still fresh" do
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK", provider_payment_id:)
    payment = create(:payment, order:, payment_method:, source:, amount: 100)
    operation = SolidusNexi::Operation.create_or_find_intent!(
      payment:,
      kind: :charge,
      logical_reference: "capture:#{payment.number}",
      amount_minor: 10_000,
      currency: "SEK",
      request_fingerprint: "f" * 64,
      idempotency_key: "stable-charge-key"
    )
    operation.update!(status: "succeeded", completed_at: Time.current)
    use_provider_fixture("nexi/payments/reserved.json", order:)

    expect { described_class.new(source:).call }
      .to have_enqueued_job(SolidusNexi::ReconcilePaymentJob).with(source.id)

    expect(payment.reload).to be_checkout
    expect(source.reload.provider_status).to eq("reserved")
  end

  it "maps authoritative cancellation and provider failure into Solidus states" do
    cancelled_source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK", provider_payment_id:)
    cancelled_payment = create(:payment, order:, payment_method:, source: cancelled_source, amount: 100)
    use_provider_fixture("nexi/payments/cancelled.json", order:)

    described_class.new(source: cancelled_source).call
    expect(cancelled_payment.reload).to be_void

    failed_source = SolidusNexi::PaymentSource.create!(
      payment_method:,
      currency: "SEK",
      provider_payment_id: "another-provider-payment"
    )
    failed_payment = create(:payment, order:, payment_method:, source: failed_source, amount: 100)
    use_provider_fixture(
      "nexi/payments/reserved.json",
      order:,
      payment_id: "another-provider-payment",
      summary: {}
    )

    described_class.new(source: failed_source, event_name: "payment.reservation.failed").call
    expect(failed_payment.reload).to be_failed
  end

  it "creates one authoritative refund and reconciles its local operation" do
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK", provider_payment_id:)
    payment = create(:payment, order:, payment_method:, source:, amount: 100, state: "completed")
    refund = create(:refund, payment:, amount: 100, transaction_id: nil)
    operation = SolidusNexi::Operation.create_or_find_intent!(
      payment:,
      kind: :refund,
      logical_reference: "refund:#{refund.id}",
      amount_minor: 10_000,
      currency: "SEK",
      request_fingerprint: "f" * 64,
      idempotency_key: "stable-refund-key"
    )
    operation.update!(status: "unknown", reconciliation_required: true)
    use_provider_fixture("nexi/payments/refunded.json", order:)

    2.times { described_class.new(source:).call }

    expect(refund.reload.transaction_id).to eq("60e208b88b94403bb9ced1cca661db99")
    expect(operation.reload).to have_attributes(
      status: "reconciled",
      provider_refund_id: "60e208b88b94403bb9ced1cca661db99"
    )
    expect(payment.refunds.count).to eq(1)
  end

  it "does not invent a refund record without a provider refund ID" do
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK", provider_payment_id:)
    payment = create(:payment, order:, payment_method:, source:, amount: 100, state: "completed")
    use_provider_fixture("nexi/payments/refunded.json", order:, refunds: [])

    expect { described_class.new(source:).call }
      .to raise_error(SolidusNexi::Nexi::ReconciliationRequired, /missing its identifier/)
    expect(payment.refunds).to be_empty
  end

  private

  def use_provider_fixture(path, **attributes)
    body = JSON.parse(Rails.root.join("..", "fixtures", path).read)
    provider_payment = body.fetch("payment")
    apply_provider_attributes(provider_payment, attributes)
    result = SolidusNexi::Nexi::Result.new(body:, http_status: 200, provider_request_id: "retrieve-1")
    client = Object.new
    client.define_singleton_method(:retrieve_payment) { |**| result }
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }
  end

  def apply_provider_attributes(provider_payment, attributes)
    provider_payment["paymentId"] = attributes[:payment_id] if attributes[:payment_id]
    provider_payment["myReference"] = attributes[:my_reference]
    provider_payment["summary"] = attributes[:summary] if attributes.key?(:summary)
    provider_payment["refunds"] = attributes[:refunds] if attributes.key?(:refunds)

    order_details = provider_payment.fetch("orderDetails")
    order_details["reference"] = attributes[:order_reference] || attributes[:order]&.number
    order_details["amount"] = attributes[:amount_minor] if attributes[:amount_minor]
  end
end
