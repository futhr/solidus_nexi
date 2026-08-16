# frozen_string_literal: true

require "json"
require "socket"
require "timeout"

require "solidus_nexi/nexi/errors"
require "solidus_nexi/nexi/money"
require "solidus_nexi/nexi/net_http_transport"
require "solidus_nexi/nexi/result"

module SolidusNexi
  module Nexi
    class Client
      BASE_URLS = {
        test: "https://test.api.dibspayment.eu",
        live: "https://api.dibspayment.eu"
      }.freeze
      PLATFORM_TAG = "Solidus-solidus_nexi/#{SolidusNexi::VERSION}"
      IDENTIFIER = /\A[0-9A-Za-z-]{1,128}\z/

      def initialize(api_key:, environment: :test, transport: NetHttpTransport.new, logger: nil)
        @api_key = api_key.to_s
        @environment = environment.to_sym
        @transport = transport
        @logger = logger
        validate_configuration!
      end

      def create_payment(payload:)
        request(:post, "/v1/payments", payload:, mutation: true, operation: :create_payment)
      end

      def retrieve_payment(payment_id:)
        request(:get, "/v1/payments/#{identifier!(payment_id, "payment_id")}", operation: :retrieve_payment)
      end

      def terminate(payment_id:)
        request(
          :put,
          "/v1/payments/#{identifier!(payment_id, "payment_id")}/terminate",
          mutation: true,
          operation: :terminate_payment
        )
      end

      def charge(payment_id:, amount_minor:, idempotency_key:)
        amount = Money.validate_minor!(amount_minor)
        request(
          :post,
          "/v1/payments/#{identifier!(payment_id, "payment_id")}/charges",
          payload: {amount:},
          idempotency_key:,
          mutation: true,
          operation: :charge
        )
      end

      def cancel(payment_id:, amount_minor:)
        amount = Money.validate_minor!(amount_minor)
        request(
          :post,
          "/v1/payments/#{identifier!(payment_id, "payment_id")}/cancels",
          payload: {amount:},
          mutation: true,
          operation: :cancel
        )
      end

      def refund(charge_id:, amount_minor:, idempotency_key:)
        amount = Money.validate_minor!(amount_minor)
        request(
          :post,
          "/v1/charges/#{identifier!(charge_id, "charge_id")}/refunds",
          payload: {amount:},
          idempotency_key:,
          mutation: true,
          operation: :refund
        )
      end

      def retrieve_charge(charge_id:)
        request(:get, "/v1/charges/#{identifier!(charge_id, "charge_id")}", operation: :retrieve_charge)
      end

      def retrieve_refund(refund_id:)
        request(:get, "/v1/refunds/#{identifier!(refund_id, "refund_id")}", operation: :retrieve_refund)
      end

      def inspect
        "#<#{self.class.name} environment=#{@environment.inspect}>"
      end

      private

      def request(method, path, operation:, payload: nil, idempotency_key: nil, mutation: false)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = @transport.call(
          method:,
          url: "#{BASE_URLS.fetch(@environment)}#{path}",
          headers: headers(idempotency_key),
          body: payload && JSON.generate(payload)
        )
        provider_request_id = provider_request_id(response.headers)
        parsed_body = parse_body(response.body, response.status, provider_request_id)
        raise_for_status!(response.status, parsed_body, response.headers, provider_request_id, mutation:)
        log(operation:, result: "success", provider_request_id:, started_at:)
        Result.new(body: parsed_body, http_status: response.status, provider_request_id:)
      rescue Timeout::Error => error
        log(operation:, result: error.class.name, started_at:)
        raise timeout_error(mutation, error)
      rescue SocketError, IOError, SystemCallError => error
        log(operation:, result: error.class.name, started_at:)
        raise transport_error(mutation, error)
      rescue Error => error
        log(operation:, result: error.class.name, provider_request_id: error.provider_request_id, started_at:)
        raise
      end

      def headers(idempotency_key)
        {
          "Accept" => "application/json",
          "Authorization" => @api_key,
          "CommercePlatformTag" => PLATFORM_TAG,
          "Content-Type" => "application/json"
        }.tap do |values|
          values["Idempotency-Key"] = validate_idempotency_key!(idempotency_key) if idempotency_key
        end
      end

      def parse_body(body, status, request_id)
        return {} if body.empty? && status == 204
        raise MalformedResponseError.new("Nexi returned an empty JSON response", provider_request_id: request_id, http_status: status) if body.empty?

        parsed = JSON.parse(body)
        unless parsed.is_a?(Hash)
          raise MalformedResponseError.new("Nexi response must be a JSON object", provider_request_id: request_id, http_status: status)
        end

        parsed
      rescue JSON::ParserError
        raise MalformedResponseError.new("Nexi response was not valid JSON", provider_request_id: request_id, http_status: status)
      end

      def raise_for_status!(status, body, response_headers, request_id, mutation:)
        return if status.between?(200, 299)

        klass = case status
        when 400, 422 then ValidationError
        when 401, 403 then AuthenticationError
        when 404 then NotFoundError
        when 409 then ConflictError
        when 429 then RateLimitError
        when 500..599 then mutation ? TimeoutUnknownOutcome : ProviderUnavailableError
        else Error
        end

        raise klass.new(
          error_message(body, status),
          provider_request_id: request_id,
          provider_code: body["code"],
          http_status: status,
          retry_after: first_header(response_headers, "retry-after")
        )
      end

      def error_message(body, status)
        value = body["message"] || body["errors"] || "HTTP #{status}"
        "Nexi request rejected: #{value.is_a?(String) ? value.slice(0, 500) : "validation failed"}"
      end

      def provider_request_id(headers)
        %w[x-request-id request-id trace-id correlation-id].filter_map { |name| first_header(headers, name) }.first
      end

      def first_header(headers, name)
        value = headers[name] || headers[name.downcase] || headers[name.capitalize]
        Array(value).first
      end

      def timeout_error(mutation, error)
        klass = mutation ? TimeoutUnknownOutcome : TransportError
        klass.new("Nexi request timed out", provider_code: error.class.name)
      end

      def transport_error(mutation, error)
        klass = mutation ? TimeoutUnknownOutcome : TransportError
        klass.new("Nexi connection failed", provider_code: error.class.name)
      end

      def identifier!(value, name)
        normalized = value.to_s
        raise ValidationError, "#{name} has an invalid format" unless IDENTIFIER.match?(normalized)

        normalized
      end

      def validate_idempotency_key!(value)
        key = value.to_s
        raise ValidationError, "idempotency key must be between 1 and 63 characters" unless key.length.between?(1, 63)

        key
      end

      def validate_configuration!
        raise ConfigurationError, "api_key is required" if @api_key.empty?
        raise ConfigurationError, "environment must be test or live" unless BASE_URLS.key?(@environment)
      end

      def log(operation:, result:, started_at:, provider_request_id: nil)
        return unless @logger

        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        @logger.info(
          provider: "nexi",
          operation: operation.to_s,
          result:,
          provider_request_id:,
          duration_ms:
        )
      end
    end
  end
end
