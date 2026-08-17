# frozen_string_literal: true

module SolidusNexi
  class OrderSerializer
    UNSUPPORTED_CHARACTERS = /[<>'"&\\]/

    def self.order_reference(value)
      sanitize(value, fallback: "solidus-order")
    end

    def self.sanitize(value, fallback:)
      cleaned = value.to_s.gsub(UNSUPPORTED_CHARACTERS, "-").strip
      cleaned = fallback if cleaned.empty?
      cleaned.slice(0, 128)
    end

    def initialize(order)
      @order = order
      @currency = Nexi::Money.validate_currency!(order.currency)
    end

    def call(amount_minor:)
      expected_amount = Nexi::Money.validate_minor!(amount_minor)
      items = line_items + shipment_items + order_adjustment_items
      append_balance_item!(items, expected_amount - items.sum { |item| item.fetch(:grossTotalAmount) })

      unless items.sum { |item| item.fetch(:grossTotalAmount) } == expected_amount
        raise Nexi::ValidationError, "serialized order items do not equal the payment amount"
      end

      {
        items:,
        amount: expected_amount,
        currency: @currency,
        reference: self.class.order_reference(@order.number)
      }
    end

    private

    def line_items
      @order.line_items.map do |line_item|
        item(
          reference: [line_item.sku.presence || "variant-#{line_item.variant_id}", line_item.id].join("-"),
          name: line_item.name.presence || "Item #{line_item.id}",
          net: minor(line_item.total_excluding_vat),
          tax: minor(line_item.included_tax_total + line_item.additional_tax_total)
        )
      end
    end

    def shipment_items
      @order.shipments.map do |shipment|
        item(
          reference: "shipping-#{shipment.number || shipment.id}",
          name: shipment_name(shipment),
          net: minor(shipment.total_excluding_vat),
          tax: minor(shipment.included_tax_total + shipment.additional_tax_total)
        )
      end
    end

    def order_adjustment_items
      @order.adjustments.reject(&:marked_for_destruction?).filter_map do |adjustment|
        next if adjustment.included?

        amount = minor(adjustment.amount)
        next if amount.zero?

        tax = adjustment.tax? ? amount : 0
        item(
          reference: "adjustment-#{adjustment.id || adjustment.source_type.to_s.parameterize}",
          name: adjustment.label.presence || "Order adjustment",
          net: amount - tax,
          tax:
        )
      end
    end

    def append_balance_item!(items, difference)
      return if difference.zero?

      items << item(
        reference: "solidus-payment-balance",
        name: difference.negative? ? "Solidus credits and discounts" : "Solidus order adjustment",
        net: difference,
        tax: 0
      )
    end

    def item(reference:, name:, net:, tax:)
      gross = net + tax
      {
        reference: clean(reference, fallback: "solidus-item"),
        name: clean(name, fallback: "Solidus item"),
        quantity: 1,
        unit: "pcs",
        unitPrice: net,
        taxRate: tax_rate(net, tax),
        taxAmount: tax,
        grossTotalAmount: gross,
        netTotalAmount: net
      }
    end

    def minor(amount)
      Nexi::Money.to_minor(amount, @currency)
    end

    def tax_rate(net, tax)
      return 0 unless net.positive? && tax.positive?

      ((BigDecimal(tax.to_s) * 10_000) / net).round.to_i.clamp(0, 99_999)
    end

    def shipment_name(shipment)
      shipment.selected_shipping_rate&.name.presence || "Shipping"
    end

    def clean(value, fallback:)
      self.class.sanitize(value, fallback:)
    end
  end
end
