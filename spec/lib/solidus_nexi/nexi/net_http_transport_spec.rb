# frozen_string_literal: true

RSpec.describe SolidusNexi::Nexi::NetHttpTransport do
  let(:response_class) do
    Class.new(Struct.new(:code, :headers, :chunks)) do
      delegate :[], to: :headers

      def read_body
        chunks.each { |chunk| yield chunk }
      end

      def to_hash
        headers.transform_values { |value| Array(value) }
      end
    end
  end

  let(:connection_class) do
    Class.new(Struct.new(:response)) do
      def request(_request)
        yield response
        response
      end
    end
  end

  subject(:transport) { described_class.new }

  it "streams a bounded response into the client response object" do
    response = response_class.new("200", {"content-type" => "application/json"}, ['{"ok":', "true}"])
    allow(transport).to receive(:connection).and_return(connection_class.new(response))

    result = transport.call(method: :get, url: "https://test.api.dibspayment.eu/v1/payments/p-1", headers: {})

    expect(result).to have_attributes(status: 200, body: '{"ok":true}')
    expect(result.headers).to eq("content-type" => ["application/json"])
  end

  it "uses verified TLS, bounded timeouts, and no implicit retries" do
    http = instance_double(Net::HTTP)
    expect(Net::HTTP).to receive(:new).with("test.api.dibspayment.eu", 443).and_return(http)
    expect(http).to receive(:max_retries=).with(0)
    expect(http).to receive(:use_ssl=).with(true)
    expect(http).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
    expect(http).to receive(:open_timeout=).with(5)
    expect(http).to receive(:read_timeout=).with(15)
    expect(http).to receive(:write_timeout=).with(15)
    response = response_class.new("204", {}, [])
    expect(http).to receive(:request).and_yield(response).and_return(response)

    expect(transport.call(method: :post, url: "https://test.api.dibspayment.eu/v1/payments", headers: {}).status)
      .to eq(204)
  end

  it "rejects an oversized declared response before reading it" do
    response = response_class.new(
      "200",
      {"content-length" => (described_class::MAX_RESPONSE_BYTES + 1).to_s},
      []
    )
    allow(transport).to receive(:connection).and_return(connection_class.new(response))

    expect do
      transport.call(method: :get, url: "https://test.api.dibspayment.eu/v1/payments/p-1", headers: {})
    end.to raise_error(SolidusNexi::Nexi::MalformedResponseError, /exceeded/)
  end

  it "rejects a chunked response as soon as it exceeds the byte limit" do
    response = response_class.new(
      "200",
      {},
      ["x" * described_class::MAX_RESPONSE_BYTES, "y"]
    )
    allow(transport).to receive(:connection).and_return(connection_class.new(response))

    expect do
      transport.call(method: :get, url: "https://test.api.dibspayment.eu/v1/payments/p-1", headers: {})
    end.to raise_error(SolidusNexi::Nexi::MalformedResponseError, /exceeded/)
  end

  it "refuses cleartext endpoints before opening a connection" do
    expect do
      described_class.new.call(method: :get, url: "http://test.api.dibspayment.eu/v1/payments/1", headers: {})
    end.to raise_error(SolidusNexi::Nexi::ConfigurationError, /HTTPS/)
  end

  it "rejects unsupported HTTP methods before dispatch" do
    transport = described_class.new
    expect(transport).not_to receive(:connection)

    expect do
      transport.call(method: :delete, url: "https://test.api.dibspayment.eu/v1/payments/1", headers: {})
    end.to raise_error(ArgumentError, /unsupported HTTP method/)
  end
end
