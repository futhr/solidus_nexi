# frozen_string_literal: true

module SolidusNexi
  class WebhooksController < ApplicationController
    skip_forgery_protection

    def create
      payment_method = PaymentMethod.find(params[:payment_method_id])
      unless payment_method.webhook_authenticator.valid?(request.authorization)
        return head :unauthorized
      end

      event = Nexi::Webhook::Parser.new.parse(request.raw_post)
      receipt, created = WebhookReceipt.record!(payment_method:, event:)
      if created || receipt.enqueue_required?
        ProcessWebhookJob.perform_later(receipt.id)
        receipt.mark_enqueued!
      end

      head :ok
    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue Nexi::ValidationError, Nexi::ConfigurationError
      head :bad_request
    end
  end
end
