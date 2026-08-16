# frozen_string_literal: true

module SolidusNexi
  module Nexi
    module Webhook
      Event = Data.define(:id, :name, :occurred_at, :merchant_id, :merchant_number, :payment_id,
        :charge_id, :refund_id, :order_reference)
    end
  end
end
