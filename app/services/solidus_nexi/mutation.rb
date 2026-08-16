# frozen_string_literal: true

require "digest"

module SolidusNexi
  class Mutation
    Result = Data.define(:authorization, :provider_request_id)

    def initialize(payment:, amount_minor:, logical_reference:)
      @payment = payment
      @source = payment.source
      @payment_method = payment.payment_method
      @amount_minor = Nexi::Money.validate_minor!(amount_minor)
      @logical_reference = logical_reference.to_s
      validate_payment!
    end

    private

    def operation(kind:, payload:, idempotent:)
      Operation.create_or_find_intent!(
        payment: @payment,
        kind:,
        logical_reference: @logical_reference,
        amount_minor: @amount_minor,
        currency: @payment.currency,
        request_fingerprint: fingerprint(payload),
        idempotency_key: idempotent ? SolidusNexi.configuration.idempotency_key_generator.call(kind) : nil
      ).tap do |record|
        unless record.request_fingerprint == fingerprint(payload)
          raise Nexi::ConflictError, "the persisted Nexi operation does not match this request"
        end
      end
    end

    def dispatch!(operation, retry_unknown: false)
      return operation if operation.status == "succeeded" || operation.status == "reconciled"
      unless operation.claim_dispatch!(retry_unknown:)
        raise Nexi::OperationInProgress, "the Nexi operation is already in progress"
      end

      operation
    end

    def unknown!(operation, error)
      operation.mark_unknown!(error)
      ReconcilePaymentJob.perform_later(@source.id)
      raise Nexi::ReconciliationRequired, "Nexi accepted the request but its outcome is unknown"
    end

    def reject!(operation, error)
      deferred = error.is_a?(Nexi::OperationInProgress) || error.is_a?(Nexi::ReconciliationRequired)
      operation.mark_rejected!(error) if operation.status == "dispatched" && !deferred
      raise error
    end

    def persistence_unknown!(operation, error)
      operation.mark_unknown!(error)
      ReconcilePaymentJob.perform_later(@source.id) if @source.provider_payment_id.present?
      raise Nexi::ReconciliationRequired, "Nexi succeeded but local persistence must be reconciled"
    end

    def client
      @client ||= SolidusNexi.configuration.client_factory.call(@payment_method)
    end

    def fingerprint(payload)
      Digest::SHA256.hexdigest(Nexi::CanonicalJson.generate(payload))
    end

    def validate_payment!
      unless @source.is_a?(PaymentSource) && @source.provider_payment_id.present?
        raise Nexi::ValidationError, "payment is missing its Nexi payment ID"
      end
    end

    def response_identifier!(response, key)
      value = response[key].to_s
      unless Nexi::Client::IDENTIFIER.match?(value)
        raise Nexi::MalformedResponseError.new(
          "Nexi response contains an invalid #{key}",
          provider_request_id: response.provider_request_id
        )
      end

      value
    end
  end
end
