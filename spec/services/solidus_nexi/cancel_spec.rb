# frozen_string_literal: true

RSpec.describe SolidusNexi::Cancel, type: :model do
  let(:payment_method) { SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout") }
  let(:order) { create(:order, currency: "SEK") }
  let(:source) do
    SolidusNexi::PaymentSource.create!(
      payment_method:,
      currency: "SEK",
      provider_payment_id: "06afca06db214766b3a230c991e14a5d",
      reserved_amount_minor: 10_000
    )
  end
  let(:payment) { create(:payment, order:, payment_method:, source:, amount: 100, state: "pending") }

  it "does not replay an ambiguous cancellation without provider idempotency support" do
    calls = 0
    client = Object.new
    client.define_singleton_method(:cancel) do |**|
      calls += 1
      raise SolidusNexi::Nexi::TimeoutUnknownOutcome, "lost response"
    end
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }
    service = described_class.new(
      payment:,
      amount_minor: 10_000,
      logical_reference: "cancel:#{payment.number}"
    )

    2.times do
      expect { service.call }.to raise_error(SolidusNexi::Nexi::ReconciliationRequired)
    end

    expect(calls).to eq(1)
    expect(SolidusNexi::Operation.find_by!(payment:, kind: "cancel")).to have_attributes(
      status: "unknown",
      idempotency_key: nil,
      reconciliation_required: true
    )
  end

  it "rejects a partial cancellation before network dispatch" do
    SolidusNexi.configuration.client_factory = ->(*) { raise "must not build a client" }
    service = described_class.new(
      payment:,
      amount_minor: 5_000,
      logical_reference: "cancel:#{payment.number}"
    )

    expect { service.call }.to raise_error(SolidusNexi::Nexi::ValidationError, /partial cancellation/)
    expect(SolidusNexi::Operation.where(payment:)).to be_empty
  end
end
