# frozen_string_literal: true

RSpec.describe SolidusNexi::Nexi::Client do
  let(:transport) { instance_double(SolidusNexi::Nexi::NetHttpTransport) }
  let(:client) { described_class.new(api_key: "test-secret", transport:) }

  it "uses the raw API key authorization contract and no idempotency key for create" do
    expect(transport).to receive(:call) do |request|
      expect(request[:url]).to eq("https://test.api.dibspayment.eu/v1/payments")
      expect(request[:headers]).to include("Authorization" => "test-secret")
      expect(request[:headers]).not_to have_key("Idempotency-Key")
      SolidusNexi::Nexi::NetHttpTransport::Response.new(
        status: 201,
        body: fixture("nexi/payments/created.json"),
        headers: {"x-request-id" => ["request-1"]}
      )
    end

    result = client.create_payment(payload: {order: {amount: 100}})
    expect(result["paymentId"]).to eq("06afca06db214766b3a230c991e14a5d")
    expect(result.provider_request_id).to eq("request-1")
  end

  it "sends a caller-supplied key when charging" do
    expect(transport).to receive(:call) do |request|
      expect(request[:headers]["Idempotency-Key"]).to eq("stable-charge-key")
      expect(JSON.parse(request[:body])).to eq("amount" => 10_000)
      SolidusNexi::Nexi::NetHttpTransport::Response.new(
        status: 201,
        body: '{"chargeId":"050491ace345418d8ca70605a0c9df96"}',
        headers: {}
      )
    end

    client.charge(
      payment_id: "06afca06db214766b3a230c991e14a5d",
      amount_minor: 10_000,
      idempotency_key: "stable-charge-key"
    )
  end

  it "classifies a mutation timeout as an unknown outcome" do
    allow(transport).to receive(:call).and_raise(Net::ReadTimeout)

    expect do
      client.cancel(payment_id: "06afca06db214766b3a230c991e14a5d", amount_minor: 10_000)
    end.to raise_error(SolidusNexi::Nexi::TimeoutUnknownOutcome)
  end

  it "maps throttling and preserves safe retry metadata" do
    allow(transport).to receive(:call).and_return(
      SolidusNexi::Nexi::NetHttpTransport::Response.new(
        status: 429,
        body: fixture("nexi/errors/rate_limited.json"),
        headers: {"retry-after" => ["30"], "x-request-id" => ["request-2"]}
      )
    )

    expect { client.retrieve_payment(payment_id: "06afca06db214766b3a230c991e14a5d") }
      .to raise_error(SolidusNexi::Nexi::RateLimitError) { |error|
        expect(error.retry_after).to eq("30")
        expect(error.provider_request_id).to eq("request-2")
      }
  end

  it "treats a server error after a mutation as an unknown outcome" do
    allow(transport).to receive(:call).and_return(
      SolidusNexi::Nexi::NetHttpTransport::Response.new(
        status: 500,
        body: '{"message":"internal error","code":"50000"}',
        headers: {"x-request-id" => ["request-3"]}
      )
    )

    expect do
      client.charge(
        payment_id: "06afca06db214766b3a230c991e14a5d",
        amount_minor: 10_000,
        idempotency_key: "stable-charge-key"
      )
    end.to raise_error(SolidusNexi::Nexi::TimeoutUnknownOutcome) { |error|
      expect(error.provider_request_id).to eq("request-3")
    }
  end

  it "classifies a non-JSON server error without mistaking it for a malformed success" do
    allow(transport).to receive(:call).and_return(
      SolidusNexi::Nexi::NetHttpTransport::Response.new(
        status: 500,
        body: "<html>upstream unavailable</html>",
        headers: {"x-request-id" => ["request-4"]}
      )
    )

    expect do
      client.cancel(payment_id: "06afca06db214766b3a230c991e14a5d", amount_minor: 10_000)
    end.to raise_error(SolidusNexi::Nexi::TimeoutUnknownOutcome) { |error|
      expect(error).to have_attributes(http_status: 500, provider_request_id: "request-4")
    }
  end

  it "classifies an empty retrieval server error as provider unavailability" do
    allow(transport).to receive(:call).and_return(
      SolidusNexi::Nexi::NetHttpTransport::Response.new(status: 503, body: "", headers: {})
    )

    expect { client.retrieve_payment(payment_id: "06afca06db214766b3a230c991e14a5d") }
      .to raise_error(SolidusNexi::Nexi::ProviderUnavailableError, /HTTP 503/)
  end

  it "accepts the provider's documented 64-character idempotency keys" do
    allow(transport).to receive(:call).and_return(
      SolidusNexi::Nexi::NetHttpTransport::Response.new(
        status: 201,
        body: '{"chargeId":"050491ace345418d8ca70605a0c9df96"}',
        headers: {}
      )
    )

    expect do
      client.charge(
        payment_id: "06afca06db214766b3a230c991e14a5d",
        amount_minor: 10_000,
        idempotency_key: "k" * 64
      )
    end.not_to raise_error
  end

  it "uses the documented cancel and refund resources" do
    expect(transport).to receive(:call).with(hash_including(
      method: :post,
      url: "https://test.api.dibspayment.eu/v1/payments/payment-1/cancels",
      body: '{"amount":10000}'
    )).and_return(response(status: 204, body: ""))
    expect(transport).to receive(:call).with(hash_including(
      method: :post,
      url: "https://test.api.dibspayment.eu/v1/charges/charge-1/refunds",
      body: '{"amount":10000}'
    )).and_return(response(status: 201, body: '{"refundId":"refund-1"}'))

    expect(client.cancel(payment_id: "payment-1", amount_minor: 10_000).body).to eq({})
    expect(client.refund(charge_id: "charge-1", amount_minor: 10_000, idempotency_key: "refund-key")["refundId"])
      .to eq("refund-1")
  end

  it "rejects invalid configuration before making a network request" do
    expect { described_class.new(api_key: "", transport:) }
      .to raise_error(SolidusNexi::Nexi::ConfigurationError, /api_key/)
    expect { described_class.new(api_key: "secret", environment: :staging, transport:) }
      .to raise_error(SolidusNexi::Nexi::ConfigurationError, /environment/)
  end

  it "rejects malformed identifiers, amounts, and idempotency keys locally" do
    expect(transport).not_to receive(:call)

    expect { client.retrieve_payment(payment_id: "../secret") }
      .to raise_error(SolidusNexi::Nexi::ValidationError, /payment_id/)
    expect { client.charge(payment_id: "payment-1", amount_minor: 0, idempotency_key: "key") }
      .to raise_error(SolidusNexi::Nexi::ValidationError, /positive/)
    expect { client.charge(payment_id: "payment-1", amount_minor: 100, idempotency_key: "k" * 65) }
      .to raise_error(SolidusNexi::Nexi::ValidationError, /idempotency/)
  end

  it "rejects empty, non-object, and invalid JSON success responses" do
    ["", "[]", "not-json"].each do |body|
      allow(transport).to receive(:call).and_return(response(status: 200, body:))

      expect { client.retrieve_payment(payment_id: "payment-1") }
        .to raise_error(SolidusNexi::Nexi::MalformedResponseError)
    end
  end

  it "maps validation, authentication, missing, conflict, and generic HTTP failures" do
    {
      400 => SolidusNexi::Nexi::ValidationError,
      401 => SolidusNexi::Nexi::AuthenticationError,
      404 => SolidusNexi::Nexi::NotFoundError,
      409 => SolidusNexi::Nexi::ConflictError,
      418 => SolidusNexi::Nexi::Error
    }.each do |status, error_class|
      allow(transport).to receive(:call).and_return(response(
        status:,
        body: '{"message":"provider rejected request","code":"provider-code"}'
      ))

      expect { client.retrieve_payment(payment_id: "payment-1") }
        .to raise_error(error_class) { |error|
          expect(error).to have_attributes(http_status: status, provider_code: "provider-code")
        }
    end
  end

  it "distinguishes safe retrieval transport failures from uncertain mutations" do
    allow(transport).to receive(:call).and_raise(SocketError, "offline")

    expect { client.retrieve_payment(payment_id: "payment-1") }
      .to raise_error(SolidusNexi::Nexi::TransportError)
    expect { client.create_payment(payload: {order: {amount: 100}}) }
      .to raise_error(SolidusNexi::Nexi::TimeoutUnknownOutcome)
  end

  it "logs bounded operational metadata without exposing the API key" do
    logger = instance_double(Logger)
    logging_client = described_class.new(api_key: "do-not-log", transport:, logger:)
    allow(transport).to receive(:call).and_return(response(
      status: 200,
      body: fixture("nexi/payments/reserved.json"),
      headers: {"correlation-id" => ["request-logged"]}
    ))

    expect(logger).to receive(:info).with(hash_including(
      provider: "nexi",
      operation: "retrieve_payment",
      result: "success",
      provider_request_id: "request-logged",
      duration_ms: be_a(Integer)
    ))

    logging_client.retrieve_payment(payment_id: "payment-1")
    expect(logging_client.inspect).to eq("#<SolidusNexi::Nexi::Client environment=:test>")
  end

  it "logs provider failures and retains request correlation" do
    logger = instance_double(Logger)
    logging_client = described_class.new(api_key: "secret", transport:, logger:)
    allow(transport).to receive(:call).and_return(response(
      status: 404,
      body: '{"message":"missing"}',
      headers: {"trace-id" => ["trace-1"]}
    ))

    expect(logger).to receive(:info).with(hash_including(
      operation: "retrieve_payment",
      result: "SolidusNexi::Nexi::NotFoundError",
      provider_request_id: "trace-1"
    ))

    expect { logging_client.retrieve_payment(payment_id: "payment-1") }
      .to raise_error(SolidusNexi::Nexi::NotFoundError)
  end

  def fixture(path)
    Rails.root.join("..", "fixtures", path).read
  end

  def response(status:, body:, headers: {})
    SolidusNexi::Nexi::NetHttpTransport::Response.new(status:, body:, headers:)
  end
end
