# frozen_string_literal: true

require "time"

module SolidusNexi
  module Nexi
    module RetryAfter
      DEFAULT_DELAY = 30
      MINIMUM_DELAY = 1
      MAXIMUM_DELAY = 3_600

      def self.delay(error, now: Time.now.utc)
        value = error.respond_to?(:retry_after) ? error.retry_after.to_s.strip : ""
        seconds = Integer(value, 10, exception: false)
        seconds ||= (Time.httpdate(value) - now).ceil unless value.empty?
        (seconds || DEFAULT_DELAY).clamp(MINIMUM_DELAY, MAXIMUM_DELAY)
      rescue ArgumentError
        DEFAULT_DELAY
      end
    end
  end
end
