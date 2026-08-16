# frozen_string_literal: true

RSpec.describe SolidusNexi::Nexi::PaymentSnapshot do
  it "extracts authoritative amounts and operation identifiers" do
    body = JSON.parse(fixture("nexi/payments/refunded.json"))
    snapshot = described_class.new(body, expected_payment_id: "06afca06db214766b3a230c991e14a5d")

    expect(snapshot.amounts).to eq(reserved: 10_000, charged: 10_000, refunded: 10_000, cancelled: 0)
    expect(snapshot.charge_id).to eq("050491ace345418d8ca70605a0c9df96")
    expect(snapshot.completed_refund_id).to eq("60e208b88b94403bb9ced1cca661db99")
  end

  it "rejects a response for a different payment" do
    body = JSON.parse(fixture("nexi/payments/charged.json"))

    expect { described_class.new(body, expected_payment_id: "different") }
      .to raise_error(SolidusNexi::Nexi::MalformedResponseError, /different payment/)
  end

  def fixture(path)
    File.read(Rails.root.join("..", "fixtures", path))
  end
end
