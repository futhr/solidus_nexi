# frozen_string_literal: true

class CreateSolidusNexiPaymentSources < ActiveRecord::Migration[7.0]
  def change
    create_table :solidus_nexi_payment_sources do |table|
      table.references :payment_method, null: false, foreign_key: {to_table: :spree_payment_methods}
      table.string :provider_payment_id
      table.string :provider_charge_id
      table.string :provider_status
      table.string :currency, limit: 3, null: false
      table.integer :reserved_amount_minor, null: false, default: 0
      table.integer :charged_amount_minor, null: false, default: 0
      table.integer :refunded_amount_minor, null: false, default: 0
      table.integer :cancelled_amount_minor, null: false, default: 0
      table.string :hosted_payment_page_url, limit: 2048
      table.string :return_token, null: false
      table.datetime :checkout_expires_at
      table.datetime :last_reconciled_at
      table.timestamps
    end

    add_index :solidus_nexi_payment_sources, :return_token, unique: true
    add_index :solidus_nexi_payment_sources,
      [:payment_method_id, :provider_payment_id],
      unique: true,
      where: "provider_payment_id IS NOT NULL",
      name: "idx_solidus_nexi_sources_provider_payment"
  end
end
