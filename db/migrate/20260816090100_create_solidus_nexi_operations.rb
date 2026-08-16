# frozen_string_literal: true

class CreateSolidusNexiOperations < ActiveRecord::Migration[7.0]
  def change
    create_table :solidus_nexi_operations do |table|
      table.references :payment, null: false, foreign_key: {to_table: :spree_payments}
      table.string :kind, null: false
      table.string :logical_reference, null: false
      table.integer :amount_minor, null: false
      table.string :currency, limit: 3, null: false
      table.string :idempotency_key
      table.string :request_fingerprint, null: false, limit: 64
      table.string :provider_payment_id
      table.string :provider_charge_id
      table.string :provider_refund_id
      table.string :provider_request_id
      table.string :provider_code
      table.string :status, null: false, default: "pending"
      table.boolean :reconciliation_required, null: false, default: false
      table.datetime :dispatched_at
      table.datetime :completed_at
      table.timestamps
    end

    add_index :solidus_nexi_operations,
      [:payment_id, :kind, :logical_reference],
      unique: true,
      name: "idx_solidus_nexi_operations_logical_intent"
    add_index :solidus_nexi_operations,
      :idempotency_key,
      unique: true,
      where: "idempotency_key IS NOT NULL"
    add_index :solidus_nexi_operations, :provider_payment_id
  end
end
