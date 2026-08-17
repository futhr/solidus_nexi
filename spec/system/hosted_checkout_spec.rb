# frozen_string_literal: true

class SolidusNexiTestStorefrontController < ApplicationController
  prepend_view_path File.expand_path("../support/views", __dir__)

  def show
    @order = Spree::Order.find_by!(number: params[:order_number])
    @payment_method = SolidusNexi::PaymentMethod.find(params[:payment_method_id])
  end

  def provider
    render plain: "Nexi test checkout boundary"
  end
end

Rails.application.routes.append do
  get "/__solidus_nexi_test/checkout", to: "solidus_nexi_test_storefront#show"
  get "/hostedpaymentpage", to: "solidus_nexi_test_storefront#provider"
end
Rails.application.reload_routes!

RSpec.describe "Nexi hosted checkout", type: :system do
  let(:order) do
    create(:order_with_line_items, currency: "SEK", line_items_price: BigDecimal("100"), shipment_cost: 0)
  end
  let(:payment_method) do
    SolidusNexi::PaymentMethod.create!(
      name: "Nexi Checkout",
      active: true,
      preferred_api_key: "test-api-key",
      preferred_webhook_secret: "WebhookSecret123",
      preferred_terms_url: "https://shop.example/terms"
    )
  end

  before do
    driven_by :rack_test
    order.store.payment_methods << payment_method
    SolidusNexi.configuration.public_base_url = "https://shop.example"
    client = instance_double(SolidusNexi::Nexi::Client)
    allow(client).to receive(:create_payment).and_return(
      SolidusNexi::Nexi::Result.new(
        body: {
          "paymentId" => "provider-payment-1",
          "hostedPaymentPageUrl" => "https://test.checkout.dibspayment.eu/hostedpaymentpage/?payment=1"
        },
        http_status: 201,
        provider_request_id: "request-system"
      )
    )
    SolidusNexi.configuration.client_factory = ->(_method) { client }
  end

  it "renders the Solidus payment partial and submits a complete checkout handoff" do
    visit "/__solidus_nexi_test/checkout?order_number=#{order.number}&payment_method_id=#{payment_method.id}"

    expect(page).to have_text(I18n.t("solidus_nexi.hosted_checkout_explanation"))
    expect(page).to have_field("order_number", type: :hidden, with: order.number)
    expect(page).to have_field("guest_token", type: :hidden, with: order.guest_token)
    click_button I18n.t("solidus_nexi.continue_to_nexi")

    payment = order.payments.reload.find_by!(payment_method:)
    expect(payment.source).to have_attributes(
      provider_payment_id: "provider-payment-1",
      provider_status: "created"
    )
    expect(SolidusNexi::Operation.find_by!(payment:, kind: "create")).to have_attributes(
      status: "succeeded",
      provider_request_id: "request-system"
    )
    expect(page.current_url).to start_with("https://test.checkout.dibspayment.eu/")
  end
end
