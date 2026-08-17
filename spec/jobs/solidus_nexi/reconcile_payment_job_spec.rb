# frozen_string_literal: true

RSpec.describe SolidusNexi::ReconcilePaymentJob, type: :job do
  it "loads the source by ID and invokes authoritative reconciliation" do
    payment_method = SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout")
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK")
    service = instance_double(SolidusNexi::ReconcilePayment, call: true)

    expect(SolidusNexi::ReconcilePayment).to receive(:new)
      .with(source:, provider_payment_id: nil)
      .and_return(service)

    described_class.perform_now(source.id)
  end

  it "reconciles a returned provider ID before it has reached the source" do
    payment_method = SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout")
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK")
    service = instance_double(SolidusNexi::ReconcilePayment, call: true)

    expect(SolidusNexi::ReconcilePayment).to receive(:new)
      .with(source:, provider_payment_id: "provider-payment-1")
      .and_return(service)

    described_class.perform_now(source.id, provider_payment_id: "provider-payment-1")
  end

  it "honors the provider Retry-After delay" do
    payment_method = SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout")
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK")
    service = instance_double(SolidusNexi::ReconcilePayment)
    allow(SolidusNexi::ReconcilePayment).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_raise(
      SolidusNexi::Nexi::RateLimitError.new("limited", retry_after: "90")
    )
    before = Time.current

    expect { described_class.perform_now(source.id) }
      .to have_enqueued_job(described_class)
      .with(source.id)
      .at(be_within(1.second).of(before + 90.seconds))
  end
end
