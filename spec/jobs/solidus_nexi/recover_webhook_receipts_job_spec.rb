# frozen_string_literal: true

RSpec.describe SolidusNexi::RecoverWebhookReceiptsJob, type: :job do
  let(:payment_method) { SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout") }

  it "requeues failed and stale receipts but leaves active and terminal work alone" do
    failed = receipt("failed", event_id: "failed")
    stale = receipt("processing", event_id: "stale", updated_at: 6.minutes.ago)
    active = receipt("processing", event_id: "active")
    processed = receipt("processed", event_id: "processed")

    described_class.perform_now

    expect(SolidusNexi::ProcessWebhookJob).to have_been_enqueued.with(failed.id)
    expect(SolidusNexi::ProcessWebhookJob).to have_been_enqueued.with(stale.id)
    expect(enqueued_jobs).not_to include(hash_including(args: [active.id]))
    expect(enqueued_jobs).not_to include(hash_including(args: [processed.id]))
    expect(failed.reload.status).to eq("enqueued")
    expect(stale.reload.status).to eq("enqueued")
  end

  it "does not duplicate a receipt that another sweep just enqueued" do
    record = receipt("failed", event_id: "failed")

    2.times { described_class.perform_now }

    jobs = enqueued_jobs.select { |job| job[:job] == SolidusNexi::ProcessWebhookJob }
    expect(jobs.pluck(:args)).to eq([[record.id]])
  end

  def receipt(status, event_id:, updated_at: Time.current)
    SolidusNexi::WebhookReceipt.create!(
      payment_method:,
      event_id:,
      event_name: "payment.created",
      provider_payment_id: "provider-payment-#{event_id}",
      merchant_id: "100089958",
      occurred_at: Time.current,
      status:,
      updated_at:
    )
  end
end
