# frozen_string_literal: true

namespace :solidus_nexi do
  desc "Reconcile one Nexi payment source, or all sources with unknown/stale operations"
  task :reconcile, [:source_id] => :environment do |_task, arguments|
    sources = if arguments[:source_id]
      SolidusNexi::PaymentSource.where(id: arguments[:source_id])
    else
      payment_ids = SolidusNexi::Operation
        .where(status: %w[dispatched accepted unknown])
        .where("dispatched_at < ? OR reconciliation_required = ?", 5.minutes.ago, true)
        .select(:payment_id)
      source_ids = Spree::Payment.where(id: payment_ids, source_type: "SolidusNexi::PaymentSource").select(:source_id)
      SolidusNexi::PaymentSource
        .where(id: source_ids)
        .or(SolidusNexi::PaymentSource.requiring_reconciliation)
        .where.not(provider_payment_id: nil)
    end

    sources.find_each do |source|
      SolidusNexi::ReconcilePaymentJob.perform_later(source.id)
      puts "Enqueued Nexi reconciliation for source #{source.id}"
    end
  end

  desc "Queue recovery for failed or stale Nexi webhook receipts"
  task recover_webhooks: :environment do
    SolidusNexi::RecoverWebhookReceiptsJob.perform_later
    puts "Enqueued Nexi webhook recovery sweep"
  end
end
