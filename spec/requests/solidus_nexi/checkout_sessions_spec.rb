# frozen_string_literal: true

RSpec.describe "SolidusNexi checkout sessions", type: :request do
  let(:order) { create(:order, currency: "SEK") }
  let(:payment_method) do
    SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout", active: true)
  end
  let(:service) { instance_double(SolidusNexi::CreateCheckout) }
  let(:result) do
    SolidusNexi::CreateCheckout::Result.new(
      payment: Struct.new(:number).new("P123"),
      source: nil,
      provider_payment_id: "provider-payment-1",
      hosted_payment_page_url: "https://test.checkout.dibspayment.eu/pay/provider-payment-1",
      reused: false
    )
  end

  before do
    order.store.payment_methods << payment_method
    SolidusNexi.configuration.public_base_url = "https://shop.example"
  end

  it "requires the order guest token before creating a provider checkout" do
    expect(SolidusNexi::CreateCheckout).not_to receive(:new)

    post checkout_path, params: checkout_params.merge(guest_token: "wrong"), as: :json

    expect(response).to have_http_status(:not_found)
  end

  it "builds public mounted URLs and returns the hosted checkout" do
    expect(SolidusNexi::CreateCheckout).to receive(:new) do |arguments|
      expect(arguments).to include(order:, payment_method:)
      expect(arguments[:webhook_url]).to eq("https://shop.example/solidus_nexi/webhooks/#{payment_method.id}")
      expect(arguments[:return_url_for].call(Struct.new(:return_token).new("return-token")))
        .to eq("https://shop.example/solidus_nexi/returns/return-token")
      service
    end
    allow(service).to receive(:call).and_return(result)

    post checkout_path, params: checkout_params, as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to eq(
      "payment_id" => "P123",
      "provider_payment_id" => "provider-payment-1",
      "checkout_url" => "https://test.checkout.dibspayment.eu/pay/provider-payment-1",
      "reused" => false
    )
  end

  it "rejects a public base URL that is not an HTTPS origin" do
    SolidusNexi.configuration.public_base_url = "https://shop.example/store?tenant=one"
    expect(SolidusNexi::CreateCheckout).not_to receive(:new)

    post checkout_path, params: checkout_params, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.fetch("error")).to match(/HTTPS origin/)
  end

  private

  def checkout_path
    SolidusNexi::Engine.routes.url_helpers.checkout_sessions_path
  end

  def checkout_params
    {
      order_number: order.number,
      guest_token: order.guest_token,
      payment_method_id: payment_method.id
    }
  end
end
