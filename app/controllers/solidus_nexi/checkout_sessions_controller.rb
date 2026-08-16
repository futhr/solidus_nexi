# frozen_string_literal: true

require "digest"
require "uri"

module SolidusNexi
  class CheckoutSessionsController < ApplicationController
    def create
      order = Spree::Order.incomplete.find_by!(number: params.require(:order_number))
      authenticate_order!(order)
      payment_method = PaymentMethod.active.available_to_store(order.store).find(params.require(:payment_method_id))

      result = CreateCheckout.new(
        order:,
        payment_method:,
        webhook_url: absolute_url(SolidusNexi::Engine.routes.url_helpers.webhook_path(payment_method)),
        return_url_for: ->(source) { absolute_url(SolidusNexi::Engine.routes.url_helpers.return_path(source.return_token)) },
        cancel_url_for: ->(source) { absolute_url(SolidusNexi::Engine.routes.url_helpers.cancel_path(source.return_token)) }
      ).call

      respond_to do |format|
        format.json do
          render json: {
            payment_id: result.payment.number,
            provider_payment_id: result.provider_payment_id,
            checkout_url: result.hosted_payment_page_url,
            reused: result.reused
          }, status: result.reused ? :ok : :created
        end
        format.any { redirect_to result.hosted_payment_page_url, allow_other_host: true, status: :see_other }
      end
    rescue ActiveRecord::RecordNotFound
      render_problem("order or payment method was not found", :not_found)
    rescue ActionController::ParameterMissing, Nexi::ValidationError, Nexi::ConfigurationError => error
      render_problem(error.message, :unprocessable_entity)
    rescue Nexi::OperationInProgress, Nexi::ConflictError, Nexi::ReconciliationRequired => error
      render_problem(error.message, :conflict)
    rescue Nexi::Error
      render_problem("Nexi Checkout is temporarily unavailable", :bad_gateway)
    end

    private

    def authenticate_order!(order)
      supplied = params[:guest_token].to_s
      expected = order.guest_token.to_s
      valid = supplied.present? && expected.present? && ActiveSupport::SecurityUtils.secure_compare(
        Digest::SHA256.hexdigest(supplied),
        Digest::SHA256.hexdigest(expected)
      )
      raise ActiveRecord::RecordNotFound unless valid
    end

    def absolute_url(path)
      base = SolidusNexi.configuration.public_base_url.to_s
      uri = URI.join(base.end_with?("/") ? base : "#{base}/", path.delete_prefix("/"))
      unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
        raise Nexi::ConfigurationError, "NEXI_CHECKOUT_PUBLIC_BASE_URL must be an HTTPS origin"
      end

      uri.to_s
    rescue URI::InvalidURIError
      raise Nexi::ConfigurationError, "NEXI_CHECKOUT_PUBLIC_BASE_URL must be a valid HTTPS origin"
    end

    def render_problem(message, status)
      render json: {error: message}, status:
    end
  end
end
