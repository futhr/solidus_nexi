# frozen_string_literal: true

module SolidusNexi
  class Gateway
    def initialize(_options = {})
    end

    def authorize(amount_minor, source, options = {})
      payment = payment_from(options)
      verify_provider_state(payment, source, amount_minor, :reserved)
    end

    def purchase(amount_minor, source, options = {})
      payment = payment_from(options)
      verify_provider_state(payment, source, amount_minor, :charged)
    end

    def capture(amount_minor, _authorization, options = {})
      payment = payment_from(options)
      result = Charge.new(
        payment:,
        amount_minor:,
        logical_reference: "capture:#{payment.number}"
      ).call
      success("Nexi payment captured", result.authorization)
    rescue Nexi::Error => error
      raise Spree::Core::GatewayError, error.message
    end

    def void(_authorization, options = {})
      payment = payment_from(options)
      amount_minor = Nexi::Money.to_minor(payment.amount, payment.currency)
      result = Cancel.new(
        payment:,
        amount_minor:,
        logical_reference: "cancel:#{payment.number}"
      ).call
      success("Nexi authorization cancelled", result.authorization)
    rescue Nexi::Error => error
      raise Spree::Core::GatewayError, error.message
    end

    def credit(amount_minor, _authorization, options = {})
      refund = options[:originator]
      payment = refund&.payment
      raise Nexi::ValidationError, "refund originator is required" unless payment

      result = Refund.new(payment:, refund:, amount_minor:).call
      success("Nexi refund accepted", result.authorization)
    rescue Nexi::Error => error
      raise Spree::Core::GatewayError, error.message
    end

    private

    def verify_provider_state(payment, source, amount_minor, required_amount)
      unless source.is_a?(PaymentSource) && source.provider_payment_id.present?
        return failure(Nexi::ValidationError.new("Nexi checkout has not been created"))
      end

      response = client_for(payment).retrieve_payment(payment_id: source.provider_payment_id)
      snapshot = Nexi::PaymentSnapshot.new(response.body, expected_payment_id: source.provider_payment_id)
      amounts = snapshot.amounts
      provider_matches = snapshot.amount_minor == amount_minor &&
        snapshot.currency == payment.currency &&
        snapshot.order_reference == OrderSerializer.order_reference(payment.order.number)
      if payment.source == source && provider_matches && amounts.fetch(required_amount) >= amount_minor
        success("Nexi payment verified", source.provider_payment_id)
      else
        failure(Nexi::ReconciliationRequired.new("Nexi payment is not financially complete"))
      end
    rescue Nexi::Error => error
      failure(error)
    end

    def payment_from(options)
      options[:originator].tap do |payment|
        raise Nexi::ValidationError, "payment originator is required" unless payment.is_a?(Spree::Payment)
      end
    end

    def client_for(payment)
      SolidusNexi.configuration.client_factory.call(payment.payment_method)
    end

    def success(message, authorization)
      ActiveMerchant::Billing::Response.new(true, message, {}, authorization:, test: false)
    end

    def failure(error)
      ActiveMerchant::Billing::Response.new(
        false,
        error.message,
        {"message" => error.message, "provider_code" => error.provider_code},
        test: false,
        error_code: error.provider_code
      )
    end
  end
end
