# frozen_string_literal: true

RSpec.describe SolidusNexi::PaymentProcessing, type: :model do
  let(:payment_method) { SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout", auto_capture: true) }
  let(:order) { create(:order, currency: "SEK") }
  let(:source) do
    SolidusNexi::PaymentSource.create!(
      payment_method:,
      currency: "SEK",
      provider_payment_id: "06afca06db214766b3a230c991e14a5d"
    )
  end
  let(:payment) { create(:payment, order:, payment_method:, source:, amount: 100) }

  it "moves a verified hosted reservation into Solidus pending state" do
    expect(payment_method).to receive(:authorize).with(10_000, source, hash_including(originator: payment))
      .and_return(successful_response)

    expect(payment.authorize!).to be(true)
    expect(payment.reload).to be_pending
    expect(payment.capture_events).to be_empty
  end

  it "moves a verified auto-capture into completed state and records the capture" do
    expect(payment_method).to receive(:purchase).with(10_000, source, hash_including(originator: payment))
      .and_return(successful_response)

    expect(payment.purchase!).to be(true)
    expect(payment.reload).to be_completed
    expect(payment.capture_events.sum(:amount)).to eq(BigDecimal("100"))
  end

  it "captures a pending authorization through Solidus's payment API" do
    payment.update!(state: "pending")
    expect(payment_method).to receive(:capture).with(10_000, anything, hash_including(originator: payment))
      .and_return(successful_response)

    expect(payment.capture!).to be(true)
    expect(payment.reload).to be_completed
    expect(payment.capture_events.sum(:amount)).to eq(BigDecimal("100"))
  end

  it "is idempotent after a payment reaches its target state" do
    payment.update!(state: "completed")
    expect(payment_method).not_to receive(:purchase)
    expect(payment_method).not_to receive(:capture)

    expect(payment.purchase!).to be(true)
    expect(payment.capture!).to be(true)
  end

  it "does not duplicate a capture when a webhook wins the synchronous race" do
    allow(payment_method).to receive(:purchase) do
      concurrent = Spree::Payment.find(payment.id)
      concurrent.capture_events.create!(amount: 100)
      concurrent.complete!
      ActiveMerchant::Billing::Response.new(
        true,
        "verified",
        {},
        authorization: source.provider_payment_id,
        test: true
      )
    end

    expect(payment.purchase!).to be(true)
    expect(payment.reload).to be_completed
    expect(payment.capture_events.count).to eq(1)
    expect(payment.capture_events.sum(:amount)).to eq(BigDecimal("100"))
  end

  def successful_response
    ActiveMerchant::Billing::Response.new(
      true,
      "verified",
      {},
      authorization: source.provider_payment_id,
      test: true
    )
  end
end
