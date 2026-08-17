# frozen_string_literal: true

RSpec.describe SolidusNexi::ProcessWebhookJob, type: :job do
  let(:payment_method) { SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout") }
  let(:receipt) do
    SolidusNexi::WebhookReceipt.create!(
      payment_method:,
      event_id: "event-1",
      event_name: "payment.created",
      provider_payment_id: "provider-payment-1",
      order_reference: "R123",
      merchant_id: "100089958",
      occurred_at: Time.current
    )
  end
  let(:service) { instance_double(SolidusNexi::ReconcilePayment) }

  before do
    allow(SolidusNexi::ReconcilePayment).to receive(:new).and_return(service)
  end

  it "marks a reconciled local payment processed" do
    allow(service).to receive(:call).and_return(Struct.new(:payment).new(instance_double(Spree::Payment)))

    described_class.perform_now(receipt.id)

    expect(receipt.reload).to have_attributes(status: "processed", attempts: 1)
  end

  it "passes exact provider operation identifiers into reconciliation" do
    receipt.update!(provider_charge_id: "charge-1", provider_refund_id: "refund-1")
    allow(service).to receive(:call).and_return(Struct.new(:payment).new(instance_double(Spree::Payment)))

    expect(SolidusNexi::ReconcilePayment).to receive(:new).with(
      payment_method:,
      provider_payment_id: "provider-payment-1",
      order_reference: "R123",
      event_name: "payment.created",
      event_charge_id: "charge-1",
      event_refund_id: "refund-1"
    ).and_return(service)

    described_class.perform_now(receipt.id)
  end

  it "marks a valid event ignored when no local payment matches" do
    allow(service).to receive(:call).and_return(Struct.new(:payment).new(nil))

    described_class.perform_now(receipt.id)

    expect(receipt.reload).to have_attributes(status: "ignored", attempts: 1)
  end

  it "records the failure class before preserving retry behavior" do
    allow(service).to receive(:call).and_raise(SolidusNexi::Nexi::ProviderUnavailableError, "unavailable")

    expect { described_class.perform_now(receipt.id) }
      .to have_enqueued_job(described_class).with(receipt.id)
    expect(receipt.reload).to have_attributes(
      status: "failed",
      error_class: "SolidusNexi::Nexi::ProviderUnavailableError"
    )
  end

  it "does nothing when another worker owns a recent receipt" do
    receipt.update!(status: "processing")
    expect(SolidusNexi::ReconcilePayment).not_to receive(:new)

    described_class.perform_now(receipt.id)

    expect(receipt.reload.attempts).to eq(0)
  end
end
