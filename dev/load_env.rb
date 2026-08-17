# frozen_string_literal: true

require_relative "../lib/solidus_nexi/public_url"

module SolidusNexi
  module DevelopmentEnvironment
    ENV_FILE = File.expand_path("../.env", __dir__)
    LOCAL_ENVIRONMENTS = %w[development test].freeze

    def self.load(path: ENV_FILE, environment: ENV)
      return false unless local?(environment)
      return false unless File.file?(path)

      require "dotenv"
      Dotenv.load(path)
      true
    end

    def self.validate!(environment: ENV)
      errors = []
      validate_master_key(environment, errors)
      validate_present(environment, errors, "NEXI_CHECKOUT_API_KEY")
      validate_webhook_secret(environment, errors, "NEXI_CHECKOUT_WEBHOOK_SECRET", required: true)
      validate_webhook_secret(environment, errors, "NEXI_CHECKOUT_PREVIOUS_WEBHOOK_SECRET", required: false)
      validate_inclusion(environment, errors, "NEXI_CHECKOUT_ENVIRONMENT", %w[test live])
      validate_country(environment, errors)
      validate_https_url(environment, errors, "NEXI_CHECKOUT_TERMS_URL", required: true)
      validate_https_url(environment, errors, "NEXI_CHECKOUT_MERCHANT_TERMS_URL", required: false)
      validate_public_origin(environment, errors)
      raise ArgumentError, errors.join("\n") if errors.any?

      true
    end

    def self.local?(environment)
      names = environment.values_at("RAILS_ENV", "RACK_ENV").compact
      names.empty? || names.all? { |name| LOCAL_ENVIRONMENTS.include?(name) }
    end

    def self.validate_master_key(environment, errors)
      value = environment["SOLIDUS_PREFERENCES_MASTER_KEY"].to_s
      errors << "SOLIDUS_PREFERENCES_MASTER_KEY must be exactly 32 bytes" unless value.bytesize == 32
    end

    def self.validate_present(environment, errors, name)
      value = environment[name].to_s
      errors << "#{name} is required" if value.empty? || value.start_with?("replace-with-")
    end

    def self.validate_webhook_secret(environment, errors, name, required:)
      value = environment[name].to_s
      return if value.empty? && !required

      errors << "#{name} must contain 8-64 alphanumeric characters" unless /\A[0-9A-Za-z]{8,64}\z/.match?(value)
    end

    def self.validate_inclusion(environment, errors, name, allowed)
      errors << "#{name} must be one of: #{allowed.join(", ")}" unless allowed.include?(environment[name])
    end

    def self.validate_country(environment, errors)
      errors << "NEXI_CHECKOUT_COUNTRY must be a three-letter uppercase country code" unless
        /\A[A-Z]{3}\z/.match?(environment["NEXI_CHECKOUT_COUNTRY"].to_s)
    end

    def self.validate_https_url(environment, errors, name, required:)
      value = environment[name].to_s
      return if value.empty? && !required

      valid = PublicUrl.valid_https?(value, maximum_length: 256)
      errors << "#{name} must be a public HTTPS URL of at most 256 characters" unless valid
    end

    def self.validate_public_origin(environment, errors)
      value = environment["NEXI_CHECKOUT_PUBLIC_BASE_URL"].to_s
      valid = PublicUrl.valid_https?(value, origin: true, maximum_length: 256)
      errors << "NEXI_CHECKOUT_PUBLIC_BASE_URL must be a public HTTPS origin without a path" unless valid
    end

    private_class_method :local?, :validate_master_key, :validate_present, :validate_webhook_secret,
      :validate_inclusion, :validate_country, :validate_https_url, :validate_public_origin
  end
end

SolidusNexi::DevelopmentEnvironment.load
