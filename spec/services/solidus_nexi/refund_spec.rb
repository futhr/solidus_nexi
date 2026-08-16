# frozen_string_literal: true

RSpec.describe SolidusNexi::Refund, type: :model do
  let(:payment_method) { SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout") }
  let(:order) { create(:order, currency: "SEK") }
  let(:source) do
    SolidusNexi::PaymentSource.create!(
      payment_method:,
      currency: "SEK",
      provider_payment_id: "06afca06db214766b3a230c991e14a5d",
      provider_charge_id: "050491ace345418d8ca70605a0c9df96",
      reserved_amount_minor: 10_000,
      charged_amount_minor: 10_000
    )
  end
  let(:payment) { create(:payment, order:, payment_method:, source:, amount: 100, state: "completed") }

  it "uses one persisted key and one provider refund for repeated execution" do
    refund = create(:refund, payment:, amount: 100)
    keys = []
    client = Object.new
    client.define_singleton_method(:refund) do |idempotency_key:, **|
      keys << idempotency_key
      SolidusNexi::Nexi::Result.new(
        body: {"refundId" => "07958a7595bb4584a79d00680fd31e15"},
        http_status: 201,
        provider_request_id: "request-1"
      )
    end
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    service = described_class.new(payment:, refund:, amount_minor: 10_000)
    2.times { expect(service.call.authorization).to eq("07958a7595bb4584a79d00680fd31e15") }

    operation = SolidusNexi::Operation.find_by!(payment:, kind: "refund")
    expect(keys).to eq([operation.idempotency_key])
  end

  it "rejects a partial refund before network dispatch" do
    refund = create(:refund, payment:, amount: 50)
    SolidusNexi.configuration.client_factory = ->(*) { raise "must not build a client" }

    service = described_class.new(payment:, refund:, amount_minor: 5_000)

    expect { service.call }.to raise_error(SolidusNexi::Nexi::ValidationError, /partial refund/)
    expect(SolidusNexi::Operation.where(payment:)).to be_empty
  end
end
