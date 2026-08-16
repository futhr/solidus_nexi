# frozen_string_literal: true

RSpec.describe SolidusNexi::Charge, type: :model do
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

  it "uses one persisted key and one provider charge for repeated execution" do
    keys = []
    client = Object.new
    client.define_singleton_method(:charge) do |idempotency_key:, **|
      keys << idempotency_key
      SolidusNexi::Nexi::Result.new(
        body: {"chargeId" => "050491ace345418d8ca70605a0c9df96"},
        http_status: 201,
        provider_request_id: "request-1"
      )
    end
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    service = described_class.new(
      payment:,
      amount_minor: 10_000,
      logical_reference: "capture:#{payment.number}"
    )
    2.times { expect(service.call.authorization).to eq("050491ace345418d8ca70605a0c9df96") }

    expect(keys.length).to eq(1)
    expect(keys.first).to eq(SolidusNexi::Operation.find_by!(payment:, kind: "charge").idempotency_key)
  end

  it "keeps an ambiguous result retriable under the same key" do
    keys = []
    client = Object.new
    client.define_singleton_method(:charge) do |idempotency_key:, **|
      keys << idempotency_key
      raise SolidusNexi::Nexi::TimeoutUnknownOutcome, "lost response" if keys.one?

      SolidusNexi::Nexi::Result.new(
        body: {"chargeId" => "050491ace345418d8ca70605a0c9df96"},
        http_status: 201,
        provider_request_id: "request-2"
      )
    end
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }
    service = described_class.new(
      payment:,
      amount_minor: 10_000,
      logical_reference: "capture:#{payment.number}"
    )

    expect { service.call }.to raise_error(SolidusNexi::Nexi::ReconciliationRequired)
    operation = SolidusNexi::Operation.find_by!(payment:, kind: "charge")
    expect(operation).to have_attributes(status: "unknown", reconciliation_required: true)

    expect(service.call.authorization).to eq("050491ace345418d8ca70605a0c9df96")
    expect(keys).to eq([operation.idempotency_key, operation.idempotency_key])
  end

  it "rejects partial capture before network dispatch" do
    SolidusNexi.configuration.client_factory = ->(*) { raise "must not build a client" }
    service = described_class.new(
      payment:,
      amount_minor: 5_000,
      logical_reference: "capture:#{payment.number}"
    )

    expect { service.call }.to raise_error(SolidusNexi::Nexi::ValidationError, /partial capture/)
    expect(SolidusNexi::Operation.where(payment:)).to be_empty
  end
end
