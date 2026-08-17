# frozen_string_literal: true

class AddReconciliationRequiredToSolidusNexiPaymentSources < ActiveRecord::Migration[7.0]
  def change
    add_column :solidus_nexi_payment_sources, :reconciliation_required, :boolean, null: false, default: false
    add_index :solidus_nexi_payment_sources,
      :reconciliation_required,
      where: "reconciliation_required = true",
      name: "idx_solidus_nexi_sources_reconciliation"
  end
end
