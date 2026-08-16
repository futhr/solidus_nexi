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
      TERMINAL_STATES = %w[completed void failed].freeze

      def map(summary:, expected_amount_minor:, event_name: nil)
        expected = Money.validate_minor!(expected_amount_minor)
        values = summary_values(summary)
        validate_summary!(values, expected)

        return Mapping.new(target_state: "completed", reconciliation_required: false, reason: "charged") if values[:charged] >= expected
        if values[:charged].positive?
          return Mapping.new(target_state: nil, reconciliation_required: true, reason: "unexpected_partial_charge")
        end
        return Mapping.new(target_state: "void", reconciliation_required: false, reason: "cancelled") if values[:cancelled] >= expected
        if values[:cancelled].positive?
          return Mapping.new(target_state: nil, reconciliation_required: true, reason: "unexpected_partial_cancel")
        end
        return Mapping.new(target_state: "pending", reconciliation_required: false, reason: "reserved") if values[:reserved] >= expected
        if values[:reserved].positive?
          return Mapping.new(target_state: nil, reconciliation_required: true, reason: "unexpected_partial_reservation")
        end
        if FAILURE_EVENTS.include?(event_name)
          return Mapping.new(target_state: "failed", reconciliation_required: false, reason: "provider_failure")
        end

        Mapping.new(target_state: nil, reconciliation_required: true, reason: "provider_state_not_final")
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
