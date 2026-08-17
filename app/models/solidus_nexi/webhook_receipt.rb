# frozen_string_literal: true

module SolidusNexi
  class WebhookReceipt < ::Spree::Base
    self.table_name = "solidus_nexi_webhook_receipts"

    STATUSES = %w[received enqueued processing processed ignored failed].freeze

    belongs_to :payment_method, class_name: "SolidusNexi::PaymentMethod"

    validates :event_id, :event_name, :provider_payment_id, :merchant_id, :occurred_at, presence: true
    validates :event_id, uniqueness: {scope: :payment_method_id}
    validates :status, inclusion: {in: STATUSES}

    def self.record!(payment_method:, event:)
      receipt = create!(
        payment_method:,
        event_id: event.id,
        event_name: event.name,
        provider_payment_id: event.payment_id,
        provider_charge_id: event.charge_id,
        provider_refund_id: event.refund_id,
        order_reference: event.order_reference,
        merchant_id: event.merchant_id,
        occurred_at: event.occurred_at
      )
      [receipt, true]
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      [find_by!(payment_method:, event_id: event.id), false]
    end

    def claim_processing!
      with_lock do
        return false if %w[processed ignored].include?(status)
        return false if status == "processing" && updated_at > 5.minutes.ago

        update!(status: "processing", attempts: attempts + 1, error_class: nil)
        true
      end
    end

    def mark_enqueued!
      update!(status: "enqueued") if enqueue_required?
    end

    def enqueue_required?
      return true if status == "received" || status == "failed"

      %w[enqueued processing].include?(status) && updated_at <= 5.minutes.ago
    end

    def mark_processed!
      update!(status: "processed", processed_at: Time.current, error_class: nil)
    end

    def mark_ignored!
      update!(status: "ignored", processed_at: Time.current, error_class: nil)
    end

    def mark_failed!(error)
      update!(status: "failed", error_class: error.class.name)
    end
  end
end
