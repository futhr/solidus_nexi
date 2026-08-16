# frozen_string_literal: true

module SolidusNexi
  class ReturnsController < ApplicationController
    def show
      return_to_storefront(:return_path_resolver)
    end

    def cancel
      return_to_storefront(:cancel_path_resolver)
    end

    private

    def return_to_storefront(resolver)
      source = PaymentSource.find_by!(return_token: params[:token])
      ReconcilePaymentJob.perform_later(source.id) if source.provider_payment_id.present?
      location = SolidusNexi.configuration.public_send(resolver).call(source)
      redirect_to location, allow_other_host: false, status: :see_other
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end
  end
end
