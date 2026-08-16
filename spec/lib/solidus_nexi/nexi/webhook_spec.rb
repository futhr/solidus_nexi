# frozen_string_literal: true

RSpec.describe "Nexi webhook contract" do
  let(:secret) { "WebhookSecret123456789" }

  it "authenticates the configured Authorization value" do
    authenticator = SolidusNexi::Nexi::Webhook::Authenticator.new([secret, "PreviousSecret987654321"])
    expect(authenticator.valid?(secret)).to be(true)
    expect(authenticator.valid?("PreviousSecret987654321")).to be(true)
    expect(authenticator.valid?("WebhookSecret123456780")).to be(false)
    expect(authenticator.valid?(nil)).to be(false)
  end

  it "parses the event identity without retaining a cardholder payload" do
    event = SolidusNexi::Nexi::Webhook::Parser.new.parse(fixture("nexi/webhooks/charge_created.json"))
    expect(event).to have_attributes(
      id: "5d866f534f0c45fe9e60941387377e9d",
      name: "payment.charge.created.v2",
      payment_id: "06afca06db214766b3a230c991e14a5d",
      charge_id: "050491ace345418d8ca70605a0c9df96",
      order_reference: "R123456789"
    )
  end

  it "accepts an unknown forward-compatible payment event" do
    event = SolidusNexi::Nexi::Webhook::Parser.new.parse(fixture("nexi/webhooks/unknown_future_event.json"))
    expect(event.name).to eq("payment.future.status.v3")
  end

  it "bounds the payload size" do
    payload = "{" + ("x" * SolidusNexi::Nexi::Webhook::Parser::MAX_BYTES) + "}"
    expect { SolidusNexi::Nexi::Webhook::Parser.new.parse(payload) }
      .to raise_error(SolidusNexi::Nexi::ValidationError, /too large/)
  end

  def fixture(path)
    File.read(Rails.root.join("..", "fixtures", path))
  end
end
