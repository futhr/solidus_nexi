# frozen_string_literal: true

require "securerandom"

require "solidus_nexi/version"
require "solidus_nexi/configuration"
require "solidus_nexi/public_url"
require "solidus_nexi/nexi/canonical_json"
require "solidus_nexi/nexi/client"
require "solidus_nexi/nexi/payment_snapshot"
require "solidus_nexi/nexi/retry_after"
require "solidus_nexi/nexi/state_mapper"
require "solidus_nexi/nexi/webhook/authenticator"
require "solidus_nexi/nexi/webhook/parser"
require "solidus_nexi/engine"

module SolidusNexi
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
