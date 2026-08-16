# frozen_string_literal: true

require "bigdecimal"

module SolidusNexi
  module Nexi
    module Money
      SUPPORTED_CURRENCIES = %w[CHF CZK DKK EUR GBP NOK PLN SEK USD].freeze
      EXPONENT = 2

      module_function

      def to_minor(amount, currency)
        validate_currency!(currency)
        decimal = BigDecimal(amount.to_s)
        scaled = decimal * (10**EXPONENT)
        raise ValidationError, "amount has more than two decimal places" unless scaled.frac.zero?

        validate_signed_minor!(scaled.to_i)
      rescue ArgumentError
        raise ValidationError, "amount is not a decimal value"
      end

      def validate_minor!(amount_minor)
        unless amount_minor.is_a?(Integer) && amount_minor.positive? && amount_minor <= 2_147_483_647
          raise ValidationError, "amount_minor must be a positive 32-bit integer"
        end

        amount_minor
      end

      def validate_signed_minor!(amount_minor)
        unless amount_minor.is_a?(Integer) && amount_minor.between?(-2_147_483_648, 2_147_483_647)
          raise ValidationError, "amount_minor must be a 32-bit integer"
        end

        amount_minor
      end

      def validate_currency!(currency)
        normalized = currency.to_s.upcase
        raise ValidationError, "currency is not supported by Nexi Checkout" unless SUPPORTED_CURRENCIES.include?(normalized)

        normalized
      end
    end
  end
end
