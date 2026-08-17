# frozen_string_literal: true

module SolidusNexi
  class Cancel < Mutation
    def call
      validate_full_cancel!
      payload = {amount: @amount_minor, provider_payment_id: @source.provider_payment_id}
      operation = operation(kind: :cancel, payload:, idempotent: false)
      if operation.status == "succeeded" || operation.status == "reconciled"
        return Result.new(authorization: @source.provider_payment_id, provider_request_id: operation.provider_request_id)
      end
      if operation.status == "unknown"
        raise Nexi::ReconciliationRequired, "the previous Nexi cancellation must be reconciled"
      end

      dispatch!(operation)
      submit_cancel(operation)
    rescue Nexi::RateLimitError => error
      retryable!(operation, error)
    rescue Nexi::TimeoutUnknownOutcome => error
      unknown!(operation, error)
    rescue Nexi::Error => error
      reject!(operation, error) if operation
      raise
    rescue ActiveRecord::ActiveRecordError => error
      persistence_unknown!(operation, error) if dispatched_after_rollback?(operation)
      raise
    end

    private

    def submit_cancel(operation)
      response = client.cancel(payment_id: @source.provider_payment_id, amount_minor: @amount_minor)
      Operation.transaction do
        operation.mark_succeeded!(
          provider_request_id: response.provider_request_id,
          provider_payment_id: @source.provider_payment_id
        )
        @source.update!(provider_status: "cancelled", cancelled_amount_minor: @amount_minor)
      end
      Result.new(authorization: @source.provider_payment_id, provider_request_id: response.provider_request_id)
    end

    def validate_full_cancel!
      full_amount = Nexi::Money.to_minor(@payment.amount, @payment.currency)
      return if @amount_minor == full_amount && @source.charged_amount_minor.zero?

      raise Nexi::ValidationError, "partial cancellation is not supported"
    end
  end
end
