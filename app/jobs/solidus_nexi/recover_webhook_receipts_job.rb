# frozen_string_literal: true

module SolidusNexi
  class RecoverWebhookReceiptsJob < ActiveJob::Base
    queue_as :default

    def perform
      WebhookReceipt.requiring_retry.find_each do |receipt|
        receipt.with_lock do
          next unless receipt.enqueue_required?

          receipt.mark_enqueued!
          ProcessWebhookJob.perform_later(receipt.id)
        end
      end
    end
  end
end
