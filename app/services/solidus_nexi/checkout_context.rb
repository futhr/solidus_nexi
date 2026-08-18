# frozen_string_literal: true

require "digest"

module SolidusNexi
  class CheckoutContext
    def self.fingerprint(order:, amount:, currency:)
      amount_minor = Nexi::Money.to_minor(amount, currency)
      serialized = OrderSerializer.new(order).call(amount_minor:)
      Digest::SHA256.hexdigest(Nexi::CanonicalJson.generate(serialized))
    end

    def self.verify!(payment:, source:)
      return unless Operation.exists?(payment:, kind: "create")

      expected = source.checkout_context_fingerprint
      if expected.blank?
        mark_conflict!(source, "checkout_context_missing")
        raise Nexi::ReconciliationRequired,
          "Nexi checkout predates canonical order-context verification"
      end

      actual = fingerprint(order: payment.order, amount: payment.amount, currency: payment.currency)
      return if expected == actual

      mark_conflict!(source, "checkout_context_conflict")
      raise Nexi::ConflictError, "Nexi checkout was created for a different order context"
    end

    def self.mark_conflict!(source, status)
      source.update!(provider_status: status, reconciliation_required: true, last_reconciled_at: Time.current)
    end
    private_class_method :mark_conflict!
  end
end
