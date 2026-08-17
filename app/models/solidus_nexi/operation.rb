# frozen_string_literal: true

module SolidusNexi
  class Operation < ::Spree::Base
    self.table_name = "solidus_nexi_operations"

    KINDS = %w[create charge cancel refund].freeze
    STATUSES = %w[pending dispatched succeeded rejected unknown reconciled].freeze
    IDEMPOTENT_KINDS = %w[charge refund].freeze

    belongs_to :payment, class_name: "Spree::Payment"

    validates :kind, inclusion: {in: KINDS}
    validates :status, inclusion: {in: STATUSES}
    validates :logical_reference, :request_fingerprint, :currency, presence: true
    validates :amount_minor, numericality: {only_integer: true, greater_than: 0}
    validates :idempotency_key, uniqueness: true, allow_nil: true, length: {maximum: 64}
    validates :logical_reference, uniqueness: {scope: %i[payment_id kind]}
    validate :idempotency_key_matches_kind

    scope :requiring_reconciliation, -> { where(reconciliation_required: true) }

    def self.create_or_find_intent!(payment:, kind:, logical_reference:, amount_minor:, currency:,
      request_fingerprint:, idempotency_key: nil)
      existing = find_by(payment:, kind: kind.to_s, logical_reference:)
      return existing if existing

      create!(
        payment:,
        kind: kind.to_s,
        logical_reference:,
        amount_minor:,
        currency: currency.to_s.upcase,
        request_fingerprint:,
        idempotency_key:
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      find_by(payment:, kind: kind.to_s, logical_reference:) || raise
    end

    def claim_dispatch!(retry_unknown: false)
      with_lock do
        dispatchable = status == "pending" || (retry_unknown && status == "unknown" && idempotency_key.present?)
        return false unless dispatchable

        update!(status: "dispatched", dispatched_at: Time.current, reconciliation_required: false)
        true
      end
    end

    def mark_succeeded!(provider_request_id: nil, provider_payment_id: nil,
      provider_charge_id: nil, provider_refund_id: nil)
      update!(
        status: "succeeded",
        provider_request_id:,
        provider_payment_id: provider_payment_id || self.provider_payment_id,
        provider_charge_id: provider_charge_id || self.provider_charge_id,
        provider_refund_id: provider_refund_id || self.provider_refund_id,
        reconciliation_required: false,
        completed_at: Time.current
      )
    end

    def mark_rejected!(error)
      update!(
        status: "rejected",
        provider_request_id: safe_error_attribute(error, :provider_request_id),
        provider_code: safe_error_attribute(error, :provider_code),
        reconciliation_required: false,
        completed_at: Time.current
      )
    end

    def mark_unknown!(error)
      update!(
        status: "unknown",
        provider_request_id: safe_error_attribute(error, :provider_request_id),
        provider_code: safe_error_attribute(error, :provider_code) || error.class.name,
        reconciliation_required: true
      )
    end

    def mark_retryable!(error)
      update!(
        status: "pending",
        provider_request_id: safe_error_attribute(error, :provider_request_id),
        provider_code: safe_error_attribute(error, :provider_code),
        reconciliation_required: false,
        dispatched_at: nil,
        completed_at: nil
      )
    end

    def mark_reconciled!
      update!(status: "reconciled", reconciliation_required: false, completed_at: Time.current)
    end

    private

    def safe_error_attribute(error, attribute)
      error.public_send(attribute) if error.respond_to?(attribute)
    end

    def idempotency_key_matches_kind
      if IDEMPOTENT_KINDS.include?(kind) && idempotency_key.blank?
        errors.add(:idempotency_key, "is required for #{kind}")
      elsif IDEMPOTENT_KINDS.exclude?(kind) && idempotency_key.present?
        errors.add(:idempotency_key, "is not supported by Nexi for #{kind}")
      end
    end
  end
end
