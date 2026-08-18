# frozen_string_literal: true

RSpec.describe SolidusNexi::CheckoutContext, type: :model do
  let(:order) do
    create(:order_with_line_items, currency: "SEK", line_items_price: BigDecimal("100"), shipment_cost: 10)
  end

  it "changes for same-total SKU, name, tax allocation, and shipping changes" do
    original = fingerprint

    order.line_items.first.variant.update!(sku: "changed-sku")
    expect(fingerprint).not_to eq(original)

    original = fingerprint
    order.line_items.first.variant.product.update!(name: "Changed product name")
    expect(fingerprint).not_to eq(original)

    original = fingerprint
    line_item = order.line_items.first
    allow(line_item).to receive_messages(
      total_excluding_vat: line_item.total_excluding_vat - 1,
      included_tax_total: line_item.included_tax_total + 1
    )
    expect(fingerprint).not_to eq(original)

    original = fingerprint
    order.shipments.first.selected_shipping_rate.shipping_method.update!(name: "Changed shipping service")
    expect(fingerprint).not_to eq(original)
  end

  def fingerprint
    described_class.fingerprint(
      order:,
      amount: order.order_total_after_store_credit,
      currency: order.currency
    )
  end
end
