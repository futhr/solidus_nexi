# frozen_string_literal: true

RSpec.describe SolidusNexi::WebhookReceipt, type: :model do
  let(:payment_method) { SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout") }
  let(:event) do
    SolidusNexi::Nexi::Webhook::Event.new(
      id: "event-1",
      name: "payment.created",
      occurred_at: Time.iso8601("2026-08-17T08:00:00Z"),
      merchant_id: "100089958",
      merchant_number: nil,
      payment_id: "provider-payment-1",
      charge_id: nil,
      refund_id: nil,
      order_reference: "R123"
    )
  end

  it "deduplicates an event per payment method" do
    first, first_created = described_class.record!(payment_method:, event:)
    second, second_created = described_class.record!(payment_method:, event:)

    expect(first_created).to be(true)
    expect(second_created).to be(false)
    expect(second).to eq(first)
  end

  it "retains operation identifiers needed for exact failure reconciliation" do
    refund_event = event.with(
      name: "payment.refund.failed",
      charge_id: "provider-charge-1",
      refund_id: "provider-refund-1"
    )

    receipt, = described_class.record!(payment_method:, event: refund_event)

    expect(receipt).to have_attributes(
      provider_charge_id: "provider-charge-1",
      provider_refund_id: "provider-refund-1"
    )
  end

  it "claims new and stale work but not active or terminal work" do
    receipt, = described_class.record!(payment_method:, event:)
    expect(receipt.claim_processing!).to be(true)
    expect(receipt).to have_attributes(status: "processing", attempts: 1)
    expect(receipt.claim_processing!).to be(false)

    receipt.update!(updated_at: 6.minutes.ago)
    expect(receipt.claim_processing!).to be(true)
    expect(receipt.attempts).to eq(2)

    receipt.mark_processed!
    expect(receipt.claim_processing!).to be(false)
  end

  it "re-enqueues failed and stale receipts but not recent active work" do
    receipt, = described_class.record!(payment_method:, event:)
    expect(receipt).to be_enqueue_required

    receipt.mark_enqueued!
    expect(receipt).not_to be_enqueue_required

    receipt.update!(updated_at: 6.minutes.ago)
    expect(receipt).to be_enqueue_required

    receipt.mark_failed!(RuntimeError.new("boom"))
    expect(receipt).to have_attributes(status: "failed", error_class: "RuntimeError")
    expect(receipt).to be_enqueue_required
  end

  it "records ignored processing as a terminal acknowledgement" do
    receipt, = described_class.record!(payment_method:, event:)
    receipt.mark_ignored!

    expect(receipt).to have_attributes(status: "ignored", error_class: nil)
    expect(receipt.processed_at).to be_present
  end
end
