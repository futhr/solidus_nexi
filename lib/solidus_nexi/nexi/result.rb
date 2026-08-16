# frozen_string_literal: true

module SolidusNexi
  module Nexi
    Result = Data.define(:body, :http_status, :provider_request_id) do
      def fetch(key)
        body.fetch(key.to_s)
      end

      def [](key)
        body[key.to_s]
      end
    end
  end
end
