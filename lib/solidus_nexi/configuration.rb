# frozen_string_literal: true

module SolidusNexi
  class Configuration
    attr_accessor :client_factory, :clock, :idempotency_key_generator, :logger,
      :return_path_resolver, :cancel_path_resolver, :public_base_url

    def initialize
      @client_factory = ->(payment_method) { payment_method.build_client }
      @clock = -> { Time.current }
      @idempotency_key_generator = ->(kind) { "sd-#{kind}-#{SecureRandom.hex(20)}" }
      @logger = -> { Rails.logger }
      @return_path_resolver = ->(_source) { "/checkout/confirm" }
      @cancel_path_resolver = ->(_source) { "/checkout/payment" }
      @public_base_url = ENV["NEXI_CHECKOUT_PUBLIC_BASE_URL"]
    end
  end
end
