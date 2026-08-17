# frozen_string_literal: true

module SolidusNexi
  class ReconcilePaymentJob < ActiveJob::Base
    queue_as :default
    MAX_PROVIDER_ATTEMPTS = 5

    retry_on Nexi::ProviderUnavailableError, Nexi::TransportError,
      wait: :polynomially_longer, attempts: 5

    def perform(source_id, provider_payment_id: nil)
      source = PaymentSource.find(source_id)
      ReconcilePayment.new(source:, provider_payment_id:).call
    rescue Nexi::RateLimitError => error
      raise error if executions >= MAX_PROVIDER_ATTEMPTS

      retry_job(wait: Nexi::RetryAfter.delay(error), error:)
    end
  end
end
