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
end
