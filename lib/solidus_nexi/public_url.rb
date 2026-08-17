# frozen_string_literal: true

require "ipaddr"
require "uri"

module SolidusNexi
  module PublicUrl
    RESERVED_HOSTS = %w[localhost example.com example.net example.org].freeze
    RESERVED_SUFFIXES = %w[.example .invalid .localhost .local .test].freeze
    NON_PUBLIC_NETWORKS = %w[
      0.0.0.0/8
      10.0.0.0/8
      100.64.0.0/10
      127.0.0.0/8
      169.254.0.0/16
      172.16.0.0/12
      192.0.0.0/24
      192.0.2.0/24
      192.168.0.0/16
      198.18.0.0/15
      198.51.100.0/24
      203.0.113.0/24
      224.0.0.0/4
      240.0.0.0/4
      ::/128
      ::1/128
      fc00::/7
      fe80::/10
      ff00::/8
      2001:db8::/32
    ].map { |network| IPAddr.new(network) }.freeze
    HOSTNAME = /\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i

    def self.valid_https?(value, origin: false, maximum_length: 2048)
      string = value.to_s
      return false if string.empty? || string.length > maximum_length

      uri = URI.parse(string)
      return false unless public_https_uri?(uri)
      return false if origin && !origin?(uri)

      true
    rescue URI::InvalidURIError
      false
    end

    def self.public_host?(value)
      host = value.to_s.downcase.delete_prefix("[").delete_suffix("]").delete_suffix(".")
      return false if RESERVED_HOSTS.include?(host)
      return false if RESERVED_SUFFIXES.any? { |suffix| host.end_with?(suffix) }
      return false if %w[example.com example.net example.org].any? { |name| host.end_with?(".#{name}") }

      address = IPAddr.new(host)
      NON_PUBLIC_NETWORKS.none? { |network| network.include?(address) }
    rescue IPAddr::InvalidAddressError
      HOSTNAME.match?(host)
    end

    def self.public_https_uri?(uri)
      uri.is_a?(URI::HTTPS) && uri.host && uri.userinfo.nil? && public_host?(uri.host)
    end

    def self.origin?(uri)
      ["", "/"].include?(uri.path) && uri.query.nil? && uri.fragment.nil?
    end

    private_class_method :public_https_uri?, :origin?
  end
end
