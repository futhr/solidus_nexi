# frozen_string_literal: true

RSpec.describe "SolidusNexi webhooks", type: :request do
  let(:secret) { "WebhookSecret123456789" }
  let(:payment_method) do
    SolidusNexi::PaymentMethod.create!(
      name: "Nexi Checkout",
      active: true,
      preferred_webhook_secret: secret,
      preferred_api_key: "test-api-key"
    )
  end
  let(:payload) { fixture("nexi/webhooks/reservation_created.json") }

  it "rejects an invalid Authorization value before persistence" do
    post webhook_path, params: payload, headers: webhook_headers("wrong-secret")

    expect(response).to have_http_status(:unauthorized)
    expect(SolidusNexi::WebhookReceipt.count).to eq(0)
  end

  it "returns exactly 200 and records an authenticated event once" do
    2.times { post webhook_path, params: payload, headers: webhook_headers(secret) }

    expect(response.status).to eq(200)
    expect(response.body).to be_empty
    expect(SolidusNexi::WebhookReceipt.count).to eq(1)
    expect(enqueued_jobs.count { |job| job[:job] == SolidusNexi::ProcessWebhookJob }).to eq(1)
  end

  it "continues authenticating callbacks for payments after the method is deactivated" do
    payment_method.update!(active: false)

    post webhook_path, params: payload, headers: webhook_headers(secret)

    expect(response.status).to eq(200)
    expect(SolidusNexi::WebhookReceipt.count).to eq(1)
  end

  private

  def webhook_path
    SolidusNexi::Engine.routes.url_helpers.webhook_path(payment_method)
  end

  def webhook_headers(authorization)
    {"CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => authorization}
  end

  def fixture(path)
    File.read(Rails.root.join("..", "fixtures", path))
  end
end
