# frozen_string_literal: true

require "json"
require "time"

require "solidus_nexi/nexi/webhook/event"

module SolidusNexi
  module Nexi
    module Webhook
      class Parser
        MAX_BYTES = 65_536
        EVENT_ID = /\A[0-9A-Za-z-]{1,128}\z/
        EVENT_NAME = /\Apayment\.[a-z0-9_.-]{1,120}\z/
        MERCHANT_ID = /\A[0-9]{1,20}\z/

        def parse(payload)
          raise ValidationError, "webhook payload is too large" if payload.to_s.bytesize > MAX_BYTES

          envelope = JSON.parse(payload)
          raise ValidationError, "webhook payload must be an object" unless envelope.is_a?(Hash)

          data = required_hash(envelope, "data")
          Event.new(
            id: required_string(envelope, "id", EVENT_ID),
            name: required_string(envelope, "event", EVENT_NAME),
            occurred_at: parse_time(envelope.fetch("timestamp")),
            merchant_id: required_string(envelope, "merchantId", MERCHANT_ID),
            merchant_number: optional_string(envelope["merchantNumber"], pattern: MERCHANT_ID),
            payment_id: required_string(data, "paymentId", EVENT_ID),
            charge_id: optional_string(data["chargeId"], pattern: EVENT_ID),
            refund_id: optional_string(data["refundId"], pattern: EVENT_ID),
            order_reference: optional_string(
              data.dig("order", "reference") || data["orderReference"],
              maximum_bytes: 128
            )
          )
        rescue JSON::ParserError
          raise ValidationError, "webhook payload is not valid JSON"
        rescue KeyError, TypeError
          raise ValidationError, "webhook payload is missing required fields"
        end

        private

        def required_hash(object, key)
          value = object.fetch(key)
          raise ValidationError, "#{key} must be an object" unless value.is_a?(Hash)

          value
        end

        def required_string(object, key, pattern)
          value = object.fetch(key).to_s
          raise ValidationError, "#{key} has an invalid format" unless pattern.match?(value)

          value
        end

        def optional_string(value, pattern: nil, maximum_bytes: nil)
          return if value.nil? || value.to_s.empty?

          string = value.to_s
          valid = string.exclude?("\0") && (!pattern || pattern.match?(string)) &&
            (!maximum_bytes || string.bytesize <= maximum_bytes)
          raise ValidationError, "optional webhook field has an invalid format" unless valid

          string
        end

        def parse_time(value)
          Time.iso8601(value.to_s)
        rescue ArgumentError
          raise ValidationError, "timestamp is not ISO 8601"
        end
      end
    end
  end
end
