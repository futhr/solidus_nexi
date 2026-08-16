# frozen_string_literal: true

module SolidusNexi
  class ReconcilePaymentJob < ActiveJob::Base
    queue_as :default

    retry_on Nexi::RateLimitError, Nexi::ProviderUnavailableError, Nexi::TransportError,
      wait: :polynomially_longer, attempts: 5

    def perform(source_id)
      source = PaymentSource.find(source_id)
      ReconcilePayment.new(source:).call
    end
  end
end
