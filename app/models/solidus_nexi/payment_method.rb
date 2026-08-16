# frozen_string_literal: true

module SolidusNexi
  class PaymentMethod < ::Spree::PaymentMethod
    WEBHOOK_SECRET = /\A[0-9A-Za-z]{8,64}\z/

    preference :api_key, :encrypted_string
    preference :webhook_secret, :encrypted_string
    preference :previous_webhook_secret, :encrypted_string
    preference :checkout_country, :string, default: "SWE"
    preference :terms_url, :string
    preference :merchant_terms_url, :string

    validates :preferred_checkout_country, format: {with: /\A[A-Z]{3}\z/}
    validate :webhook_secret_format

    def partial_name
      "nexi_checkout"
    end

    alias_method :cart_partial_name, :partial_name
    alias_method :product_page_partial_name, :partial_name
    alias_method :risky_partial_name, :partial_name

    def source_required?
      true
    end

    def payment_source_class
      PaymentSource
    end

    def gateway_class
      Gateway
    end

    def payment_profiles_supported?
      false
    end

    def admin_form_preference_names
      super - %i[api_key webhook_secret previous_webhook_secret]
    end

    def build_client
      Nexi::Client.new(
        api_key: preferred_api_key,
        environment: nexi_environment,
        logger: SolidusNexi.configuration.logger.call
      )
    end

    def webhook_authenticator
      Nexi::Webhook::Authenticator.new([preferred_webhook_secret, preferred_previous_webhook_secret])
    end

    def nexi_environment
      (preferred_server == "production" && !preferred_test_mode) ? :live : :test
    end

    private

    def webhook_secret_format
      {
        preferred_webhook_secret: preferred_webhook_secret,
        preferred_previous_webhook_secret: preferred_previous_webhook_secret
      }.each do |attribute, secret|
        next if secret.blank? || WEBHOOK_SECRET.match?(secret)

        errors.add(attribute, "must contain 8-64 alphanumeric characters")
      end
    end
  end
end
