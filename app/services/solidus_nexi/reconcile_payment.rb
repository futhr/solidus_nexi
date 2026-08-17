# frozen_string_literal: true

module SolidusNexi
  class ReconcilePayment
    Result = Data.define(:payment, :source, :mapping)
    LOCAL_MUTATION_GRACE = 30.seconds

    def initialize(source: nil, payment_method: nil, provider_payment_id: nil,
      order_reference: nil, event_name: nil)
      @source = source
      @payment_method = payment_method || source&.payment_method
      @provider_payment_id = provider_payment_id || source&.provider_payment_id
      @order_reference = order_reference
      @event_name = event_name
    end

    def call
      validate_input!
      response = client.retrieve_payment(payment_id: @provider_payment_id)
      snapshot = Nexi::PaymentSnapshot.new(response.body, expected_payment_id: @provider_payment_id)
      @source ||= recover_source(snapshot)
      return Result.new(payment: nil, source: nil, mapping: nil) unless @source

      payment = payment_for(@source)
      validate_order!(payment, snapshot)
      amounts = snapshot.amounts
      mapping = Nexi::StateMapper.new.map(
        summary: snapshot.summary,
        expected_amount_minor: snapshot.amount_minor,
        event_name: @event_name
      )

      payment.with_lock do
        payment.reload
        reconcile_operations!(payment, snapshot, amounts)
        if recent_local_mutation?(payment)
          update_source!(snapshot, amounts, mapping)
          ReconcilePaymentJob.set(wait: LOCAL_MUTATION_GRACE).perform_later(@source.id)
        else
          mapping = mapping_for_payment(payment, mapping)
          update_source!(snapshot, amounts, mapping)
          apply_financial_records!(payment, snapshot, amounts)
          apply_payment_state!(payment, mapping)
        end
      end

      Result.new(payment:, source: @source, mapping:)
    end

    private

    def validate_input!
      unless @payment_method.is_a?(PaymentMethod) && @provider_payment_id.present?
        raise Nexi::ValidationError, "payment method and provider payment ID are required"
      end
    end

    def recover_source(snapshot)
      known_source = PaymentSource.find_by(
        payment_method: @payment_method,
        provider_payment_id: @provider_payment_id
      )
      return known_source if known_source

      payment = recoverable_payment(snapshot)
      return unless payment

      payment.source.with_lock do
        payment.source.reload
        if payment.source.provider_payment_id.blank?
          payment.source.update!(provider_payment_id: @provider_payment_id, provider_status: "recovered")
          payment.update!(response_code: @provider_payment_id)
        elsif payment.source.provider_payment_id != @provider_payment_id
          raise Nexi::ConflictError, "Nexi payment is already bound to another checkout"
        end
      end
      payment.source
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      PaymentSource.find_by(
        payment_method: @payment_method,
        provider_payment_id: @provider_payment_id
      ) || raise
    end

    def recoverable_payment(snapshot)
      validate_event_reference!(snapshot)
      return payment_from_provider_reference!(snapshot) if snapshot.my_reference.present?

      order = Spree::Order.find_by(number: snapshot.order_reference)
      return unless order

      candidates = eligible_payments(order).select { |payment| payment.source.provider_payment_id.blank? }
      candidates.one? ? candidates.first : nil
    end

    def payment_from_provider_reference!(snapshot)
      payment = Spree::Payment.find_by(number: snapshot.my_reference)
      unless payment && eligible_payment?(payment) && provider_order_matches?(payment, snapshot)
        raise Nexi::ConflictError, "Nexi payment reference does not match a recoverable Solidus payment"
      end

      payment
    end

    def eligible_payments(order)
      order.payments
        .where(payment_method: @payment_method, source_type: "SolidusNexi::PaymentSource")
        .where(state: %w[checkout processing pending completed])
        .includes(:source)
        .to_a
    end

    def eligible_payment?(payment)
      payment.payment_method == @payment_method &&
        payment.source_type == "SolidusNexi::PaymentSource" &&
        %w[checkout processing pending completed].include?(payment.state)
    end

    def validate_event_reference!(snapshot)
      return if @order_reference.blank? || @order_reference == snapshot.order_reference

      raise Nexi::ConflictError, "webhook order reference does not match the Nexi payment"
    end

    def provider_order_matches?(payment, snapshot)
      snapshot.order_reference == OrderSerializer.order_reference(payment.order.number)
    end

    def payment_for(source)
      source.payments.where(payment_method: @payment_method).order(created_at: :desc).first ||
        raise(Nexi::ReconciliationRequired, "Nexi source has no Solidus payment")
    end

    def validate_order!(payment, snapshot)
      local_amount = Nexi::Money.to_minor(payment.amount, payment.currency)
      unless snapshot.amount_minor == local_amount && snapshot.currency == payment.currency
        raise Nexi::ConflictError, "Nexi payment does not match the Solidus payment"
      end
      if snapshot.order_reference != OrderSerializer.order_reference(payment.order.number)
        raise Nexi::ConflictError, "Nexi payment has a different order reference"
      end
    end

    def update_source!(snapshot, amounts, mapping)
      @source.update!(
        provider_payment_id: snapshot.payment_id,
        provider_charge_id: snapshot.charge_id || @source.provider_charge_id,
        provider_status: mapping.reason,
        reserved_amount_minor: amounts[:reserved],
        charged_amount_minor: amounts[:charged],
        refunded_amount_minor: amounts[:refunded],
        cancelled_amount_minor: amounts[:cancelled],
        reconciliation_required: mapping.reconciliation_required,
        last_reconciled_at: Time.current
      )
    end

    def mapping_for_payment(payment, mapping)
      target = mapping.target_state
      return mapping if target.blank? || payment.state == target
      return mapping if Nexi::StateMapper.new.transition_allowed?(payment.state, target)

      Nexi::StateMapper::Mapping.new(
        target_state: nil,
        reconciliation_required: true,
        reason: "local_state_conflict"
      )
    end

    def reconcile_operations!(payment, snapshot, amounts)
      Operation.requiring_reconciliation.where(payment:).find_each do |operation|
        fulfilled = case operation.kind
        when "create" then true
        when "charge" then amounts[:charged] >= operation.amount_minor
        when "cancel" then amounts[:cancelled] >= operation.amount_minor
        when "refund" then amounts[:refunded] >= operation.amount_minor
        end
        next unless fulfilled

        operation.update!(
          provider_payment_id: snapshot.payment_id,
          provider_charge_id: snapshot.charge_id || operation.provider_charge_id,
          provider_refund_id: snapshot.refund_id || operation.provider_refund_id
        )
        reconcile_local_refund!(operation, snapshot) if operation.kind == "refund"
        operation.mark_reconciled!
      end
    end

    def reconcile_local_refund!(operation, snapshot)
      refund_id = operation.logical_reference.delete_prefix("refund:")
      refund = Spree::Refund.find_by(id: refund_id, payment: operation.payment)
      return unless refund && refund.transaction_id.blank?

      refund.update!(transaction_id: snapshot.refund_id || operation.provider_refund_id)
    end

    def recent_local_mutation?(payment)
      Operation.where(payment:, kind: %w[charge cancel refund], status: %w[dispatched succeeded])
        .exists?(updated_at: LOCAL_MUTATION_GRACE.ago..)
    end

    def apply_financial_records!(payment, snapshot, amounts)
      captured_minor = Nexi::Money.to_minor(payment.capture_events.sum(:amount), payment.currency)
      if amounts[:charged] > captured_minor
        payment.capture_events.create!(amount: decimal_amount(amounts[:charged] - captured_minor))
      end

      refunded_minor = Nexi::Money.to_minor(payment.refunds.sum(:amount), payment.currency)
      return unless amounts[:refunded] > refunded_minor

      refund_id = snapshot.completed_refund_id || snapshot.refund_id
      raise Nexi::ReconciliationRequired, "Nexi refund is missing its identifier" unless refund_id

      reason = Spree::RefundReason.where(name: "Nexi reconciliation").first_or_create!
      payment.refunds.create!(
        amount: decimal_amount(amounts[:refunded] - refunded_minor),
        reason:,
        transaction_id: refund_id
      )
    end

    def apply_payment_state!(payment, mapping)
      target = mapping.target_state
      return if target.blank? || payment.state == target
      return unless Nexi::StateMapper.new.transition_allowed?(payment.state, target)

      case target
      when "pending" then payment.pend!
      when "completed" then payment.complete!
      when "void" then payment.void!
      when "failed"
        payment.started_processing! if payment.checkout?
        payment.failure!
      end
    end

    def decimal_amount(amount_minor)
      BigDecimal(amount_minor.to_s) / 100
    end

    def client
      @client ||= SolidusNexi.configuration.client_factory.call(@payment_method)
    end
  end
end
