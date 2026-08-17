# frozen_string_literal: true

RSpec.describe "SolidusNexi checkout returns", type: :request do
  let(:payment_method) { SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout") }

  it "queues provider retrieval and redirects a known customer return locally" do
    source = SolidusNexi::PaymentSource.create!(
      payment_method:,
      currency: "SEK",
      provider_payment_id: "provider-payment-1"
    )

    get SolidusNexi::Engine.routes.url_helpers.return_path(source.return_token)

    expect(response).to redirect_to("/checkout/confirm")
    expect(response).to have_http_status(:see_other)
    expect(enqueued_jobs.pluck(:job)).to include(SolidusNexi::ReconcilePaymentJob)
  end

  it "does not queue retrieval for a cancellation without a provider payment" do
    source = SolidusNexi::PaymentSource.create!(payment_method:, currency: "SEK")

    get SolidusNexi::Engine.routes.url_helpers.cancel_path(source.return_token)

    expect(response).to redirect_to("/checkout/payment")
    expect(enqueued_jobs).to be_empty
  end

  it "does not disclose unknown return tokens" do
    get SolidusNexi::Engine.routes.url_helpers.return_path("unknown")

    expect(response).to have_http_status(:not_found)
  end
end
