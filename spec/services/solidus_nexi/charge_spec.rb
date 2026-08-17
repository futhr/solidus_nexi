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

  it "returns a throttled request to pending and retries it with the same key" do
    keys = []
    client = Object.new
    client.define_singleton_method(:charge) do |idempotency_key:, **|
      keys << idempotency_key
      if keys.one?
        raise SolidusNexi::Nexi::RateLimitError.new(
          "slow down",
          provider_request_id: "request-limited",
          retry_after: "30"
        )
      end

      SolidusNexi::Nexi::Result.new(
        body: {"chargeId" => "050491ace345418d8ca70605a0c9df96"},
        http_status: 201,
        provider_request_id: "request-retried"
      )
    end
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }
    service = described_class.new(
      payment:,
      amount_minor: 10_000,
      logical_reference: "capture:#{payment.number}"
    )

    expect { service.call }.to raise_error(SolidusNexi::Nexi::RateLimitError)
    operation = SolidusNexi::Operation.find_by!(payment:, kind: "charge")
    expect(operation).to have_attributes(
      status: "pending",
      provider_request_id: "request-limited",
      dispatched_at: nil,
      reconciliation_required: false
    )

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

  it "treats a malformed successful response as an unknown outcome" do
    client = instance_double(SolidusNexi::Nexi::Client)
    allow(client).to receive(:charge).and_return(
      SolidusNexi::Nexi::Result.new(body: {"chargeId" => "invalid/id"}, http_status: 201,
        provider_request_id: "request-malformed")
    )
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    expect { service.call }.to raise_error(SolidusNexi::Nexi::ReconciliationRequired)
    expect(SolidusNexi::Operation.find_by!(payment:, kind: "charge")).to have_attributes(
      status: "unknown",
      provider_request_id: "request-malformed",
      reconciliation_required: true
    )
  end

  it "marks provider rejection terminal and does not retry it" do
    client = instance_double(SolidusNexi::Nexi::Client)
    allow(client).to receive(:charge).and_raise(
      SolidusNexi::Nexi::ValidationError.new("rejected", provider_code: "1008")
    )
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    expect { service.call }.to raise_error(SolidusNexi::Nexi::ValidationError)
    expect(SolidusNexi::Operation.find_by!(payment:, kind: "charge"))
      .to have_attributes(status: "rejected", provider_code: "1008", reconciliation_required: false)
  end

  it "marks provider success with failed local persistence for reconciliation" do
    client = instance_double(SolidusNexi::Nexi::Client)
    allow(client).to receive(:charge).and_return(
      SolidusNexi::Nexi::Result.new(
        body: {"chargeId" => "050491ace345418d8ca70605a0c9df96"},
        http_status: 201,
        provider_request_id: "request-charge"
      )
    )
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }
    allow(source).to receive(:update!).and_raise(ActiveRecord::StatementInvalid, "database unavailable")

    expect { service.call }.to raise_error(SolidusNexi::Nexi::ReconciliationRequired)
    expect(SolidusNexi::Operation.find_by!(payment:, kind: "charge").status).to eq("unknown")
  end

  it "detects a changed request behind an existing logical reference" do
    operation = SolidusNexi::Operation.create_or_find_intent!(
      payment:,
      kind: :charge,
      logical_reference: "capture:#{payment.number}",
      amount_minor: 10_000,
      currency: "SEK",
      request_fingerprint: "f" * 64,
      idempotency_key: "stable-key"
    )

    expect { service.call }.to raise_error(SolidusNexi::Nexi::ConflictError, /does not match/)
    expect(operation.reload.status).to eq("pending")
  end

  it "refuses a concurrent dispatch of the same operation" do
    operation = SolidusNexi::Operation.create_or_find_intent!(
      payment:,
      kind: :charge,
      logical_reference: "capture:#{payment.number}",
      amount_minor: 10_000,
      currency: "SEK",
      request_fingerprint: Digest::SHA256.hexdigest(SolidusNexi::Nexi::CanonicalJson.generate(
        amount: 10_000,
        provider_payment_id: source.provider_payment_id
      )),
      idempotency_key: "stable-key"
    )
    operation.update!(status: "dispatched", dispatched_at: Time.current)

    expect { service.call }.to raise_error(SolidusNexi::Nexi::OperationInProgress)
    expect(operation.reload.status).to eq("dispatched")
  end

  it "requires a provider payment ID before persisting an operation" do
    source.update!(provider_payment_id: nil)

    expect { service }.to raise_error(SolidusNexi::Nexi::ValidationError, /missing its Nexi payment ID/)
  end

  def service
    described_class.new(
      payment:,
      amount_minor: 10_000,
      logical_reference: "capture:#{payment.number}"
    )
  end
end
