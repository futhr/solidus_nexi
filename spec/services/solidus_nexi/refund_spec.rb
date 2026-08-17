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
    expect(operation).to have_attributes(
      status: "accepted",
      provider_refund_id: "07958a7595bb4584a79d00680fd31e15",
      reconciliation_required: true
    )
    expect(source.reload).to have_attributes(provider_status: "refund_pending", reconciliation_required: true)
  end

  it "reuses an unsaved Solidus refund intent but permits a new attempt after final failure" do
    calls = 0
    client = Object.new
    client.define_singleton_method(:refund) do |**|
      calls += 1
      SolidusNexi::Nexi::Result.new(
        body: {"refundId" => "provider-refund-#{calls}"},
        http_status: 201,
        provider_request_id: "request-#{calls}"
      )
    end
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    first_refund = build(:refund, payment:, amount: 100, transaction_id: nil)
    second_refund = build(:refund, payment:, amount: 100, transaction_id: nil)
    described_class.new(payment:, refund: first_refund, amount_minor: 10_000).call
    described_class.new(payment:, refund: second_refund, amount_minor: 10_000).call
    first_operation = SolidusNexi::Operation.find_by!(payment:, logical_reference: "refund:attempt:1")
    first_operation.mark_rejected!(
      SolidusNexi::Nexi::Error.new("Nexi refund failed", provider_code: "refund_failed")
    )

    third_refund = build(:refund, payment:, amount: 100, transaction_id: nil)
    described_class.new(payment:, refund: third_refund, amount_minor: 10_000).call

    expect(calls).to eq(2)
    expect(SolidusNexi::Operation.where(payment:, kind: "refund").order(:created_at).pluck(:logical_reference))
      .to eq(%w[refund:attempt:1 refund:attempt:2])
  end

  it "rejects a partial refund before network dispatch" do
    refund = create(:refund, payment:, amount: 50)
    SolidusNexi.configuration.client_factory = ->(*) { raise "must not build a client" }

    service = described_class.new(payment:, refund:, amount_minor: 5_000)

    expect { service.call }.to raise_error(SolidusNexi::Nexi::ValidationError, /partial refund/)
    expect(SolidusNexi::Operation.where(payment:)).to be_empty
  end

  it "retrieves and persists a missing charge ID before refunding" do
    source.update!(provider_charge_id: nil)
    refund = create(:refund, payment:, amount: 100)
    body = JSON.parse(Rails.root.join("../fixtures/nexi/payments/charged.json").read)
    body.fetch("payment").fetch("orderDetails")["reference"] = order.number
    client = instance_double(SolidusNexi::Nexi::Client)
    expect(client).to receive(:retrieve_payment).and_return(
      SolidusNexi::Nexi::Result.new(body:, http_status: 200, provider_request_id: "retrieve-1")
    )
    expect(client).to receive(:refund).with(hash_including(charge_id: "050491ace345418d8ca70605a0c9df96"))
      .and_return(SolidusNexi::Nexi::Result.new(
        body: {"refundId" => "07958a7595bb4584a79d00680fd31e15"},
        http_status: 201,
        provider_request_id: "refund-1"
      ))
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    result = described_class.new(payment:, refund:, amount_minor: 10_000).call

    expect(result.authorization).to eq("07958a7595bb4584a79d00680fd31e15")
    expect(source.reload.provider_charge_id).to eq("050491ace345418d8ca70605a0c9df96")
  end

  it "does not guess when the provider has no charge to refund" do
    source.update!(provider_charge_id: nil)
    refund = create(:refund, payment:, amount: 100)
    body = JSON.parse(Rails.root.join("../fixtures/nexi/payments/reserved.json").read)
    body.fetch("payment").fetch("orderDetails")["reference"] = order.number
    client = instance_double(SolidusNexi::Nexi::Client)
    allow(client).to receive(:retrieve_payment).and_return(
      SolidusNexi::Nexi::Result.new(body:, http_status: 200, provider_request_id: "retrieve-1")
    )
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    expect { described_class.new(payment:, refund:, amount_minor: 10_000).call }
      .to raise_error(SolidusNexi::Nexi::ReconciliationRequired, /no charge/)
    expect(SolidusNexi::Operation.where(payment:)).to be_empty
  end

  it "makes a malformed refund response safely retriable with the same operation" do
    refund = create(:refund, payment:, amount: 100)
    client = instance_double(SolidusNexi::Nexi::Client)
    allow(client).to receive(:refund).and_return(
      SolidusNexi::Nexi::Result.new(
        body: {"refundId" => "invalid/id"},
        http_status: 201,
        provider_request_id: "refund-malformed"
      )
    )
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    expect { described_class.new(payment:, refund:, amount_minor: 10_000).call }
      .to raise_error(SolidusNexi::Nexi::ReconciliationRequired)
    expect(SolidusNexi::Operation.find_by!(payment:, kind: "refund"))
      .to have_attributes(status: "unknown", reconciliation_required: true)
  end

  it "marks provider success with failed local persistence for reconciliation" do
    refund = create(:refund, payment:, amount: 100)
    client = instance_double(SolidusNexi::Nexi::Client)
    allow(client).to receive(:refund).and_return(
      SolidusNexi::Nexi::Result.new(
        body: {"refundId" => "07958a7595bb4584a79d00680fd31e15"},
        http_status: 201,
        provider_request_id: "request-refund"
      )
    )
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }
    allow(source).to receive(:update!).and_raise(ActiveRecord::StatementInvalid, "database unavailable")

    expect { described_class.new(payment:, refund:, amount_minor: 10_000).call }
      .to raise_error(SolidusNexi::Nexi::ReconciliationRequired)
    expect(SolidusNexi::Operation.find_by!(payment:, kind: "refund").status).to eq("unknown")
  end
end
