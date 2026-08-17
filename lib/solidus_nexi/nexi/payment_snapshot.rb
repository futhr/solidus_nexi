# frozen_string_literal: true

module SolidusNexi
  module Nexi
    class PaymentSnapshot
      attr_reader :payment_id, :summary, :amount_minor, :currency, :order_reference, :my_reference,
        :charge_id, :refund_id, :refunds

      def initialize(body, expected_payment_id: nil)
        payment = body.fetch("payment")
        raise MalformedResponseError, "Nexi payment response is missing payment" unless payment.is_a?(Hash)

        @payment_id = required_string(payment, "paymentId")
        if expected_payment_id && @payment_id != expected_payment_id
          raise MalformedResponseError, "Nexi returned a different payment"
        end

        @summary = payment.fetch("summary")
        raise MalformedResponseError, "Nexi payment response is missing summary" unless @summary.is_a?(Hash)

        order = payment.fetch("orderDetails")
        raise MalformedResponseError, "Nexi payment response is missing order details" unless order.is_a?(Hash)

        @amount_minor = positive_integer(order, "amount")
        @currency = Money.validate_currency!(order.fetch("currency"))
        @order_reference = bounded_optional_string(order["reference"], "reference")
        @my_reference = bounded_optional_string(payment["myReference"], "myReference")
        @charge_id = latest_identifier(payment["charges"], "chargeId")
        @refunds = Array(payment["refunds"]).select { |refund| refund.is_a?(Hash) }
        @refund_id = latest_identifier(@refunds, "refundId")
      rescue KeyError
        raise MalformedResponseError, "Nexi payment response is missing required fields"
      end

      def amounts
        {
          reserved: nonnegative_integer(summary, "reservedAmount"),
          charged: nonnegative_integer(summary, "chargedAmount"),
          refunded: nonnegative_integer(summary, "refundedAmount"),
          cancelled: nonnegative_integer(summary, "cancelledAmount")
        }
      end

      def completed_refund_id
        completed = refunds.reverse.find { |refund| refund_state(refund) == "completed" }
        completed && required_string(completed, "refundId")
      end

      def refund_state_for(refund_id)
        refund = refund_by_id(refund_id)
        refund && refund_state(refund)
      end

      def refund_id_with_state(*states)
        expected_states = states.map { |state| state.to_s.downcase }
        refund = refunds.reverse.find { |candidate| expected_states.include?(refund_state(candidate)) }
        refund && required_string(refund, "refundId")
      end

      private

      def latest_identifier(collection, key)
        entry = Array(collection).reverse.find { |value| value.is_a?(Hash) && value[key].present? }
        entry && required_string(entry, key)
      end

      def refund_by_id(refund_id)
        return unless Client::IDENTIFIER.match?(refund_id.to_s)

        refunds.reverse.find { |refund| refund["refundId"].to_s == refund_id.to_s }
      end

      def refund_state(refund)
        state = bounded_optional_string(refund["state"], "refund state")
        state&.downcase
      end

      def required_string(object, key)
        value = object.fetch(key).to_s
        raise MalformedResponseError, "Nexi payment response contains an invalid #{key}" unless Client::IDENTIFIER.match?(value)

        value
      end

      def positive_integer(object, key)
        value = Integer(object.fetch(key))
        raise MalformedResponseError, "Nexi payment response contains an invalid #{key}" unless value.positive?

        value
      rescue ArgumentError, TypeError
        raise MalformedResponseError, "Nexi payment response contains an invalid #{key}"
      end

      def nonnegative_integer(object, key)
        value = Integer(object[key] || 0)
        raise MalformedResponseError, "Nexi payment response contains an invalid #{key}" if value.negative?

        value
      rescue ArgumentError, TypeError
        raise MalformedResponseError, "Nexi payment response contains an invalid #{key}"
      end

      def bounded_optional_string(value, key)
        return if value.nil? || value.to_s.empty?

        string = value.to_s
        if string.bytesize > 128 || string.include?("\0")
          raise MalformedResponseError, "Nexi payment response contains an invalid #{key}"
        end

        string
      end
    end
  end
end
