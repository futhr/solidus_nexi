# frozen_string_literal: true

module SolidusNexi
  # Called under the payment lock so concurrent retrievals cannot duplicate records.
  class ReconcileFinancialRecords
    def initialize(payment:, snapshot:)
      @payment = payment
      @snapshot = snapshot
    end

    def call
      amounts = @snapshot.amounts
      captured_minor = Nexi::Money.to_minor(@payment.capture_events.sum(:amount), @payment.currency)
      if amounts[:charged] > captured_minor
        @payment.capture_events.create!(amount: decimal_amount(amounts[:charged] - captured_minor))
      end

      refunded_minor = Nexi::Money.to_minor(@payment.refunds.sum(:amount), @payment.currency)
      return unless amounts[:refunded] > refunded_minor

      refund_id = @snapshot.completed_refund_id || @snapshot.refund_id
      raise Nexi::ReconciliationRequired, "Nexi refund is missing its identifier" unless refund_id

      reason = Spree::RefundReason.where(name: "Nexi reconciliation").first_or_create!
      @payment.refunds.create!(
        amount: decimal_amount(amounts[:refunded] - refunded_minor),
        reason:,
        transaction_id: refund_id
      )
    end

    private

    def decimal_amount(amount_minor)
      BigDecimal(amount_minor.to_s) / 100
    end
  end
end
