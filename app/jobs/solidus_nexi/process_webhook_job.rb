# frozen_string_literal: true

module SolidusNexi
  class ProcessWebhookJob < ActiveJob::Base
    queue_as :default
    MAX_PROVIDER_ATTEMPTS = 5

    retry_on Nexi::ProviderUnavailableError, Nexi::TransportError,
      wait: :polynomially_longer, attempts: 5
    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
      wait: :polynomially_longer, attempts: 5

    def perform(receipt_id)
      receipt = WebhookReceipt.find(receipt_id)
      return unless receipt.claim_processing!

      result = ReconcilePayment.new(
        payment_method: receipt.payment_method,
        provider_payment_id: receipt.provider_payment_id,
        order_reference: receipt.order_reference,
        event_name: receipt.event_name,
        event_charge_id: receipt.provider_charge_id,
        event_refund_id: receipt.provider_refund_id
      ).call
      result.payment ? receipt.mark_processed! : receipt.mark_ignored!
    rescue Nexi::RateLimitError => error
      receipt&.mark_failed!(error)
      retry_rate_limit(error)
    rescue => error
      receipt&.mark_failed!(error)
      raise
    end

    private

    def retry_rate_limit(error)
      raise error if executions >= MAX_PROVIDER_ATTEMPTS

      retry_job(wait: Nexi::RetryAfter.delay(error), error:)
    end
  end
end
