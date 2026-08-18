# frozen_string_literal: true

RSpec.describe SolidusNexi::CheckoutResponse do
  it "rejects an invalid payment identifier with provider correlation" do
    response = SolidusNexi::Nexi::Result.new(
      body: {"paymentId" => "invalid/payment"},
      http_status: 201,
      provider_request_id: "request-invalid"
    )

    expect { described_class.payment_id!(response) }
      .to raise_error(SolidusNexi::Nexi::MalformedResponseError) do |error|
        expect(error.provider_request_id).to eq("request-invalid")
      end
  end

  it "rejects a malformed hosted URL" do
    expect { described_class.hosted_url!("https://[") }
      .to raise_error(SolidusNexi::Nexi::MalformedResponseError, /invalid hosted checkout URL/)
  end
end
