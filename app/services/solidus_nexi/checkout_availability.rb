# frozen_string_literal: true

module SolidusNexi
  class CheckoutAvailability
    Result = Data.define(:payment, :error)
    REPLACEMENT_SAFETY_MARGIN = 5.minutes

    def initialize(payments:, amount:, context_fingerprint:)
      @payments = payments
      @amount = amount
      @context_fingerprint = context_fingerprint
    end

    def call
      open_payments = @payments.select { |payment| payment.source.checkout_open? }
      return open_checkout_result(open_payments) if open_payments.any?

      @payments.each do |payment|
        source = payment.source
        next unless source.provider_payment_id.present? && source.hosted_payment_page_url.present?

        safely_expired = source.checkout_expires_at &&
          source.checkout_expires_at < REPLACEMENT_SAFETY_MARGIN.ago
        unless payment.checkout? && safely_expired
          source.update!(provider_status: "checkout_replacement_blocked", reconciliation_required: true)
          return Result.new(payment: nil, error: :replacement_blocked)
        end

        payment.invalidate! if payment.can_invalidate?
        source.update!(
          hosted_payment_page_url: nil,
          provider_status: "checkout_expired",
          reconciliation_required: false
        )
      end
      Result.new(payment: nil, error: nil)
    end

    private

    def open_checkout_result(open_payments)
      matching = open_payments.select do |payment|
        payment.amount == @amount &&
          payment.source.checkout_context_fingerprint == @context_fingerprint
      end
      return Result.new(payment: matching.first, error: nil) if open_payments.one? && matching.one?

      open_payments.each do |payment|
        payment.source.update!(provider_status: "checkout_context_stale", reconciliation_required: true)
      end
      Result.new(payment: nil, error: :stale_checkout)
    end
  end
end
