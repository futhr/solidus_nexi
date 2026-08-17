# frozen_string_literal: true

class AddOperationIdsToSolidusNexiWebhookReceipts < ActiveRecord::Migration[7.0]
  def change
    change_table :solidus_nexi_webhook_receipts, bulk: true do |table|
      table.string :provider_charge_id, limit: 128
      table.string :provider_refund_id, limit: 128
    end

    add_index :solidus_nexi_webhook_receipts, :provider_refund_id,
      name: "idx_solidus_nexi_webhooks_provider_refund"
  end
end
