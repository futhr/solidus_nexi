# frozen_string_literal: true

RSpec.describe SolidusNexi::Gateway, type: :model do
  let(:payment_method) { SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout") }
  let(:order) { create(:order, currency: "SEK") }
  let(:source) do
    SolidusNexi::PaymentSource.create!(
      payment_method:,
      currency: "SEK",
      provider_payment_id: "06afca06db214766b3a230c991e14a5d"
    )
  end
  let(:payment) { create(:payment, order:, payment_method:, source:, amount: 100) }
  let(:gateway) { described_class.new(test: true) }

  it "authorizes only after retrieving the matching reservation" do
    use_provider_fixture("nexi/payments/reserved.json")

    response = gateway.authorize(10_000, source, originator: payment)

    expect(response).to be_success
    expect(response).to be_test
    expect(response.authorization).to eq(source.provider_payment_id)
  end

  it "refuses a provider payment whose order reference does not match" do
    use_provider_fixture("nexi/payments/charged.json", order_reference: "another-order")

    response = gateway.purchase(10_000, source, originator: payment)

    expect(response).not_to be_success
    expect(response.message).to match(/not financially complete/)
  end

  it "purchases only after retrieving the matching full charge" do
    use_provider_fixture("nexi/payments/charged.json")

    response = gateway.purchase(10_000, source, originator: payment)

    expect(response).to be_success
    expect(response.authorization).to eq(source.provider_payment_id)
  end

  it "returns a gateway failure before checkout creation" do
    source.update!(provider_payment_id: nil)

    response = gateway.authorize(10_000, source, originator: payment)

    expect(response).not_to be_success
    expect(response.message).to match(/checkout has not been created/)
  end

  it "turns provider retrieval errors into an ActiveMerchant failure" do
    client = instance_double(SolidusNexi::Nexi::Client)
    allow(client).to receive(:retrieve_payment)
      .and_raise(SolidusNexi::Nexi::ProviderUnavailableError.new("unavailable", provider_code: "500"))
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }

    response = gateway.authorize(10_000, source, originator: payment)

    expect(response).not_to be_success
    expect(response.error_code).to eq("500")
    expect(response).to be_test
  end

  it "delegates capture, cancellation, and refund with durable logical identities" do
    refund = create(:refund, payment:, amount: 100)
    charge_result = SolidusNexi::Mutation::Result.new(authorization: "charge-1", provider_request_id: "request-1")
    cancel_result = SolidusNexi::Mutation::Result.new(authorization: "payment-1", provider_request_id: "request-2")
    refund_result = SolidusNexi::Mutation::Result.new(authorization: "refund-1", provider_request_id: "request-3")

    expect(SolidusNexi::Charge).to receive(:new).with(
      payment:,
      amount_minor: 10_000,
      logical_reference: "capture:#{payment.number}"
    ).and_return(instance_double(SolidusNexi::Charge, call: charge_result))
    expect(SolidusNexi::Cancel).to receive(:new).with(
      payment:,
      amount_minor: 10_000,
      logical_reference: "cancel:#{payment.number}"
    ).and_return(instance_double(SolidusNexi::Cancel, call: cancel_result))
    expect(SolidusNexi::Refund).to receive(:new).with(payment:, refund:, amount_minor: 10_000)
      .and_return(instance_double(SolidusNexi::Refund, call: refund_result))

    expect(gateway.capture(10_000, "ignored", originator: payment)).to be_success
    expect(gateway.void("ignored", originator: payment)).to be_success
    expect(gateway.credit(10_000, "ignored", originator: refund)).to be_success
  end

  it "raises a clear gateway error when a mutation fails" do
    allow(SolidusNexi::Charge).to receive(:new)
      .and_raise(SolidusNexi::Nexi::ValidationError, "partial capture is not supported")

    expect { gateway.capture(5_000, "ignored", originator: payment) }
      .to raise_error(Spree::Core::GatewayError, /partial capture/)
  end

  it "requires a Solidus payment or refund originator" do
    expect { gateway.capture(10_000, "ignored", {}) }
      .to raise_error(Spree::Core::GatewayError, /payment originator/)
    expect { gateway.credit(10_000, "ignored", {}) }
      .to raise_error(Spree::Core::GatewayError, /refund originator/)
  end

  private

  def use_provider_fixture(path, order_reference: order.number)
    body = JSON.parse(Rails.root.join("..", "fixtures", path).read)
    body.fetch("payment").fetch("orderDetails")["reference"] = order_reference
    result = SolidusNexi::Nexi::Result.new(body:, http_status: 200, provider_request_id: "retrieve-1")
    client = instance_double(SolidusNexi::Nexi::Client, retrieve_payment: result)
    SolidusNexi.configuration.client_factory = ->(_payment_method) { client }
  end
end
