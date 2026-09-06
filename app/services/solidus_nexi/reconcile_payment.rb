# frozen_string_literal: true

module SolidusNexi
  class ReconcilePayment
    Result = Data.define(:payment, :source, :mapping)
    LOCAL_MUTATION_GRACE = 30.seconds

    def initialize(source: nil, payment_method: nil, provider_payment_id: nil,
      order_reference: nil, event_name: nil, event_charge_id: nil, event_refund_id: nil)
      @source = source
      @payment_method = payment_method || source&.payment_method
      @provider_payment_id = provider_payment_id || source&.provider_payment_id
      @order_reference = order_reference
      @event_name = event_name
      @event_charge_id = event_charge_id
      @event_refund_id = event_refund_id
    end

    def call
      validate_input!
      response = client.retrieve_payment(payment_id: @provider_payment_id)
      snapshot = Nexi::PaymentSnapshot.new(response.body, expected_payment_id: @provider_payment_id)
      amounts = snapshot.amounts
      @source ||= recover_source(snapshot)
      return Result.new(payment: nil, source: nil, mapping: nil) unless @source

      payment = payment_for(@source)
      validate_order!(payment, snapshot)
      CheckoutContext.verify!(payment:, source: @source)
      mapping = initial_mapping(snapshot)

      payment.with_lock do
        validate_snapshot_fresh!(amounts)
        refund_outcome = reconcile_operations!(payment, snapshot, amounts)
        mapping = refund_outcome.mapping || mapping
        if recent_local_mutation?(payment)
          update_source!(snapshot, amounts, mapping)
          ReconcilePaymentJob.set(wait: LOCAL_MUTATION_GRACE).perform_later(@source.id)
        else
          mapping = mapping_for_payment(payment, mapping)
          update_source!(snapshot, amounts, mapping)
          ReconcileFinancialRecords.new(payment:, snapshot:).call
          apply_payment_state!(payment, mapping)
        end
      end

      Result.new(payment:, source: @source, mapping:)
    end

    private

    def validate_snapshot_fresh!(amounts)
      @source.reload
      if amounts[:charged] < @source.charged_amount_minor || amounts[:refunded] < @source.refunded_amount_minor ||
          amounts[:cancelled] < @source.cancelled_amount_minor
        raise Nexi::ProviderUnavailableError, "Nexi returned an older financial snapshot; retry reconciliation"
      end
    end

    def initial_mapping(snapshot)
      Nexi::StateMapper.new.map(
        summary: snapshot.summary,
        expected_amount_minor: snapshot.amount_minor,
        event_name: @event_name
      )
    end

    def validate_input!
      unless @payment_method.is_a?(PaymentMethod) && @provider_payment_id.present?
        raise Nexi::ValidationError, "payment method and provider payment ID are required"
      end
      return unless @source

      if @source.payment_method != @payment_method ||
          (@source.provider_payment_id.present? && @source.provider_payment_id != @provider_payment_id)
        raise Nexi::ConflictError, "Nexi source is already bound to another payment or payment method"
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
        validate_order!(payment, snapshot)
        initial_mapping(snapshot)
        CheckoutContext.verify!(payment:, source: payment.source)
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
      validate_event_reference!(snapshot)
      if snapshot.my_reference.present? && snapshot.my_reference != payment.number
        raise Nexi::ConflictError, "Nexi payment reference does not match the Solidus payment"
      end
      local_amount = Nexi::Money.to_minor(payment.amount, payment.currency)
      unless snapshot.amount_minor == local_amount && snapshot.currency == payment.currency
        raise Nexi::ConflictError, "Nexi payment does not match the Solidus payment"
      end
      if snapshot.order_reference != OrderSerializer.order_reference(payment.order.number)
        raise Nexi::ConflictError, "Nexi payment has a different order reference"
      end
      if @event_charge_id.present? && snapshot.charge_id.present? && @event_charge_id != snapshot.charge_id
        raise Nexi::ConflictError, "webhook charge does not match the Nexi payment"
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
      refund_outcome = RefundReconciliation.new(
        payment:,
        snapshot:,
        amounts:,
        event_name: @event_name,
        event_refund_id: @event_refund_id
      ).call
      Operation.requiring_reconciliation.where(payment:).where.not(kind: "refund").find_each do |operation|
        fulfilled = case operation.kind
        when "create" then true
        when "charge" then amounts[:charged] >= operation.amount_minor
        when "cancel" then amounts[:cancelled] >= operation.amount_minor
        end
        next unless fulfilled

        operation.update!(
          provider_payment_id: snapshot.payment_id,
          provider_charge_id: snapshot.charge_id || operation.provider_charge_id
        )
        operation.mark_reconciled!
      end
      refund_outcome
    end

    def recent_local_mutation?(payment)
      Operation.where(payment:, kind: %w[charge cancel refund], status: %w[dispatched accepted succeeded])
        .exists?(updated_at: LOCAL_MUTATION_GRACE.ago..)
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

    def client
      @client ||= SolidusNexi.configuration.client_factory.call(@payment_method)
    end
  end
end
