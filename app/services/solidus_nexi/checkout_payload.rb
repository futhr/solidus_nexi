# frozen_string_literal: true

require "uri"

module SolidusNexi
  class CheckoutPayload
    WEBHOOK_EVENTS = %w[
      payment.created
      payment.checkout.completed
      payment.reservation.created.v2
      payment.reservation.failed
      payment.charge.created.v2
      payment.charge.failed.v2
      payment.cancel.created
      payment.cancel.failed
      payment.refund.initiated.v2
      payment.refund.completed
      payment.refund.failed
    ].freeze

    def initialize(order:, payment:, payment_method:, webhook_url:, return_url:, cancel_url:)
      @order = order
      @payment = payment
      @payment_method = payment_method
      @webhook_url = secure_url!(webhook_url, "webhook_url")
      @return_url = secure_url!(return_url, "return_url")
      @cancel_url = secure_url!(cancel_url, "cancel_url")
      @terms_url = secure_url!(payment_method.preferred_terms_url, "terms_url")
      @merchant_terms_url = optional_secure_url(payment_method.preferred_merchant_terms_url, "merchant_terms_url")
      @webhook_secret = webhook_secret!(payment_method.preferred_webhook_secret)
    end

    def call
      amount_minor = Nexi::Money.to_minor(@payment.amount, @order.currency)
      {
        order: OrderSerializer.new(@order).call(amount_minor:),
        checkout: checkout,
        notifications: {webHooks: webhooks},
        myReference: @payment.number.to_s.slice(0, 36)
      }
    end

    private

    def checkout
      {
        integrationType: "HostedPaymentPage",
        returnUrl: @return_url,
        cancelUrl: @cancel_url,
        termsUrl: @terms_url,
        merchantTermsUrl: @merchant_terms_url,
        charge: @payment_method.auto_capture?,
        countryCode: @payment_method.preferred_checkout_country
      }.compact
    end

    def webhooks
      WEBHOOK_EVENTS.map do |event_name|
        {
          eventName: event_name,
          url: @webhook_url,
          authorization: @webhook_secret
        }
      end
    end

    def optional_secure_url(value, name)
      secure_url!(value, name) if value.present?
    end

    def webhook_secret!(value)
      secret = value.to_s
      unless PaymentMethod::WEBHOOK_SECRET.match?(secret)
        raise Nexi::ConfigurationError, "webhook_secret must contain 8-64 alphanumeric characters"
      end

      secret
    end

    def secure_url!(value, name)
      uri = URI.parse(value.to_s)
      unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && value.to_s.length <= 256
        raise Nexi::ConfigurationError, "#{name} must be an HTTPS URL of at most 256 characters"
      end

      uri.to_s
    rescue URI::InvalidURIError
      raise Nexi::ConfigurationError, "#{name} must be a valid HTTPS URL"
    end
  end
end
