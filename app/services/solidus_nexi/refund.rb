# frozen_string_literal: true

module SolidusNexi
  class Refund < Mutation
    def initialize(payment:, refund:, amount_minor:)
      @refund = refund
      super(payment:, amount_minor:, logical_reference: "refund:#{refund.id}")
    end

    def call
      validate_full_refund!
      charge_id = @source.provider_charge_id.presence || latest_charge_id!
      payload = {amount: @amount_minor, provider_charge_id: charge_id}
      operation = operation(kind: :refund, payload:, idempotent: true)
      if operation.status == "succeeded" || operation.status == "reconciled"
        return Result.new(authorization: operation.provider_refund_id, provider_request_id: operation.provider_request_id)
      end

      dispatch!(operation, retry_unknown: true)
      submit_refund(operation, charge_id)
    rescue Nexi::RateLimitError => error
      retryable!(operation, error)
    rescue Nexi::TimeoutUnknownOutcome => error
      unknown!(operation, error)
    rescue Nexi::MalformedResponseError => error
      unknown!(operation, error)
    rescue ActiveRecord::ActiveRecordError => error
      persistence_unknown!(operation, error) if dispatched_after_rollback?(operation)
      raise
    rescue Nexi::Error => error
      reject!(operation, error) if operation
      raise
    end

    private

    def submit_refund(operation, charge_id)
      response = client.refund(
        charge_id:,
        amount_minor: @amount_minor,
        idempotency_key: operation.idempotency_key
      )
      refund_id = response_identifier!(response, "refundId")
      Operation.transaction do
        operation.mark_succeeded!(
          provider_request_id: response.provider_request_id,
          provider_payment_id: @source.provider_payment_id,
          provider_charge_id: charge_id,
          provider_refund_id: refund_id
        )
        @source.update!(provider_status: "refund_pending")
      end
      Result.new(authorization: refund_id, provider_request_id: response.provider_request_id)
    end

    def validate_full_refund!
      prior_refunds = @payment.refunds.where.not(id: @refund.id).sum(:amount)
      refundable = Nexi::Money.to_minor(@payment.amount - prior_refunds, @payment.currency)
      return if prior_refunds.zero? && @amount_minor == refundable

      raise Nexi::ValidationError, "partial refund is not supported"
    end

    def latest_charge_id!
      response = client.retrieve_payment(payment_id: @source.provider_payment_id)
      snapshot = Nexi::PaymentSnapshot.new(response.body, expected_payment_id: @source.provider_payment_id)
      raise Nexi::ReconciliationRequired, "Nexi payment has no charge to refund" unless snapshot.charge_id

      @source.update!(provider_charge_id: snapshot.charge_id)
      snapshot.charge_id
    end
  end
end
