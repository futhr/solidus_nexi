# frozen_string_literal: true

RSpec.describe SolidusNexi::ReconcilePaymentJob, type: :job do
  it "loads the source by ID and invokes authoritative reconciliation" do
    payment_method = SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout")
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK")
    service = instance_double(SolidusNexi::ReconcilePayment, call: true)

    expect(SolidusNexi::ReconcilePayment).to receive(:new).with(source:).and_return(service)

    described_class.perform_now(source.id)
  end
end
