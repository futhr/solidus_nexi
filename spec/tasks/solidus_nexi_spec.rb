# frozen_string_literal: true

require "rake"

RSpec.describe "solidus_nexi:reconcile", type: :model do
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
end
