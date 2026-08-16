# frozen_string_literal: true

RSpec.describe SolidusNexi::Operation, type: :model do
  let(:payment_method) { SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout") }
  let(:order) { create(:order, currency: "SEK") }
  let(:source) { SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK") }
  let(:payment) { create(:payment, order:, payment_method:, source:, amount: 100) }

  it "reuses the durable operation and idempotency key for one logical intent" do
    first = described_class.create_or_find_intent!(**intent)
    second = described_class.create_or_find_intent!(**intent.merge(idempotency_key: "a-new-key-that-must-not-win"))

    expect(second.id).to eq(first.id)
    expect(second.idempotency_key).to eq("stable-charge-key")
  end

  it "requires idempotency only for provider-supported operation kinds" do
    expect { described_class.create_or_find_intent!(**intent.merge(idempotency_key: nil)) }
      .to raise_error(ActiveRecord::RecordInvalid)

    cancel = described_class.create_or_find_intent!(**intent.merge(
      kind: :cancel,
      logical_reference: "cancel:#{payment.number}",
      idempotency_key: nil
    ))
    expect(cancel).to be_valid
  end

  def intent
    {
      payment:,
      kind: :charge,
      logical_reference: "capture:#{payment.number}",
      amount_minor: 10_000,
      currency: "SEK",
      request_fingerprint: "f" * 64,
      idempotency_key: "stable-charge-key"
    }
  end
end
