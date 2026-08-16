# frozen_string_literal: true

module SolidusNexi
  module Nexi
    class Error < StandardError
      attr_reader :provider_request_id, :provider_code, :http_status, :retry_after

      def initialize(message = nil, provider_request_id: nil, provider_code: nil, http_status: nil, retry_after: nil)
        @provider_request_id = provider_request_id
        @provider_code = provider_code
        @http_status = http_status
        @retry_after = retry_after
        super(message)
      end
    end

    class ConfigurationError < Error; end
    class AuthenticationError < Error; end
    class ValidationError < Error; end
    class NotFoundError < Error; end
    class ConflictError < Error; end
    class RateLimitError < Error; end
    class ProviderUnavailableError < Error; end
    class TransportError < Error; end
    class TimeoutUnknownOutcome < Error; end
    class MalformedResponseError < Error; end
    class ReconciliationRequired < Error; end
    class OperationInProgress < Error; end
  end
end
