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

  private

  def use_provider_fixture(path, order:)
    body = JSON.parse(File.read(Rails.root.join("..", "fixtures", path)))
    body.fetch("payment").fetch("orderDetails")["reference"] = order.number
    result = SolidusNexi::Nexi::Result.new(body:, http_status: 200, provider_request_id: "retrieve-1")
    client = Object.new
    client.define_singleton_method(:retrieve_payment) { |**| result }
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }
  end
end
