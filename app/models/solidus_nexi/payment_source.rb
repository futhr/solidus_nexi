# frozen_string_literal: true

module SolidusNexi
  class PaymentSource < ::Spree::PaymentSource
    self.table_name = "solidus_nexi_payment_sources"

    belongs_to :payment_method, class_name: "SolidusNexi::PaymentMethod"

    validates :currency, inclusion: {in: Nexi::Money::SUPPORTED_CURRENCIES}
    validates :return_token, presence: true, uniqueness: true
    validates :provider_payment_id, uniqueness: {scope: :payment_method_id}, allow_nil: true
    validates :reserved_amount_minor, :charged_amount_minor, :refunded_amount_minor,
      :cancelled_amount_minor, numericality: {only_integer: true, greater_than_or_equal_to: 0}

    before_validation :assign_return_token, on: :create

    scope :requiring_reconciliation, -> { where(reconciliation_required: true) }

    def actions
      %w[capture void credit]
    end

    def can_capture?(payment)
      payment.pending? && payment.uncaptured_amount.positive?
    end

    def can_void?(payment)
      payment.pending?
    end

    def can_credit?(payment)
      payment.completed? && payment.credit_allowed.positive?
    end

    def reusable?
      false
    end

    def checkout_open?(at: Time.current)
      provider_payment_id.present? && hosted_payment_page_url.present? && checkout_expires_at && checkout_expires_at > at
    end

    private

    def assign_return_token
      self.return_token ||= SecureRandom.hex(24)
    end
  end
end
