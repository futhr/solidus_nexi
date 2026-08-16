# frozen_string_literal: true

require "digest"
require "openssl"

module SolidusNexi
  module Nexi
    module Webhook
      class Authenticator
        def initialize(secrets)
          @digests = Array(secrets).filter_map do |secret|
            value = secret.to_s
            digest(value) unless value.empty?
          end
          raise ConfigurationError, "webhook secret is required" if @digests.empty?
        end

        def valid?(authorization)
          candidate = authorization.to_s
          return false if candidate.empty?

          candidate_digest = digest(candidate)
          @digests.reduce(false) do |matched, expected|
            OpenSSL.fixed_length_secure_compare(expected, candidate_digest) | matched
          end
        end

        private

        def digest(value)
          Digest::SHA256.digest(value)
        end
      end
    end
  end
end
