# frozen_string_literal: true

require "rake"

RSpec.describe "solidus_nexi tasks", type: :model do
  let(:task) { Rake::Task["solidus_nexi:reconcile"] }
  let(:payment_method) { SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout") }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("solidus_nexi:reconcile")
    task.reenable
  end

  it "queues sources flagged by provider reconciliation even without an uncertain operation" do
    source = SolidusNexi::PaymentSource.create!(
      payment_method:,
      currency: "SEK",
      provider_payment_id: "provider-payment-1",
      reconciliation_required: true
    )
    SolidusNexi::PaymentSource.create!(
      payment_method:,
      currency: "SEK",
      provider_payment_id: "provider-payment-2"
    )

    expect { task.invoke }
      .to output("Enqueued Nexi reconciliation for source #{source.id}\n").to_stdout

    jobs = enqueued_jobs.select { |job| job[:job] == SolidusNexi::ReconcilePaymentJob }
    expect(jobs.pluck(:args)).to eq([[source.id]])
  end
  it "recovers a provider identity retained only on the create operation" do
    order = create(:order, currency: "SEK")
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK")
    payment = create(:payment, order:, payment_method:, source:, amount: 100)
    operation = SolidusNexi::Operation.create_or_find_intent!(
      payment:, kind: :create, logical_reference: "checkout:#{payment.number}",
      amount_minor: 10_000, currency: "SEK", request_fingerprint: "f" * 64
    )
    operation.mark_unknown!(SolidusNexi::Nexi::MalformedResponseError.new("lost URL"),
      provider_payment_id: "recovered-payment")

    expect { task.invoke }.to have_enqueued_job(SolidusNexi::ReconcilePaymentJob)
      .with(source.id, provider_payment_id: "recovered-payment")
  end

  it "queues the webhook recovery sweep" do
    recovery_task = Rake::Task["solidus_nexi:recover_webhooks"]
    recovery_task.reenable

    expect { recovery_task.invoke }
      .to output("Enqueued Nexi webhook recovery sweep\n").to_stdout
      .and have_enqueued_job(SolidusNexi::RecoverWebhookReceiptsJob)
  end
end
