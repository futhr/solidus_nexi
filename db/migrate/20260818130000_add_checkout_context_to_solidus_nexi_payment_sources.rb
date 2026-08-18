# frozen_string_literal: true

class AddCheckoutContextToSolidusNexiPaymentSources < ActiveRecord::Migration[7.0]
  def change
    add_column :solidus_nexi_payment_sources, :checkout_context_fingerprint, :string, limit: 64
    add_check_constraint :solidus_nexi_payment_sources,
      "checkout_context_fingerprint IS NULL OR LENGTH(checkout_context_fingerprint) = 64",
      name: "solidus_nexi_sources_checkout_context_length"
  end
end
