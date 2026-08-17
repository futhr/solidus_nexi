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

  it "serializes included and additional line-item tax with Nexi's VAT formula" do
    order = create(
      :order_with_line_items,
      currency: "SEK",
      line_items_price: BigDecimal("100"),
      shipment_cost: 0
    )
    line_item = order.line_items.first
    allow(line_item).to receive_messages(
      total_excluding_vat: BigDecimal("80"),
      included_tax_total: BigDecimal("20"),
      additional_tax_total: 0
    )

    included = described_class.new(order).call(amount_minor: 10_000).fetch(:items).first
    expect(included).to include(
      unitPrice: 8_000,
      taxRate: 2_500,
      taxAmount: 2_000,
      grossTotalAmount: 10_000,
      netTotalAmount: 8_000
    )

    allow(line_item).to receive_messages(
      total_excluding_vat: BigDecimal("100"),
      included_tax_total: 0,
      additional_tax_total: BigDecimal("25")
    )
    additional = described_class.new(order).call(amount_minor: 12_500).fetch(:items).first
    expect(additional).to include(unitPrice: 10_000, taxRate: 2_500, taxAmount: 2_500)
  end

  it "serializes taxed shipping without duplicating line or order tax" do
    order = create(
      :order_with_line_items,
      currency: "SEK",
      line_items_price: BigDecimal("100"),
      shipment_cost: 20
    )
    shipment = order.shipments.first
    allow(shipment).to receive_messages(
      total_excluding_vat: BigDecimal("16"),
      included_tax_total: BigDecimal("4"),
      additional_tax_total: 0
    )

    shipping = described_class.new(order).call(amount_minor: 12_000).fetch(:items)
      .find { |item| item.fetch(:reference).start_with?("shipping-") }

    expect(shipping).to include(
      unitPrice: 1_600,
      taxRate: 2_500,
      taxAmount: 400,
      grossTotalAmount: 2_000
    )
  end

  it "rejects tax-only order adjustments and impossible item tax allocations" do
    order = create(
      :order_with_line_items,
      currency: "SEK",
      line_items_price: BigDecimal("100"),
      shipment_cost: 0
    )
    create(:adjustment, order:, adjustable: order, amount: 25, included: false)

    expect { described_class.new(order).call(amount_minor: 12_500) }
      .to raise_error(SolidusNexi::Nexi::ValidationError, /order-level tax adjustments/)

    order.adjustments.destroy_all
    line_item = order.line_items.first
    allow(line_item).to receive_messages(
      total_excluding_vat: 0,
      included_tax_total: BigDecimal("1"),
      additional_tax_total: 0
    )
    expect { described_class.new(order).call(amount_minor: 100) }
      .to raise_error(SolidusNexi::Nexi::ValidationError, /invalid tax allocation/)
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
