# frozen_string_literal: true

require "digest"
require "uri"

module SolidusNexi
  class CreateCheckout
    Result = Data.define(:payment, :source, :provider_payment_id, :hosted_payment_page_url, :reused)
    CHECKOUT_LIFETIME = 48.hours

    def initialize(order:, payment_method:, webhook_url:, return_url_for:, cancel_url_for:)
      @order = order
      @payment_method = payment_method
      @webhook_url = webhook_url
      @return_url_for = return_url_for
      @cancel_url_for = cancel_url_for
    end

    def call
      prepared = prepare_local_operation
      return prepared if prepared.is_a?(Result)

      payment, source, payload, operation = prepared

      response = client.create_payment(payload:)
      provider_payment_id = response_identifier!(response, "paymentId")
      hosted_url = validate_hosted_url!(response["hostedPaymentPageUrl"])

      Operation.transaction do
        source.update!(
          provider_payment_id:,
          hosted_payment_page_url: hosted_url,
          checkout_expires_at: Time.current + CHECKOUT_LIFETIME,
          provider_status: "created"
        )
        payment.update!(response_code: provider_payment_id)
        operation.mark_succeeded!(provider_request_id: response.provider_request_id, provider_payment_id:)
      end

      Result.new(
        payment:,
        source:,
        provider_payment_id:,
        hosted_payment_page_url: hosted_url,
        reused: false
      )
    rescue Nexi::TimeoutUnknownOutcome => error
      operation&.mark_unknown!(error)
      enqueue_reconciliation(source)
      raise Nexi::ReconciliationRequired, "Nexi checkout creation has an unknown outcome"
    rescue Nexi::MalformedResponseError => error
      operation&.mark_unknown!(error)
      enqueue_reconciliation(source)
      raise Nexi::ReconciliationRequired, "Nexi checkout creation has an unknown outcome"
    rescue Nexi::Error => error
      unless error.is_a?(Nexi::OperationInProgress) || error.is_a?(Nexi::ReconciliationRequired)
        operation&.mark_rejected!(error) if operation&.status == "dispatched"
        payment&.invalidate! if payment&.can_invalidate?
      end
      raise
    rescue ActiveRecord::ActiveRecordError => error
      if operation&.status == "dispatched"
        operation.mark_unknown!(error)
        enqueue_reconciliation(source)
        raise Nexi::ReconciliationRequired, "Nexi succeeded but local persistence must be reconciled"
      end
      raise
    end

    private

    def prepare_local_operation
      @order.with_lock do
        @order.reload
        if (existing = reusable_checkout)
          return Result.new(
            payment: existing,
            source: existing.source,
            provider_payment_id: existing.source.provider_payment_id,
            hosted_payment_page_url: existing.source.hosted_payment_page_url,
            reused: true
          )
        end

        reject_unresolved_create!
        payment, source = persist_local_intent
        payload = checkout_payload(payment, source)
        operation = create_operation(payment, payload)
        unless operation.claim_dispatch!
          raise Nexi::OperationInProgress, "checkout creation is already in progress"
        end

        [payment, source, payload, operation]
      end
    end

    def reusable_checkout
      current_payments.find do |payment|
        payment.amount == payment_amount && payment.source.checkout_open?
      end
    end

    def reject_unresolved_create!
      unresolved = current_payments.filter_map do |payment|
        Operation.where(payment:, kind: "create", status: %w[pending dispatched unknown]).first
      end.first
      return unless unresolved

      if unresolved.status == "unknown" || unresolved.dispatched_at&.<(5.minutes.ago)
        raise Nexi::ReconciliationRequired, "a previous checkout creation must be reconciled before retrying"
      end

      raise Nexi::OperationInProgress, "checkout creation is already in progress"
    end

    def current_payments
      @order.payments
        .where(payment_method: @payment_method, source_type: "SolidusNexi::PaymentSource")
        .where(state: %w[checkout processing pending])
        .includes(:source)
        .order(created_at: :desc)
    end

    def persist_local_intent
      source = PaymentSource.create!(payment_method: @payment_method, currency: @order.currency)
      payment = @order.payments.create!(
        payment_method: @payment_method,
        source:,
        amount: payment_amount
      )
      [payment, source]
    end

    def payment_amount
      @payment_amount ||= @order.order_total_after_store_credit
    end

    def checkout_payload(payment, source)
      CheckoutPayload.new(
        order: @order,
        payment:,
        payment_method: @payment_method,
        webhook_url: @webhook_url,
        return_url: @return_url_for.call(source),
        cancel_url: @cancel_url_for.call(source)
      ).call
    end

    def create_operation(payment, payload)
      amount_minor = Nexi::Money.to_minor(payment.amount, payment.currency)
      fingerprint = Digest::SHA256.hexdigest(Nexi::CanonicalJson.generate(payload))
      operation = Operation.create_or_find_intent!(
        payment:,
        kind: :create,
        logical_reference: "checkout:#{payment.number}",
        amount_minor:,
        currency: payment.currency,
        request_fingerprint: fingerprint
      )
      unless operation.request_fingerprint == fingerprint
        raise Nexi::ConflictError, "checkout intent changed after it was persisted"
      end

      operation
    end

    def validate_hosted_url!(value)
      uri = URI.parse(value.to_s)
      valid_host = uri.host == "checkout.dibspayment.eu" || uri.host == "test.checkout.dibspayment.eu" ||
        uri.host&.end_with?(".checkout.dibspayment.eu")
      unless uri.is_a?(URI::HTTPS) && valid_host && uri.userinfo.nil? && uri.to_s.length <= 2048
        raise Nexi::MalformedResponseError, "Nexi returned an invalid hosted checkout URL"
      end

      uri.to_s
    rescue URI::InvalidURIError
      raise Nexi::MalformedResponseError, "Nexi returned an invalid hosted checkout URL"
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

    def client
      @client ||= SolidusNexi.configuration.client_factory.call(@payment_method)
    end

    def enqueue_reconciliation(source)
      ReconcilePaymentJob.perform_later(source.id) if source&.persisted? && source.provider_payment_id.present?
    end
  end
end
