# frozen_string_literal: true

require "uri"

module SolidusNexi
  class CheckoutResponse
    def self.payment_id!(response)
      value = response["paymentId"].to_s
      return value if Nexi::Client::IDENTIFIER.match?(value)

      raise Nexi::MalformedResponseError.new(
        "Nexi response contains an invalid paymentId",
        provider_request_id: response.provider_request_id
      )
    end

    def self.hosted_url!(value)
      uri = URI.parse(value.to_s)
      valid_host = uri.host == "checkout.dibspayment.eu" || uri.host == "test.checkout.dibspayment.eu" ||
        uri.host&.end_with?(".checkout.dibspayment.eu")
      unless uri.is_a?(URI::HTTPS) && valid_host && uri.userinfo.nil? && uri.to_s.length <= 2048
        raise Nexi::MalformedResponseError, "Nexi returned an invalid hosted checkout URL"
      end

      uri.to_s
    rescue URI::InvalidURIError
      raise Nexi::MalformedResponseError, "Nexi returned an invalid hosted checkout URL"
    end
  end
end
