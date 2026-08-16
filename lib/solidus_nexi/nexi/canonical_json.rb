# frozen_string_literal: true

require "json"

module SolidusNexi
  module Nexi
    module CanonicalJson
      module_function

      def generate(value)
        JSON.generate(normalize(value))
      end

      def normalize(value)
        case value
        when Hash
          value.to_h { |key, nested| [key.to_s, normalize(nested)] }.sort.to_h
        when Array
          value.map { |nested| normalize(nested) }
        else
          value
        end
      end
    end
  end
end
