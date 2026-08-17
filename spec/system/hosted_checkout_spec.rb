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
  let(:provider_payment_id) { "06afca06db214766b3a230c991e14a5d" }
  let(:order) do
    create(:order_with_line_items, currency: "SEK", line_items_price: BigDecimal("100"), shipment_cost: 0)
  end
  let(:payment_method) do
    SolidusNexi::PaymentMethod.create!(
      name: "Nexi Checkout",
      active: true,
      preferred_api_key: "test-api-key",
      preferred_webhook_secret: "WebhookSecret123",
      preferred_terms_url: "https://checkout.merchant.se/terms"
    )
  end
  let(:client) { instance_double(SolidusNexi::Nexi::Client) }

  before do
    driven_by :rack_test
    order.store.payment_methods << payment_method
    SolidusNexi.configuration.public_base_url = "https://checkout.merchant.se"
    allow(client).to receive(:create_payment).and_return(
      SolidusNexi::Nexi::Result.new(
        body: {
          "paymentId" => provider_payment_id,
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
      provider_payment_id:,
      provider_status: "created"
    )
    expect(SolidusNexi::Operation.find_by!(payment:, kind: "create")).to have_attributes(
      status: "succeeded",
      provider_request_id: "request-system"
    )
    expect(page.current_url).to start_with("https://test.checkout.dibspayment.eu/")
  end

  it "moves an authenticated reservation webhook through the shipped storefront into Solidus" do
    allow(client).to receive(:retrieve_payment).with(payment_id: provider_payment_id).and_return(
      SolidusNexi::Nexi::Result.new(body: reserved_payment, http_status: 200, provider_request_id: "retrieve-system")
    )
    visit "/__solidus_nexi_test/checkout?order_number=#{order.number}&payment_method_id=#{payment_method.id}"
    click_button I18n.t("solidus_nexi.continue_to_nexi")

    2.times do
      perform_enqueued_jobs do
        page.driver.post(
          SolidusNexi::Engine.routes.url_helpers.webhook_path(payment_method),
          reservation_webhook.to_json,
          {"CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "WebhookSecret123"}
        )
      end
      expect(page.driver.response.status).to eq(200)
    end

    payment = order.payments.reload.find_by!(payment_method:)
    expect(payment).to be_pending
    expect(payment.source.reload).to have_attributes(
      provider_status: "reserved",
      reserved_amount_minor: 10_000,
      reconciliation_required: false
    )
    expect(SolidusNexi::WebhookReceipt.all).to contain_exactly(have_attributes(status: "processed"))
    expect(client).to have_received(:retrieve_payment).once
  end

  def reserved_payment
    {
      "payment" => {
        "paymentId" => provider_payment_id,
        "summary" => {
          "reservedAmount" => 10_000,
          "chargedAmount" => 0,
          "refundedAmount" => 0,
          "cancelledAmount" => 0
        },
        "orderDetails" => {"amount" => 10_000, "currency" => "SEK", "reference" => order.number},
        "checkout" => {"url" => "https://test.checkout.dibspayment.eu/hpp/example"},
        "charges" => [],
        "refunds" => []
      }
    }
  end

  def reservation_webhook
    {
      id: "311ff2158e8a4c30a8867ef71a3238b4",
      event: "payment.reservation.created.v2",
      timestamp: "2026-08-16T08:01:00Z",
      merchantId: 100_242_833,
      merchantNumber: 0,
      data: {paymentId: provider_payment_id, order: {reference: order.number}}
    }
  end
end
