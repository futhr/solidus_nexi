# frozen_string_literal: true

module SolidusNexi
  class ProcessWebhookJob < ActiveJob::Base
    queue_as :default

    retry_on Nexi::RateLimitError, Nexi::ProviderUnavailableError, Nexi::TransportError,
      wait: :polynomially_longer, attempts: 5

    def perform(receipt_id)
      receipt = WebhookReceipt.find(receipt_id)
      return unless receipt.claim_processing!

      result = ReconcilePayment.new(
        payment_method: receipt.payment_method,
        provider_payment_id: receipt.provider_payment_id,
        order_reference: receipt.order_reference,
        event_name: receipt.event_name
      ).call
      result.payment ? receipt.mark_processed! : receipt.mark_ignored!
    rescue => error
      receipt&.mark_failed!(error)
      raise
    end
  end
end
