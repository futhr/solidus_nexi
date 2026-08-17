# frozen_string_literal: true

RSpec.describe "Nexi payment visibility in Solidus admin", type: :feature do
  stub_authorization!

  it "shows provider identity, financial status, and reconciliation warning" do
    order = create(:completed_order_with_totals, currency: "SEK", line_items_price: 100)
    payment_method = SolidusNexi::PaymentMethod.create!(name: "Nexi Checkout", active: true)
    source = SolidusNexi::PaymentSource.create!(
      payment_method:,
      currency: "SEK",
      provider_payment_id: "provider-payment-1",
      provider_charge_id: "provider-charge-1",
      provider_status: "local_state_conflict",
      reconciliation_required: true,
      last_reconciled_at: Time.zone.parse("2026-08-17 10:30:00")
    )
    payment = create(:payment, order:, payment_method:, source:, amount: 100, state: "completed")

    visit spree.admin_order_payment_path(order, payment)

    expect(page).to have_text("provider-payment-1")
    expect(page).to have_text("provider-charge-1")
    expect(page).to have_text("local_state_conflict")
    expect(page).to have_text(I18n.t("solidus_nexi.reconciliation_required"))
  end
end
