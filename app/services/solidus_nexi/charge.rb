# frozen_string_literal: true

module SolidusNexi
  class Charge < Mutation
    def call
      validate_full_capture!
      payload = {amount: @amount_minor, provider_payment_id: @source.provider_payment_id}
      operation = operation(kind: :charge, payload:, idempotent: true)
      if operation.status == "succeeded" || operation.status == "reconciled"
        return Result.new(authorization: operation.provider_charge_id || @source.provider_charge_id,
          provider_request_id: operation.provider_request_id)
      end

      dispatch!(operation, retry_unknown: true)
      response = client.charge(
        payment_id: @source.provider_payment_id,
        amount_minor: @amount_minor,
        idempotency_key: operation.idempotency_key
      )
      charge_id = response_identifier!(response, "chargeId")
      Operation.transaction do
        operation.mark_succeeded!(
          provider_request_id: response.provider_request_id,
          provider_payment_id: @source.provider_payment_id,
          provider_charge_id: charge_id
        )
        @source.update!(provider_charge_id: charge_id, provider_status: "charged")
      end
      Result.new(authorization: charge_id, provider_request_id: response.provider_request_id)
    rescue Nexi::TimeoutUnknownOutcome => error
      unknown!(operation, error)
    rescue Nexi::MalformedResponseError => error
      unknown!(operation, error)
    rescue ActiveRecord::ActiveRecordError => error
      persistence_unknown!(operation, error) if operation&.status == "dispatched"
      raise
    rescue Nexi::Error => error
      reject!(operation, error) if operation
      raise
    end

    private

    def validate_full_capture!
      full_amount = Nexi::Money.to_minor(@payment.uncaptured_amount, @payment.currency)
      return if @amount_minor == full_amount

      raise Nexi::ValidationError, "partial capture is not supported"
    end
  end
end
