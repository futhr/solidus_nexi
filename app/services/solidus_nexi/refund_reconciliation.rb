# frozen_string_literal: true

module SolidusNexi
  class RefundReconciliation
    Result = Data.define(:status, :provider_refund_id) do
      def mapping
        attributes = case status
        when :pending then ["completed", true, "refund_pending"]
        when :failed then ["completed", false, "refund_failed"]
        when :unknown then ["completed", true, "refund_outcome_unknown"]
        when :unexpected_pending then [nil, true, "unexpected_refund_pending"]
        when :unexpected_failure then [nil, true, "unexpected_refund_failure"]
        end
        return unless attributes

        Nexi::StateMapper::Mapping.new(
          target_state: attributes[0],
          reconciliation_required: attributes[1],
          reason: attributes[2]
        )
      end
    end
    PENDING_STATES = %w[initiated pending].freeze

    def initialize(payment:, snapshot:, amounts:, event_name: nil, event_refund_id: nil)
      @payment = payment
      @snapshot = snapshot
      @amounts = amounts
      @event_name = event_name
      @event_refund_id = event_refund_id
    end

    def call
      results = candidate_operations.map { |operation| reconcile(operation) }
      results << unmatched_provider_outcome
      results.max_by { |result| outcome_priority(result.status) }
    end

    private

    def candidate_operations
      Operation.where(payment: @payment, kind: "refund")
        .where(<<~SQL.squish)
          reconciliation_required = TRUE
          OR status IN ('accepted', 'succeeded')
          OR (status = 'rejected' AND provider_code = 'refund_failed')
        SQL
        .order(:created_at)
    end

    def reconcile(operation)
      refund_id = provider_refund_id(operation)
      state = @snapshot.refund_state_for(refund_id)

      if operation.status == "rejected" && operation.provider_code == "refund_failed"
        remove_failed_local_refund!(operation, refund_id)
        return Result.new(status: :failed, provider_refund_id: refund_id)
      end

      if completed?(operation, refund_id, state)
        reconcile_completed!(operation, refund_id)
        return Result.new(status: :completed, provider_refund_id: refund_id)
      end
      if failed?(refund_id, state)
        reconcile_failed!(operation, refund_id)
        return Result.new(status: :failed, provider_refund_id: refund_id)
      end
      if refund_id && (PENDING_STATES.include?(state) || operation.status == "accepted")
        mark_pending!(operation, refund_id)
        return Result.new(status: :pending, provider_refund_id: refund_id)
      end

      Result.new(status: :unknown, provider_refund_id: refund_id)
    end

    def provider_refund_id(operation)
      return operation.provider_refund_id if operation.provider_refund_id.present?
      return @event_refund_id if @event_refund_id.present?

      @snapshot.completed_refund_id || @snapshot.refund_id
    end

    def completed?(operation, refund_id, state)
      @amounts[:refunded] >= operation.amount_minor &&
        refund_id.present? &&
        (state == "completed" || @snapshot.completed_refund_id == refund_id)
    end

    def failed?(refund_id, state)
      return true if state == "failed"

      @event_name == "payment.refund.failed" &&
        @event_refund_id.present? && @event_refund_id == refund_id
    end

    def reconcile_completed!(operation, refund_id)
      bind_provider_identity!(operation, refund_id)
      reconcile_local_refund!(operation, refund_id)
      operation.mark_reconciled!
    end

    def reconcile_failed!(operation, refund_id)
      bind_provider_identity!(operation, refund_id)
      remove_failed_local_refund!(operation, refund_id)
      operation.mark_rejected!(Nexi::Error.new("Nexi refund failed", provider_code: "refund_failed"))
    end

    def mark_pending!(operation, refund_id)
      operation.mark_accepted!(
        provider_request_id: operation.provider_request_id,
        provider_payment_id: @snapshot.payment_id,
        provider_charge_id: @snapshot.charge_id || operation.provider_charge_id,
        provider_refund_id: refund_id
      )
    end

    def bind_provider_identity!(operation, refund_id)
      operation.update!(
        provider_payment_id: @snapshot.payment_id,
        provider_charge_id: @snapshot.charge_id || operation.provider_charge_id,
        provider_refund_id: refund_id
      )
    end

    def reconcile_local_refund!(operation, refund_id)
      refund = local_refund(operation, refund_id)
      refund.update!(transaction_id: refund_id) if refund && refund.transaction_id.blank?
    end

    def remove_failed_local_refund!(operation, refund_id)
      refund = local_refund(operation, refund_id)
      return unless refund

      local_amount = Nexi::Money.to_minor(refund.amount, operation.currency)
      unless local_amount == operation.amount_minor
        raise Nexi::ConflictError, "failed Nexi refund does not match the local refund"
      end

      reimbursement = refund.reimbursement
      refund.log_entries.delete_all
      refund.destroy!
      reimbursement&.update!(reimbursement_status: "errored")
      @payment.order.recalculate
    end

    def local_refund(operation, refund_id)
      by_transaction = @payment.refunds.find_by(transaction_id: refund_id)
      return by_transaction if by_transaction

      refund_id_from_reference = operation.logical_reference.delete_prefix("refund:")
      return unless /\A[1-9][0-9]*\z/.match?(refund_id_from_reference)

      @payment.refunds.find_by(id: refund_id_from_reference)
    end

    def unmatched_provider_outcome
      state = @snapshot.refund_state_for(@event_refund_id) if @event_refund_id
      if @event_name == "payment.refund.failed" || state == "failed"
        return Result.new(status: :unexpected_failure, provider_refund_id: @event_refund_id)
      end
      pending_id = @snapshot.refund_id_with_state(*PENDING_STATES)
      if @event_name == "payment.refund.initiated.v2" || pending_id
        return Result.new(status: :unexpected_pending, provider_refund_id: @event_refund_id || pending_id)
      end

      Result.new(status: :none, provider_refund_id: nil)
    end

    def outcome_priority(status)
      %i[none unknown unexpected_pending pending unexpected_failure failed completed].index(status) || 0
    end
  end
end
