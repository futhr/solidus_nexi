# frozen_string_literal: true

module SolidusNexi
  module Nexi
    class StateMapper
      Mapping = Data.define(:target_state, :reconciliation_required, :reason)

      FAILURE_EVENTS = %w[
        payment.reservation.failed
        payment.charge.failed
        payment.charge.failed.v2
        payment.cancel.failed
      ].freeze
      REFUND_PENDING_EVENTS = %w[payment.refund.initiated.v2].freeze
      REFUND_FAILURE_EVENTS = %w[payment.refund.failed].freeze
      TERMINAL_STATES = %w[completed void failed].freeze

      def map(summary:, expected_amount_minor:, event_name: nil)
        expected = Money.validate_minor!(expected_amount_minor)
        values = summary_values(summary)
        validate_summary!(values, expected)

        [
          refund_mapping(values, expected, event_name),
          charge_mapping(values, expected),
          cancel_mapping(values, expected),
          reservation_mapping(values, expected),
          failure_mapping(event_name)
        ].compact.first || mapping(nil, true, "provider_state_not_final")
      end

      def transition_allowed?(current_state, target_state)
        return true if current_state == target_state
        return false if TERMINAL_STATES.include?(current_state)

        {
          "checkout" => %w[processing pending completed void failed],
          "processing" => %w[pending completed void failed],
          "pending" => %w[completed void failed]
        }.fetch(current_state, []).include?(target_state)
      end

      private

      def refund_mapping(values, expected, event_name)
        if values[:refunded] >= expected
          return mapping("completed", false, "refunded")
        end
        if values[:refunded].positive?
          return mapping(nil, true, "unexpected_partial_refund")
        end
        return unless values[:charged] >= expected

        if REFUND_FAILURE_EVENTS.include?(event_name)
          return mapping("completed", false, "refund_failed")
        end
        mapping("completed", true, "refund_pending") if REFUND_PENDING_EVENTS.include?(event_name)
      end

      def charge_mapping(values, expected)
        return mapping("completed", false, "charged") if values[:charged] >= expected

        mapping(nil, true, "unexpected_partial_charge") if values[:charged].positive?
      end

      def cancel_mapping(values, expected)
        return mapping("void", false, "cancelled") if values[:cancelled] >= expected

        mapping(nil, true, "unexpected_partial_cancel") if values[:cancelled].positive?
      end

      def reservation_mapping(values, expected)
        return mapping("pending", false, "reserved") if values[:reserved] >= expected

        mapping(nil, true, "unexpected_partial_reservation") if values[:reserved].positive?
      end

      def failure_mapping(event_name)
        mapping("failed", false, "provider_failure") if FAILURE_EVENTS.include?(event_name)
      end

      def mapping(target_state, reconciliation_required, reason)
        Mapping.new(target_state:, reconciliation_required:, reason:)
      end

      def summary_values(summary)
        {
          reserved: integer(summary, "reservedAmount"),
          charged: integer(summary, "chargedAmount"),
          refunded: integer(summary, "refundedAmount"),
          cancelled: integer(summary, "cancelledAmount")
        }
      end

      def integer(summary, key)
        Integer(summary[key] || summary[key.to_sym] || 0)
      rescue ArgumentError, TypeError
        raise MalformedResponseError, "Nexi payment summary contains an invalid #{key}"
      end

      def validate_summary!(values, expected)
        raise MalformedResponseError, "Nexi payment summary contains a negative amount" if values.values.any?(&:negative?)
        if values[:reserved] > expected || values[:charged] + values[:cancelled] > expected
          raise MalformedResponseError, "Nexi payment summary exceeds the order amount"
        end
        if values[:refunded] > values[:charged]
          raise MalformedResponseError, "Nexi refunded amount exceeds charged amount"
        end
      end
    end
  end
end
