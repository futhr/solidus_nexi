# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

module SolidusNexi
  module Nexi
    class NetHttpTransport
      Response = Data.define(:status, :body, :headers)

      DEFAULT_OPEN_TIMEOUT = 5
      DEFAULT_READ_TIMEOUT = 15
      DEFAULT_WRITE_TIMEOUT = 15
      MAX_RESPONSE_BYTES = 1_048_576

      def initialize(open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
        write_timeout: DEFAULT_WRITE_TIMEOUT)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @write_timeout = write_timeout
      end

      def call(method:, url:, headers:, body: nil)
        uri = URI.parse(url)
        raise ConfigurationError, "Nexi endpoint must use HTTPS" unless uri.is_a?(URI::HTTPS)

        request = request_class(method).new(uri.request_uri, headers)
        request.body = body if body

        response = connection(uri).request(request)
        response_body = response.body.to_s
        if response_body.bytesize > MAX_RESPONSE_BYTES
          raise MalformedResponseError, "Nexi response exceeded #{MAX_RESPONSE_BYTES} bytes"
        end

        Response.new(status: response.code.to_i, body: response_body, headers: response.to_hash)
      end

      private

      def connection(uri)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.open_timeout = @open_timeout
          http.read_timeout = @read_timeout
          http.write_timeout = @write_timeout if http.respond_to?(:write_timeout=)
        end
      end

      def request_class(method)
        case method.to_s.downcase
        when "get" then Net::HTTP::Get
        when "post" then Net::HTTP::Post
        when "put" then Net::HTTP::Put
        else
          raise ArgumentError, "unsupported HTTP method: #{method}"
        end
      end
    end
  end
end
