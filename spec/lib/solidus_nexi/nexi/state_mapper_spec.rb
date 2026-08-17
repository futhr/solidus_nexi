# frozen_string_literal: true

RSpec.describe SolidusNexi::Nexi::StateMapper do
  subject(:mapper) { described_class.new }

  it "maps a full reservation to pending" do
    result = mapper.map(summary: {"reservedAmount" => 10_000}, expected_amount_minor: 10_000)
    expect(result).to have_attributes(target_state: "pending", reconciliation_required: false)
  end

  it "maps a full charge to completed" do
    result = mapper.map(summary: {"chargedAmount" => 10_000}, expected_amount_minor: 10_000)
    expect(result.target_state).to eq("completed")
  end

  it "does not pretend a partial charge is supported" do
    result = mapper.map(summary: {"chargedAmount" => 5_000}, expected_amount_minor: 10_000)
    expect(result).to have_attributes(target_state: nil, reconciliation_required: true,
      reason: "unexpected_partial_charge")
  end

  it "maps full and partial cancellation without inventing financial state" do
    full = mapper.map(summary: {"cancelledAmount" => 10_000}, expected_amount_minor: 10_000)
    partial = mapper.map(summary: {"cancelledAmount" => 5_000}, expected_amount_minor: 10_000)

    expect(full).to have_attributes(target_state: "void", reconciliation_required: false)
    expect(partial).to have_attributes(
      target_state: nil,
      reconciliation_required: true,
      reason: "unexpected_partial_cancel"
    )
  end

  it "requires reconciliation for a partial reservation or non-final provider state" do
    partial = mapper.map(summary: {"reservedAmount" => 5_000}, expected_amount_minor: 10_000)
    empty = mapper.map(summary: {}, expected_amount_minor: 10_000)

    expect(partial.reason).to eq("unexpected_partial_reservation")
    expect(empty.reason).to eq("provider_state_not_final")
  end

  it "maps a provider failure only before any financial operation succeeded" do
    result = mapper.map(
      summary: {},
      expected_amount_minor: 10_000,
      event_name: "payment.reservation.failed"
    )

    expect(result).to have_attributes(target_state: "failed", reconciliation_required: false)
  end

  it "rejects impossible, negative, and malformed summaries" do
    expect do
      mapper.map(summary: {"chargedAmount" => -1}, expected_amount_minor: 10_000)
    end.to raise_error(SolidusNexi::Nexi::MalformedResponseError, /negative/)

    expect do
      mapper.map(summary: {"reservedAmount" => 10_001}, expected_amount_minor: 10_000)
    end.to raise_error(SolidusNexi::Nexi::MalformedResponseError, /exceeds/)

    expect do
      mapper.map(summary: {"chargedAmount" => 100, "refundedAmount" => 101}, expected_amount_minor: 10_000)
    end.to raise_error(SolidusNexi::Nexi::MalformedResponseError, /refunded/)

    expect do
      mapper.map(summary: {"chargedAmount" => "invalid"}, expected_amount_minor: 10_000)
    end.to raise_error(SolidusNexi::Nexi::MalformedResponseError, /chargedAmount/)
  end

  it "prevents late events from regressing terminal Solidus state" do
    expect(mapper.transition_allowed?("completed", "pending")).to be(false)
    expect(mapper.transition_allowed?("void", "completed")).to be(false)
  end

  it "allows only the declared forward Solidus transitions" do
    expect(mapper.transition_allowed?("checkout", "pending")).to be(true)
    expect(mapper.transition_allowed?("pending", "completed")).to be(true)
    expect(mapper.transition_allowed?("pending", "checkout")).to be(false)
    expect(mapper.transition_allowed?("unknown", "completed")).to be(false)
  end
end
