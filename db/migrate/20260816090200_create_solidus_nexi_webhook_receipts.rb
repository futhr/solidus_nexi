# frozen_string_literal: true

class CreateSolidusNexiWebhookReceipts < ActiveRecord::Migration[7.0]
  def change
    create_table :solidus_nexi_webhook_receipts do |table|
      table.references :payment_method,
        type: :integer,
        null: false,
        foreign_key: {to_table: :spree_payment_methods}
      table.string :event_id, null: false
      table.string :event_name, null: false
      table.string :provider_payment_id, null: false
      table.string :order_reference
      table.string :merchant_id, null: false
      table.datetime :occurred_at, null: false
      table.string :status, null: false, default: "received"
      table.integer :attempts, null: false, default: 0
      table.string :error_class
      table.datetime :processed_at
      table.timestamps
    end

    add_index :solidus_nexi_webhook_receipts,
      [:payment_method_id, :event_id],
      unique: true,
      name: "idx_solidus_nexi_webhooks_account_event"
    add_index :solidus_nexi_webhook_receipts,
      [:payment_method_id, :provider_payment_id],
      name: "idx_solidus_nexi_webhooks_provider_payment"
  end
end
