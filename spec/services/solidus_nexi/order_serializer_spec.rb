# frozen_string_literal: true

RSpec.describe SolidusNexi::OrderSerializer, type: :model do
  it "sanitizes and bounds Nexi-facing references" do
    expect(described_class.order_reference(" <R&123> ")).to eq("-R-123-")
    expect(described_class.order_reference("")).to eq("solidus-order")
    expect(described_class.order_reference("r" * 200).length).to eq(128)
  end

  it "serializes actual Solidus line items and balances discounts exactly" do
    order = create(
      :order_with_line_items,
      currency: "SEK",
      line_items_price: BigDecimal("100"),
      shipment_cost: 0
    )

    payload = described_class.new(order).call(amount_minor: 9_000)

    expect(payload[:items].sum { |item| item[:grossTotalAmount] }).to eq(9_000)
    expect(payload[:items].last).to include(
      reference: "solidus-payment-balance",
      name: "Solidus credits and discounts",
      grossTotalAmount: -1_000
    )
  end

  it "adds a positive balance item when Solidus's payable amount exceeds components" do
    order = create(
      :order_with_line_items,
      currency: "SEK",
      line_items_price: BigDecimal("100"),
      shipment_cost: 0
    )

    payload = described_class.new(order).call(amount_minor: 11_000)

    expect(payload[:items].last).to include(
      name: "Solidus order adjustment",
      grossTotalAmount: 1_000
    )
  end

  it "rejects unsupported currencies and non-positive payment totals" do
    unsupported = create(:order, currency: "AUD")
    expect { described_class.new(unsupported) }
      .to raise_error(SolidusNexi::Nexi::ValidationError, /currency/)

    order = create(:order, currency: "SEK")
    expect { described_class.new(order).call(amount_minor: 0) }
      .to raise_error(SolidusNexi::Nexi::ValidationError, /positive/)
  end
end
