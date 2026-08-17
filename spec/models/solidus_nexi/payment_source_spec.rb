# frozen_string_literal: true

RSpec.describe SolidusNexi::PaymentSource, type: :model do
  let(:payment_method) { SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout") }
  let(:source) { described_class.create!(payment_method:, currency: "SEK") }
  let(:order) { create(:order, currency: "SEK") }
  let(:payment) { create(:payment, order:, payment_method:, source:, amount: 100) }

  it "exposes only the Solidus actions the gateway implements" do
    expect(source.actions).to eq(%w[capture void credit])
    expect(source).not_to be_reusable
  end

  it "allows capture and void only while the payment is pending" do
    payment.update!(state: "pending")

    expect(source.can_capture?(payment)).to be(true)
    expect(source.can_void?(payment)).to be(true)

    payment.update!(state: "completed")
    expect(source.can_capture?(payment)).to be(false)
    expect(source.can_void?(payment)).to be(false)
  end

  it "allows credit only for a completed payment with refundable value" do
    payment.update!(state: "completed")

    expect(source.can_credit?(payment)).to be(true)

    create(:refund, payment:, amount: payment.amount)
    expect(source.can_credit?(payment.reload)).to be(false)
  end

  it "recognizes only a provider-backed, unexpired hosted checkout" do
    source.update!(
      provider_payment_id: "provider-payment-1",
      hosted_payment_page_url: "https://test.checkout.dibspayment.eu/hostedpaymentpage/1",
      checkout_expires_at: 1.hour.from_now
    )

    expect(source.checkout_open?).to be(true)
    expect(source.checkout_open?(at: 2.hours.from_now)).to be(false)
  end

  it "assigns an opaque unique return token and rejects unsupported currency" do
    expect(source.return_token).to match(/\A[0-9a-f]{48}\z/)

    invalid = described_class.new(payment_method:, currency: "AUD")
    expect(invalid).not_to be_valid
    expect(invalid.errors[:currency]).to be_present
  end
end
