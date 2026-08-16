# frozen_string_literal: true

module SolidusNexi
  module PaymentProcessing
    def authorize!
      return super unless nexi_payment?
      return true if pending? || completed?
      return unless check_payment_preconditions!

      started_processing!
      protect_from_connection_error do
        response = payment_method.authorize(money.money.cents, source, gateway_options)
        with_lock do
          reload
          return true if pending? || completed?

          pend! if handle_response(response)
        end
      end
    end

    def purchase!
      return super unless nexi_payment?
      return true if completed?
      return unless check_payment_preconditions!

      started_processing!
      protect_from_connection_error do
        response = payment_method.purchase(money.money.cents, source, gateway_options)
        with_lock do
          reload
          return true if completed?

          if handle_response(response)
            record_missing_capture!(money.money.cents)
            complete!
          end
        end
      end
    end

    def capture!(capture_amount = nil)
      return super unless nexi_payment?
      return true if completed?
      return false unless amount.positive?

      capture_amount ||= money.money.cents
      started_processing!
      protect_from_connection_error do
        response = payment_method.capture(capture_amount, response_code, gateway_options)
        with_lock do
          reload
          return true if completed?

          if handle_response(response)
            record_missing_capture!(capture_amount)
            update!(amount: captured_amount)
            complete!
          end
        end
      end
    end

    private

    def nexi_payment?
      payment_method.is_a?(SolidusNexi::PaymentMethod)
    end

    def record_missing_capture!(amount_minor)
      requested = ::Money.new(amount_minor, currency).to_d
      missing = requested - capture_events.sum(:amount)
      capture_events.create!(amount: missing) if missing.positive?
    end
  end
end
