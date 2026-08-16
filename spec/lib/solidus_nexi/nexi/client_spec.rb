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

  def fixture(path)
    File.read(Rails.root.join("..", "fixtures", path))
  end
end
